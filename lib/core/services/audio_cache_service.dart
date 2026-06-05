import 'dart:convert';
import 'package:zyp_music/core/utils/app_logger.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/datasources/local/playlist_database.dart';
import '../../domain/entities/album.dart';
import '../../domain/entities/video.dart';
import '../../domain/repositories/audio_repository.dart';
import 'hybrid_cache_service.dart';

class AudioCacheService {
  static const int _maxCachedItems = 200;
  static const String _prefsKey = 'audio_cache_lru';

  /// Optional notifier fired after a stream write completes successfully.
  /// Receives the `(trackId, finalFilePath)` so the caller can register the
  /// new cache entry in its own index (e.g. a Hive box) without coupling
  /// this service to that index.
  ///
  /// Errors raised inside the callback are swallowed; the file is already
  /// on disk and the next reconcile pass can pick it up if the index update
  /// did not land.
  Future<void> Function(String trackId, String filePath)? onCacheSuccess;

  /// Late-bound collaborators for the independent background downloader
  /// and the Hive-to-SQLite cache migration hook. Wired in `main.dart`
  /// after every collaborator it depends on is constructed. The downloader
  /// task is a no-op when these are unset, which keeps the constructor
  /// parameter-free and the service usable in isolation (e.g. from the
  /// settings screen's `clearCache()` call site).
  AudioRepository? _audioRepository;
  HybridCacheService? _hybridCache;
  PlaylistDatabase? _libraryDatabase;

  /// Hooks the collaborators required by [downloadTrackIndependent] and
  /// [migrateToLibrary] / [migrateAlbumToLibrary]. Safe to call multiple
  /// times — the latest call wins.
  void attachDownloadCollaborators({
    required AudioRepository audioRepository,
    required HybridCacheService hybridCache,
    required PlaylistDatabase libraryDatabase,
  }) {
    _audioRepository = audioRepository;
    _hybridCache = hybridCache;
    _libraryDatabase = libraryDatabase;
  }

  /// Returns the local file URI if the track is cached, otherwise null.
  Future<String?> getCachedUri(String trackId) async {
    try {
      final cacheDir = await _getCacheDir();
      if (!await cacheDir.exists()) return null;

      final files = cacheDir.listSync().whereType<File>().where((file) {
        final name = file.path.split('/').last;
        return name.startsWith('$trackId.');
      }).toList();

      if (files.isNotEmpty) {
        final file = files.first;
        if (await file.length() > 0) {
          await _updateAccessTime(trackId);
          return file.uri.toString();
        } else {
          // Clean up empty files
          await file.delete();
        }
      }
    } catch (e) {
      AppLogger.log('Error reading cache: $e', name: 'AudioCacheService');
    }
    return null;
  }

  /// Downloads the stream in the background and saves it to the cache.
  Future<void> cacheStream(String trackId, String streamUrl) async {
    try {
      final cacheDir = await _getCacheDir();

      // Determine file extension based on streamUrl
      String ext = 'mp3';
      final lowerUrl = streamUrl.toLowerCase();
      if (lowerUrl.contains('.flac')) {
        ext = 'flac';
      } else if (lowerUrl.contains('.webm')) {
        ext = 'webm';
      } else if (lowerUrl.contains('.mp4') || lowerUrl.contains('.m4a') || lowerUrl.contains('.aac')) {
        ext = 'm4a';
      }

      final file = File('${cacheDir.path}/$trackId.$ext');

      final existingUri = await getCachedUri(trackId);
      if (existingUri != null) {
        return;
      }

      // Download file to temp location first
      final tmpFile = File('${cacheDir.path}/$trackId.tmp');
      final response = await http.get(
        Uri.parse(streamUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
        },
      );
      if (response.statusCode == 200) {
        await tmpFile.writeAsBytes(response.bodyBytes);
        await tmpFile.rename(file.path);
        await _updateAccessTime(trackId);
        await _enforceCacheLimit();
        final hook = onCacheSuccess;
        if (hook != null) {
          try {
            await hook(trackId, file.path);
          } catch (e) {
            AppLogger.log('onCacheSuccess hook failed for $trackId: $e',
                name: 'AudioCacheService');
          }
        }
      }
    } catch (e) {
      AppLogger.log('Error caching stream: $e', name: 'AudioCacheService');
    }
  }

  /// Background, non-playing download entry point. Invoked by the
  /// download icon and the album-save action. Bypasses the active audio
  /// player completely — the network stream URL is resolved and the
  /// audio bytes are written to the cache directory without ever
  /// touching the `MusicAudioHandler` queue, the playback session, or
  /// the seek bar.
  ///
  /// Spec execution flow (lifted verbatim from the non-playing
  /// downloader spec):
  ///
  ///   1. Instantly flip the cache state to `caching` so the download
  ///      icon switches to the spinner in the same frame the user
  ///      pressed it. Bails out if the Hive box already has the track
  ///      (explicit Hive pre-check) or, when [writeToLibraryOnSuccess]
  ///      is `true`, the SQLite library already has it.
  ///   2. Resolve the network stream URL directly from the audio
  ///      repository (which already wraps the YouTube extractor). The
  ///      player is never asked to load or play the stream.
  ///   3. Fire the audio file write and the timed-lyrics fetch in
  ///      parallel. The audio write goes through [cacheStream] and the
  ///      lyrics fetch goes through the repository's write-time
  ///      validation pass. A failed lyrics fetch never aborts the
  ///      audio cache write (mirrors the prebuffer behaviour).
  ///   4. The Hive validation tracker is fired by the `onCacheSuccess`
  ///      hook that the wiring code installs, which also flips the
  ///      icon to the success checkmark. If the file write did not
  ///      actually land on disk the transient caching flag is cleared
  ///      so the UI does not stay stuck on the spinner.
  ///   5. When [writeToLibraryOnSuccess] is `true`, the verified
  ///      success token is written straight into SQLite
  ///      (`downloaded_tracks`) and the Hive entry is gently evicted
  ///      — responsibility for the track now lives in the permanent
  ///      library, not the transient cache.
  ///   6. Errors are surfaced to the UI by clearing the transient
  ///      caching flag and logged for the support trail.
  Future<void> downloadTrackIndependent(
    Track track, {
    String? playlistId,
    bool writeToLibraryOnSuccess = false,
  }) async {
    final repo = _audioRepository;
    final cache = _hybridCache;
    if (repo == null || cache == null) {
      AppLogger.log(
        'downloadTrackIndependent: collaborators not attached, '
        'skipping background download for ${track.id}',
        name: 'AudioCacheService',
      );
      return;
    }

    // Spec §1: explicit Hive pre-check. The download pipeline must not
    // start a network fetch for a track the transient cache already
    // holds.
    if (cache.isCached(track.id)) {
      return;
    }

    // When the caller intends to mirror the result into the permanent
    // library, also bail out if SQLite already has the track so we do
    // not re-download an already-permanently-saved file.
    final db = _libraryDatabase;
    if (writeToLibraryOnSuccess && db != null) {
      try {
        if (await db.isTrackDownloaded(track.id)) return;
      } catch (_) {
        // Treat a database read failure as "not present" and fall
        // through to the download path. The SQLite write at the end
        // has its own conflict-algorithm-replace semantics.
      }
    }

    // 1. Instantly set the UI download state to "Caching In Progress".
    cache.markCaching(track.id);

    try {
      // 2. Fetch network stream URL directly from the source locator
      //    without loading it into the player. The repository's
      //    getAudioUrl() consults the local download table and the
      //    LRU cache before falling through to the YouTube extractor,
      //    so a track that was previously downloaded or pre-buffered
      //    never re-enters the network path here.
      final streamUrl = await repo.getAudioUrl(track, quality: 'adaptive');

      // If the audio repository returned a local file path, the
      // track is already permanently downloaded. Just register it in
      // the Hive box and exit — no network call is made.
      if (!streamUrl.startsWith('http')) {
        await cache.markSuccessAfterWrite(
          track.id,
          expectedFilePath: streamUrl,
        );
        await _maybePromoteToLibrary(track, streamUrl,
            playlistId: playlistId, writeToLibrary: writeToLibraryOnSuccess);
        return;
      }

      // 3. Simultaneously download audio bytes and save timed lyrics
      //    files to local disk. The audio write goes through the
      //    shared [cacheStream] path so the `onCacheSuccess` hook fires
      //    on completion (which writes the Hive tracker entry). The
      //    lyrics fetch is best-effort — a failed LrcLib round-trip
      //    must not abort the audio cache write.
      try {
        await Future.wait([
          cacheStream(track.id, streamUrl),
          repo.preloadTrackLyrics(track),
        ]);
      } catch (e) {
        AppLogger.log(
          'Parallel cache fetch partially failed for ${track.id} '
          '(continuing with whatever landed on disk): $e',
          name: 'AudioCacheService',
        );
      }

      // 4. Verify the audio file actually landed. The `onCacheSuccess`
      //    hook has already flipped the state to `success` if it did —
      //    a missing file means the download failed and we need to
      //    clear the transient caching flag so the UI does not stay
      //    stuck on the spinner.
      final landed = await getCachedUri(track.id);
      if (landed == null) {
        cache.markNotCaching(track.id);
        AppLogger.log(
          'Background downloader completed without producing a file '
          'for ${track.id}',
          name: 'AudioCacheService',
        );
        return;
      }

      // 5. Verified success token: write the file path into SQLite
      //    and gently evict the Hive entry so the permanent library
      //    becomes the source of truth for this track.
      await _maybePromoteToLibrary(
        track,
        landed.startsWith('file://') ? Uri.parse(landed).toFilePath() : landed,
        playlistId: playlistId,
        writeToLibrary: writeToLibraryOnSuccess,
      );
    } catch (e) {
      // Spec: surface failure to the UI. The markNotCaching() call
      // collapses the transient caching flag, which flips the icon
      // back to idle (or success, if the file was already in the box
      // from a previous attempt).
      cache.markNotCaching(track.id);
      AppLogger.log(
        'Background downloader failed for track ${track.id}: $e',
        name: 'AudioCacheService',
      );
    }
  }

  /// Album-level background downloader. Concurrently downloads every
  /// track in [album] via [downloadTrackIndependent] without
  /// interrupting whatever the audio player is currently doing. Used
  /// by the favorite hook's "False" branch when the user saves an
  /// entire album whose files are not already in the cache.
  Future<void> downloadEntireAlbum(
    Album album, {
    bool writeToLibraryOnSuccess = false,
  }) async {
    if (album.tracks.isEmpty) return;
    // Spec: map the track collection into an asynchronous array loop
    // (Future.wait()) and process each track through the decoupled
    // background downloader simultaneously.
    await Future.wait(
      album.tracks.map(
        (track) => downloadTrackIndependent(
          track,
          playlistId: album.id,
          writeToLibraryOnSuccess: writeToLibraryOnSuccess,
        ),
      ),
    );
  }

  /// Hive-to-SQLite cache migration hook. Called when a user
  /// favorites a track whose Hive transient cache box already has a
  /// record.
  ///
  /// Spec execution flow:
  ///
  ///   1. Check the Hive `cache_tracker_box` for the target track id
  ///      (`hiveBox.containsKey(trackId)`).
  ///   2. If true, extract the cached metadata timestamp and any
  ///      stored raw timed-lyrics text out of the Hive record.
  ///   3. Write a new row into the SQLite `downloaded_tracks` table
  ///      containing the track metadata and the verified local file
  ///      path. This is the "flag confirming the local audio file is
  ///      fully verified and downloaded on disk".
  ///   4. Gently evict the tracking record from Hive
  ///      (`hiveBox.delete(trackId)`) since responsibility has
  ///      officially shifted to SQLite. The underlying audio and
  ///      lyrics files on disk are not touched.
  ///
  /// The migration is a no-op when:
  /// - the cache service has no library handle,
  /// - the track is already in the SQLite `downloaded_tracks` table,
  /// - the Hive box has no record for the track,
  /// - the on-disk audio file is missing.
  ///
  /// Returns `true` when the migration actually fired, `false` when
  /// it was skipped (so the caller can decide whether to fall through
  /// to the background-downloader "False" branch).
  Future<bool> migrateToLibrary(
    Track track, {
    String playlistId = 'favorites',
  }) async {
    final cache = _hybridCache;
    final db = _libraryDatabase;
    if (cache == null || db == null) return false;

    try {
      // Already in the permanent library? Nothing to do.
      if (await db.isTrackDownloaded(track.id)) return false;

      // Hive transient cache must have a record for this track.
      if (!cache.isCached(track.id)) return false;

      // Locate the on-disk audio file. The cache service uses a
      // deterministic trackId-keyed filename under
      // `<docs>/audio_cache/<trackId>.<ext>` — the same convention the
      // eviction pipeline uses, so the SQLite row and the Hive box
      // resolve to the exact same local file URL.
      final filePath = await _resolveCachedAudioPath(track.id);
      if (filePath == null) return false;
      if (!File(filePath).existsSync()) {
        AppLogger.log(
          'migrateToLibrary: file missing on disk for ${track.id} '
          'at $filePath, skipping migration',
          name: 'AudioCacheService',
        );
        return false;
      }

      // 2. Extract the cached metadata timestamp and any stored raw
      //    timed-lyrics text out of the Hive record. The Hive blob is
      //    the authoritative backup for the LRC payload — the offline
      //    cascade reads it as a fallback if the deterministic file
      //    on disk is missing. We log the extraction for the support
      //    trail; the canonical storage target is the SQLite row.
      final entry = cache.getCacheEntry(track.id);
      final originalCachedAt = entry?.cachedAt;
      final originalLyrics = entry?.timedLyrics;
      if (originalLyrics != null && originalLyrics.isNotEmpty) {
        AppLogger.log(
          'Migrating Hive-tracked lyrics blob for ${track.id} '
          '(${originalLyrics.length} chars, cachedAt=$originalCachedAt)',
          name: 'AudioCacheService',
        );
      }

      // 3. Write the SQLite row with the track metadata + a flag
      //    confirming the local audio file is fully verified (the
      //    existence of the row itself is the flag — see
      //    [PlaylistDatabase.isTrackDownloaded] for the read side).
      await db.markTrackDownloaded(
        track.id,
        playlistId,
        filePath,
        title: track.title,
        thumbnailUrl: track.thumbnailUrl,
        durationSeconds: track.duration.inSeconds,
        author: track.author,
      );

      // 4. Gently evict from Hive. The on-disk files are not
      //    touched, so the SQLite `filePath` still resolves to a
      //    valid local file URL.
      await cache.evictFromTracker(track.id);

      AppLogger.log(
        'Migrated Hive cache entry to SQLite library: ${track.id}',
        name: 'AudioCacheService',
      );
      return true;
    } catch (e) {
      AppLogger.log(
        'migrateToLibrary failed for ${track.id}: $e',
        name: 'AudioCacheService',
      );
      return false;
    }
  }

  /// Album-level migration hook. When a user favorites an album,
  /// every track in the album is run through [migrateToLibrary].
  /// Returns the list of track ids that still need to be downloaded
  /// (i.e. tracks the Hive box did not have) so the caller can hand
  /// them to [downloadEntireAlbum] for the "False" branch.
  Future<List<Track>> migrateAlbumToLibrary(Album album) async {
    if (album.tracks.isEmpty) return const <Track>[];
    final missing = <Track>[];
    for (final track in album.tracks) {
      final migrated = await migrateToLibrary(track, playlistId: album.id);
      if (!migrated) {
        missing.add(track);
      }
    }
    return missing;
  }

  /// Internal helper for the [downloadTrackIndependent] success path.
  /// When [writeToLibrary] is `true`, the verified audio file at
  /// [filePath] is registered in the SQLite `downloaded_tracks` table
  /// and the Hive entry (created earlier by the `onCacheSuccess`
  /// hook) is gently evicted so the permanent library becomes the
  /// source of truth.
  Future<void> _maybePromoteToLibrary(
    Track track,
    String filePath, {
    String? playlistId,
    required bool writeToLibrary,
  }) async {
    if (!writeToLibrary) return;
    final db = _libraryDatabase;
    final cache = _hybridCache;
    if (db == null || cache == null) return;
    if (!File(filePath).existsSync()) return;
    try {
      if (await db.isTrackDownloaded(track.id)) {
        // Already in the permanent library. Just make sure the
        // transient cache does not also claim the track.
        await cache.evictFromTracker(track.id);
        return;
      }
      await db.markTrackDownloaded(
        track.id,
        playlistId ?? 'background',
        filePath,
        title: track.title,
        thumbnailUrl: track.thumbnailUrl,
        durationSeconds: track.duration.inSeconds,
        author: track.author,
      );
      await cache.evictFromTracker(track.id);
      AppLogger.log(
        'Promoted background download to permanent library: ${track.id}',
        name: 'AudioCacheService',
      );
    } catch (e) {
      AppLogger.log(
        '_maybePromoteToLibrary failed for ${track.id}: $e',
        name: 'AudioCacheService',
      );
    }
  }

  /// Resolves the deterministic trackId-keyed audio file path inside
  /// the cache directory. Returns `null` when no file with the
  /// `<trackId>.<ext>` prefix exists. Mirrors the convention used by
  /// [HybridCacheService.deleteLocalAudioFile] so the SQLite
  /// `downloaded_tracks` row and the Hive box resolve to the exact
  /// same local file URL.
  Future<String?> _resolveCachedAudioPath(String trackId) async {
    try {
      final cacheDir = await _getCacheDir();
      if (!await cacheDir.exists()) return null;
      for (final f in cacheDir.listSync().whereType<File>()) {
        final name = f.path.split('/').last;
        if (name.startsWith('$trackId.') && !name.endsWith('.tmp')) {
          return f.path;
        }
      }
    } catch (e) {
      AppLogger.log(
        '_resolveCachedAudioPath failed for $trackId: $e',
        name: 'AudioCacheService',
      );
    }
    return null;
  }

  Future<void> clearCache() async {
    try {
      final cacheDir = await _getCacheDir();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (e) {
      AppLogger.log('Error clearing cache: $e', name: 'AudioCacheService');
    }
  }

  Future<Directory> _getCacheDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${docs.path}/audio_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  Future<void> _updateAccessTime(String trackId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? lruString = prefs.getString(_prefsKey);
    List<String> lru = lruString != null ? List<String>.from(jsonDecode(lruString)) : [];

    lru.remove(trackId);
    lru.add(trackId); // Add to end (most recently used)

    await prefs.setString(_prefsKey, jsonEncode(lru));
  }

  Future<void> _enforceCacheLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final String? lruString = prefs.getString(_prefsKey);
    if (lruString == null) return;

    List<String> lru = List<String>.from(jsonDecode(lruString));

    if (lru.length > _maxCachedItems) {
      final cacheDir = await _getCacheDir();
      int itemsToRemove = lru.length - _maxCachedItems;

      for (int i = 0; i < itemsToRemove; i++) {
        final oldestTrackId = lru[0];
        final files = cacheDir.listSync().whereType<File>().where((file) {
          final name = file.path.split('/').last;
          return name.startsWith('$oldestTrackId.');
        }).toList();

        for (final file in files) {
          if (await file.exists()) {
            await file.delete();
          }
        }
        lru.removeAt(0);
      }

      await prefs.setString(_prefsKey, jsonEncode(lru));
    }
  }
}
