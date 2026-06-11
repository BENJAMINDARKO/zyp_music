import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:zyp_music/core/utils/app_logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../../domain/entities/video.dart';
import '../../domain/repositories/audio_repository.dart';
import '../datasources/remote/youtube_remote_datasource.dart';
import '../datasources/remote/lyrics_remote_datasource.dart';
import '../datasources/local/playlist_database.dart';

import '../../service/audio_handler.dart';
import '../../core/services/audio_cache_service.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/hybrid_cache_service.dart';
import '../../core/services/lyrics_chain_service.dart';

/// Public top-level entry point for the Track-ID prefix
/// stripper. The function lives at file scope (not on a
/// class) so collaborators outside [AudioRepositoryImpl] —
/// e.g. the lyrics chain service — can call it without
/// either a class reference or `static` ceremony. Kept as a
/// plain function (no underscore) on purpose; the previous
/// private `_stripPrefixes` was already top-level so this
/// is purely a rename for re-use.
String stripTrackIdPrefixes(String id) {
  var stripped = id;
  if (stripped.startsWith('unified_')) {
    stripped = stripped.substring('unified_'.length);
  }
  if (stripped.startsWith('youtube_music_')) {
    stripped = stripped.substring('youtube_music_'.length);
  } else if (stripped.startsWith('youtube_')) {
    stripped = stripped.substring('youtube_'.length);
  }
  return stripped;
}

class AudioRepositoryImpl implements AudioRepository, LyricsCacheReader {
  final YoutubeRemoteDataSource remoteDataSource;
  final LyricsRemoteDataSource lyricsDataSource;
  final MusicAudioHandler _handler;
  final PlaylistDatabase _database;
  final HybridCacheService? _hybridCache;
  ConnectivityService? _connectivity;

  /// The audio cache service is constructed in `main.dart` and shared
  /// across the audio + playlist repositories so the non-playing
  /// downloader and the Hive-to-SQLite cache migration hooks can reuse
  /// the same on-disk file layout and Hive tracker wiring.
  final AudioCacheService _cacheService;

  /// Phase 2: multi-tier lyrics fetch chain (YTMusic timed
  /// → YTMusic plain → LrcLib) with the on-disk LRC cache as
  /// tier 1. Late-bound via [setLyricsChainService] so the
  /// repository remains constructible in unit tests that
  /// don't care about lyrics. When null, the legacy
  /// single-tier LrcLib path is preserved.
  LyricsChainService? _lyricsChain;

  void setLyricsChainService(LyricsChainService chain) {
    _lyricsChain = chain;
  }

  bool _isOffline = false;
  bool get isOffline => _isOffline;

  AudioRepositoryImpl({
    required this.remoteDataSource,
    required this.lyricsDataSource,
    required MusicAudioHandler handler,
    required PlaylistDatabase database,
    required AudioCacheService cacheService,
    HybridCacheService? hybridCache,
  })  : _handler = handler,
        _database = database,
        _cacheService = cacheService,
        _hybridCache = hybridCache {
    debugPrint('[RepoInit] handler runtimeType=${_handler.runtimeType} hash=${identityHashCode(_handler)}');
    // Forward every successful on-disk write to the Hive cache tracker so
    // pre-buffered tracks register themselves in the box. This is what makes
    // the download icon flip to the checkmark for tracks that were cached
    // by the lookahead pre-buffer engine (not just user-initiated downloads).
    //
    // Phase 6 (cached-metadata spec): the originating [Track] is forwarded
    // so `markSuccessAfterWrite` can mirror its `title`/`author`/`thumbnailUrl`
    // into the persisted Hive record. The synthesis paths in
    // `QueueManager._buildTrackFromId` and `LocalCrateMiner._mineFromHive`
    // then return a fully-populated `Track` from the Hive tier alone
    // instead of the legacy `'Cached Track'` stub.
    _cacheService.onCacheSuccess = (track, trackId, filePath) async {
      final cache = _hybridCache;
      if (cache == null) return;
      await cache.markSuccessAfterWrite(
        trackId,
        expectedFilePath: filePath,
        sourceTrack: track,
      );
      // C2: fire-and-forget duration backfill. The YouTube
      // extractor often returns no duration for live streams /
      // unlisted videos; the file we just wrote to disk has
      // a real duration that the SQLite row is missing. The
      // probe is bounded (5s) and short-circuits when the row
      // already has a non-null duration, so the common case
      // (YouTube API provided one) is a single no-op SQL
      // read.
      unawaited(
        _cacheService.backfillDurationFromFile(trackId, filePath),
      );
    };
  }

  /// Late-binding entry point used by `main.dart` to break the
  /// chicken-and-egg ctor cycle between [AudioRepositoryImpl] and
  /// [ConnectivityService]. The repository is constructed first (so
  /// the connectivity service can hold a reference for the offline
  /// push path), then the live connectivity service is patched in
  /// here so the lyrics offline cascade can read its current state.
  /// Safe to call exactly once during startup; subsequent calls are
  /// ignored to keep the contract explicit.
  void attachConnectivity(ConnectivityService connectivity) {
    _connectivity = connectivity;
  }

  /// Toggle driven exclusively by [ConnectivityService]. The flag itself
  /// is advisory — the existing local-cache fallback in [getAudioUrl] and
  /// the natural failure of network calls already produce the correct
  /// offline behaviour. The flag is exposed so future consumers (UI
  /// badges, queue logic) can `context.watch` it without re-implementing
  /// the connectivity probe.
  void setOfflineMode(bool isOffline) {
    if (_isOffline == isOffline) return;
    _isOffline = isOffline;
    AppLogger.log(
      'AudioRepository offline mode -> $isOffline',
      name: 'AudioRepository',
    );
  }

  @override
  Future<String> getAudioUrl(
    Track track, {
    String quality = 'adaptive',
  }) async {
    try {
      if (track.id.startsWith('local_')) {
        // Track ID contains the path's hashcode. We actually just need to get it from the database since it's saved there.
        // Wait, for local tracks, we can retrieve the path from SQLite. The original path was saved to SQLite downloaded_tracks.
        final localPath = await _database.getDownloadedFilePath(track.id);
        if (localPath != null && File(localPath).existsSync()) {
          return localPath;
        } else {
          throw Exception('Local file not found for \${track.id}');
        }
      }

      // 1. Local downloaded file takes priority over everything
      final localPath = await _database.getDownloadedFilePath(track.id);
      if (localPath != null && File(localPath).existsSync()) {
        return localPath;
      }

      // 2. LRU cache (skip obviously broken paths)
      final cachedUri = await _cacheService.getCachedUri(track.id);
      if (cachedUri != null) {
        if (cachedUri.endsWith('/.mp3') || cachedUri == '.mp3') {
          AppLogger.log('Invalid cache path detected: $cachedUri. Skipping.', name: 'AudioRepository');
        } else {
          AppLogger.log('Playing from cache: $cachedUri', name: 'AudioRepository');
          return cachedUri;
        }
      }

      // 3. YouTube-only stream retrieval (hardcoded).
      return await _getYouTubeUrl(track, quality);
    } catch (e) {
      throw Exception('YouTube stream failed: $e');
    }
  }

  /// Resolve a YouTube stream URL for [track].
  ///
  /// For native YouTube tracks with an 11-char ID, tries direct URL resolution first.
  /// Falls back to a search query for any other track or if the direct call fails.
  Future<String> _getYouTubeUrl(Track track, String quality) async {
    final rawId = stripTrackIdPrefixes(track.id);
    if ((track.source == TrackSource.youtube || track.source == TrackSource.youtube_music) &&
        rawId.length == 11) {
      try {
        return await remoteDataSource.getAudioUrl(rawId, quality: quality);
      } catch (e) {
        AppLogger.log('Direct YT URL failed, falling back to search: $e', name: 'AudioRepository');
      }
    }

    // Search YouTube by title + artist + album
    final query = '${track.title} ${track.author ?? ''} ${track.album ?? ''} official audio'.trim();
    AppLogger.log('Mapping track via YouTube search: $query', name: 'AudioRepository');
    final results = await remoteDataSource.search(query);
    if (results.isNotEmpty) {
      return await remoteDataSource.getAudioUrl(results.first.id, quality: quality);
    }
    throw Exception('Could not find "${track.title}" on YouTube');
  }

  @override
  Future<void> playTrack(Track track, String audioUrl) async {
    String finalUrl = audioUrl;

    // YouTube Stream URL Expiry Fix: Always re-fetch a fresh stream URL immediately before playback
    if ((track.source == TrackSource.youtube || track.source == TrackSource.youtube_music) &&
        finalUrl.contains('googlevideo.com')) {
      try {
        AppLogger.log('Fetching fresh YouTube stream URL at play time', name: 'AudioRepository');
        final rawId = stripTrackIdPrefixes(track.id);
        final freshUrl = await remoteDataSource.getAudioUrl(rawId, quality: 'adaptive');
        if (freshUrl.isNotEmpty) {
          finalUrl = freshUrl;
        }
      } catch (e) {
        AppLogger.log('Fresh fetch failed: $e, falling back to original URL', name: 'AudioRepository');
      }
    }

    if (finalUrl.startsWith('http')) {
      // Start caching the stream in the background
      _cacheService.cacheStream(track.id, finalUrl, track: track);
    }

    final actualSource = 'youtube';

    final item = MediaItem(
      id: track.id,
      title: track.title,
      artist: track.author ?? '',
      album: track.album,
      artUri: track.thumbnailUrl != null
          ? Uri.tryParse(track.thumbnailUrl!)
          : null,
      duration: track.duration,
      extras: {
        'year': track.year,
        'source': actualSource,
      },
    );

    Future<void> executePlay(String url, MediaItem mediaItem) async {
      final queue = _handler.queue.value;
      if (queue.isNotEmpty && queue.any((e) => e.id == track.id)) {
        _handler.updateMediaItem(mediaItem);
        await _handler.playTrack(url, mediaItem);
      } else {
        final newQueue = List<MediaItem>.from(queue);
        newQueue.add(mediaItem);
        _handler.queue.add(newQueue);
        await _handler.playTrack(url, mediaItem);
      }
    }

    try {
      await executePlay(finalUrl, item);
    } catch (e) {
      if (finalUrl.startsWith('file://') || !finalUrl.startsWith('http')) {
        AppLogger.log('Local cached file failed to play: $e. Deleting cache and retrying from network...', name: 'AudioRepository');
        try {
          final filePath = finalUrl.startsWith('file://') ? Uri.parse(finalUrl).toFilePath() : finalUrl;
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (cleanupError) {
          AppLogger.log('Failed to delete corrupted cached file: $cleanupError', name: 'AudioRepository');
        }

        try {
          final networkUrl = await getAudioUrl(track, quality: 'adaptive');
          if (networkUrl.startsWith('http')) {
            final newItem = MediaItem(
              id: track.id,
              title: track.title,
              artist: track.author ?? '',
              album: track.album,
              artUri: track.thumbnailUrl != null
                  ? Uri.tryParse(track.thumbnailUrl!)
                  : null,
              duration: track.duration,
              extras: {
                'year': track.year,
                'source': 'youtube',
              },
            );
            await executePlay(networkUrl, newItem);
            return;
          }
        } catch (retryError) {
          AppLogger.log('Retry playback failed: $retryError', name: 'AudioRepository');
        }
      }
      rethrow;
    }
  }

  @override
  Future<void> play(String url) async {
    final resolved = await _handler.resolveRedirects(url);
    await _handler.playTrack(resolved, const MediaItem(id: '', title: ''));
  }

  @override
  Future<void> pause() async {
    AppLogger.log('repo.pause() called', name: 'AudioRepository');
    await _handler.pause();
  }

  @override
  Future<void> resume() => _handler.play();

  @override
  Future<void> stop() => _handler.stop();

  @override
  Future<void> seek(Duration position) => _handler.seek(position);

  @override
  Future<void> setPlaybackSpeed(double speed) =>
      _handler.setSpeed(speed);

  @override
  Future<Duration> getPosition() async => _handler.position;

  @override
  Future<Duration> getDuration() async => _handler.duration;

  @override
  Stream<Duration> get positionStream => _handler.positionStream;

  @override
  Stream<Duration> get bufferedPositionStream => _handler.bufferedPositionStream;

  @override
  Stream<Duration> get durationStream => _handler.durationStream;

  @override
  Future<bool> isPlaying() async => _handler.isPlaying;

  @override
  Stream<bool> get playingStream => _handler.playbackState.map((state) => state.playing).distinct();
  @override
  Stream<ProcessingState> get processingStateStream =>
      _handler.processingStateStream;

  @override
  bool get currentTrackCompleted => _handler.currentTrackCompleted;

  @override
  Stream<void> get onSkipNextRequested => _handler.skipNextRequested.stream;

  @override
  Stream<void> get onSkipPreviousRequested => _handler.skipPreviousRequested.stream;

  @override
  Future<String?> getLyrics(Track track) async {
    // When the device is offline the lyrics repository must completely
    // bypass the network client — the offline cascade is the only legal
    // read path. This is the spec §2 invariant: when offline, no LrcLib
    // call is permitted, even if the local file is missing. Falls back
    // to the online path when the connectivity service has not yet
    // been attached (the brief startup window before
    // `attachConnectivity` runs in main.dart).
    if (_connectivity?.isOffline ?? false) {
      return getLyricsOffline(track);
    }

    if (track.id.startsWith('local_')) {
      return getLyricsOffline(track);
    }

    // 1. Try the on-disk LRC first. If it is non-empty and structurally
    // valid (synced LRC timestamp regex matches, or it is a plain-text
    // lyrics file with no timestamp lines), return it without touching
    // the network.
    final lyricsPath = await _lyricsFilePathFor(track.id);
    final cached = await _readCachedLyricsFile(track.id, lyricsPath);
    if (cached != null) return cached;

    // 2. Network fetch with the write-time validation pass. The spec
    // requires a strict assertion (File.exists() on the LRC, blob
    // equality against the Hive `timedLyrics`) before the cache
    // transaction is declared complete. If the assertion fails, retry
    // the fetch once; if it still fails, flag the lyrics state as
    // missing so future consumers can self-heal.
    return _fetchAndCacheLyricsWithValidation(track, lyricsPath);
  }

  /// Offline-only lyrics read cascade. Used when [ConnectivityService]
  /// reports the device is offline (or when the caller explicitly needs
  /// the local-only result). Strict order:
  ///
  ///   1. `<docs>/<trackId>-lyrics.lrc` — the deterministic trackId-keyed
  ///      LRC file. Validated for non-empty content + LRC timestamp
  ///      structure. Returns immediately on a hit.
  ///   2. `HybridCacheService.getLyrics(trackId)` — the in-box
  ///      `timedLyrics` blob. This is the belt-and-braces fallback for
  ///      the case where the file is missing (manual delete, partial
  ///      cleanup) but the Hive record survived. The blob was committed
  ///      to memory-mapped storage as part of the same write transaction
  ///      as the file, so it is trustworthy in isolation.
  ///   3. `null` — neither source has a usable payload. The presentation
  ///      layer renders "Lyrics not available".
  ///
  /// This method never calls the network, never modifies either storage
  /// tier, and never throws on a miss.
  @override
  Future<String?> getLyricsOffline(Track track) async {
    final lyricsPath = await _lyricsFilePathFor(track.id);

    // Step 1: deterministic trackId-keyed LRC file.
    final cached = await _readCachedLyricsFile(track.id, lyricsPath);
    if (cached != null) {
      AppLogger.log(
        'Offline lyrics served from LRC file for ${track.id}',
        name: 'AudioRepository',
      );
      return cached;
    }

    // Step 2: Hive tracker blob fallback.
    final cache = _hybridCache;
    if (cache != null) {
      final blob = cache.getLyrics(track.id);
      if (blob != null && blob.isNotEmpty) {
        AppLogger.log(
          'Offline lyrics served from Hive blob for ${track.id} '
          '(file missing, blob recovered)',
          name: 'AudioRepository',
        );
        return blob;
      }
    }

    // Step 3: nothing on disk and nothing in the box.
    return null;
  }

  /// Fire-and-forget lyrics fetch used by the prebuffer and favorite
  /// entry points. Runs the same fetch+validation+retry flow as
  /// [getLyrics] but is safe to invoke without awaiting from background
  /// cache coordinators. Errors are swallowed (logged) — a failed
  /// background lyrics fetch must never abort the audio cache write.
  ///
  /// Skips the network fetch when the Hive tracker already reports the
  /// lyrics as verified (the validator passed on a previous write).
  /// The validator still runs on the first call after any eviction
  /// pass that flips `lyricsVerified` back to `false`, so the self-heal
  /// path stays intact.
  @override
  Future<void> preloadTrackLyrics(Track track) async {
    try {
      final cache = _hybridCache;
      if (cache != null && cache.isLyricsVerified(track.id)) {
        return;
      }
      await getLyrics(track);
    } catch (e) {
      AppLogger.log(
        'preloadTrackLyrics failed for ${track.id}: $e',
        name: 'AudioRepository',
      );
    }
  }

  /// LyricsCacheReader entry point used by [LyricsChainService]
  /// as tier 1 (the "is the LRC already on disk?" check). The
  /// chain can be called from any code path that has a
  /// [Track] in hand; the repository is the only collaborator
  /// that knows the on-disk file layout, so the indirection
  /// keeps the chain free of `dart:io` and path manipulation.
  @override
  Future<String?> read(String trackId) async {
    final path = await _lyricsFilePathFor(trackId);
    return _readCachedLyricsFile(trackId, path);
  }

  /// Reads the deterministic trackId-keyed LRC file at [lyricsPath] and
  /// returns its content only when the content is non-empty AND
  /// structurally valid (synced LRC timestamps or plain text). Returns
  /// `null` for a missing file, an empty file, or a corrupt payload —
  /// in all three cases the caller is expected to fall through to a
  /// fresh network fetch.
  Future<String?> _readCachedLyricsFile(
    String trackId,
    String lyricsPath,
  ) async {
    try {
      final file = File(lyricsPath);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      if (content.isEmpty) return null;
      final hasValidLrc = RegExp(r'\[\d{2}:\d{2}\.\d{2}').hasMatch(content);
      final isPlainLyrics = !content.contains('[');
      if (hasValidLrc || isPlainLyrics) return content;
      AppLogger.log(
        'Cached lyrics file for $trackId appears corrupt, '
        'falling through to network',
        name: 'AudioRepository',
      );
      return null;
    } catch (e) {
      AppLogger.log(
        'Error reading local lyrics file for $trackId: $e',
        name: 'AudioRepository',
      );
      return null;
    }
  }

  /// Fetches lyrics from the network, writes them to disk and to the
  /// Hive tracker, and then runs the structural validation pass
  /// [HybridCacheService.validateLyricsWrite] before declaring the
  /// transaction complete. If validation fails, retries the network
  /// fetch once; if the second attempt also fails to validate, the
  /// track's lyrics state is flagged as missing via
  /// [HybridCacheService.markLyricsMissing] and the method returns the
  /// best-effort payload (which may still be the second-attempt body).
  Future<String?> _fetchAndCacheLyricsWithValidation(
    Track track,
    String lyricsPath,
  ) async {
    const maxAttempts = 2;
    String? lastLyrics;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final lyrics = await _fetchLyricsFromNetwork(track);
      if (lyrics == null || lyrics.isEmpty) {
        AppLogger.log(
          'Lyrics network fetch returned empty for ${track.id} '
          '(attempt $attempt/$maxAttempts)',
          name: 'AudioRepository',
        );
        continue;
      }
      lastLyrics = lyrics;
      try {
        final file = File(lyricsPath);
        await file.writeAsString(lyrics);
        final cache = _hybridCache;
        if (cache != null) {
          await cache.setLyrics(track.id, lyrics, filePath: lyricsPath);
        }
      } catch (e) {
        AppLogger.log(
          'Error persisting fetched lyrics for ${track.id}: $e',
          name: 'AudioRepository',
        );
        continue;
      }
      // Write-time validation pass: assert the file exists on disk AND
      // the in-box blob matches the payload we just wrote. If both
      // conditions hold the cache transaction is complete.
      final cache = _hybridCache;
      final isValid = cache == null
          ? File(lyricsPath).existsSync()
          : HybridCacheService.validateLyricsWrite(
              trackId: track.id,
              lyrics: lyrics,
              lyricsFilePath: lyricsPath,
              cache: cache,
            );
      if (isValid) {
        AppLogger.log(
          'Lyrics write validation passed for ${track.id} on attempt $attempt',
          name: 'AudioRepository',
        );
        return lyrics;
      }
      AppLogger.log(
        'Lyrics write validation FAILED for ${track.id} on attempt $attempt; '
        '${attempt < maxAttempts ? "retrying fetch" : "flagging as missing"}',
        name: 'AudioRepository',
      );
    }
    if (lastLyrics != null) {
      final cache = _hybridCache;
      if (cache != null) {
        await cache.markLyricsMissing(track.id);
      }
    }
    return lastLyrics;
  }

  Future<String?> _fetchLyricsFromNetwork(Track track) async {
    final chain = _lyricsChain;
    if (chain != null) {
      return chain.fetchLyrics(track);
    }
    return await lyricsDataSource.getSyncedLyrics(track.title, track.author ?? '');
  }

  @override
  Future<String?> refreshLyrics(Track track) async {
    final lyricsPath = await _lyricsFilePathFor(track.id);
    return _fetchAndCacheLyricsWithValidation(track, lyricsPath);
  }

  /// Resolves the deterministic trackId-keyed lyrics file path inside the
  /// application documents directory. Kept private to the repository so the
  /// Hive eviction pipeline can rely on the same naming convention.
  Future<String> _lyricsFilePathFor(String trackId) async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$trackId-lyrics.lrc';
  }

  @override
  Future<List<Track>> getUpNexts(Track track) async {
    try {
      final upNexts = await remoteDataSource.getUpNexts(track.id);
      final tracks = <Track>[];
      for (final e in upNexts) {
        if (e.videoId == null || e.videoId!.isEmpty) continue;
        // Phase 5: capture the genre signal at fetch time. The
        // YouTube Music `UpNextsDetails` payload does NOT expose
        // a `genre` field, so the strongest signal on the wire
        // is `album.name`. We record whatever we have (album
        // name or "Unknown") so the AI DJ routing service can
        // score candidates with zero extra round trips; the
        // crate miner still falls back to
        // `dj_listening_history.primary_genre` when this
        // proxy is weak or null.
        // Inherit the seed track's genre to ensure AutoDJ routing works correctly.
        final genre = track.genre ?? _captureGenreSignal(e);
        final t = Track(
          id: e.videoId!,
          title: e.title ?? 'Unknown',
          author: e.artists?.name ?? 'Unknown',
          thumbnailUrl: e.thumbnails?.last.url,
          // C1: preserve null. The YouTube API returns no
          // `duration` for live streams / unlisted videos;
          // coercing to `0` would render as `0:00` in the UI.
          // [formatDuration] handles the null case with the
          // em-dash placeholder.
          duration: e.duration == null
              ? null
              : Duration(seconds: e.duration!),
          albumId: e.album?.albumId,
          source: TrackSource.youtube,
          genre: genre,
        );
        tracks.add(t);
        // Synchronize the captured genre into both stores so
        // the routing service can read it back with zero
        // latency. Fire-and-forget: a write failure is
        // non-fatal (the routing service falls back to the
        // history ledger on miss).
        unawaited(_persistGenreCapture(t.id, genre));
      }
      if (tracks.isNotEmpty) return tracks;
    } catch (e) {
      AppLogger.log('Failed to fetch Up Nexts: $e', name: 'AudioRepository');
    }
    
    // Fallback logic
    try {
      final results = await remoteDataSource.searchTracks("${track.title} ${track.author ?? ''}");
      return results.where((t) => t.id != track.id).map((t) => t.toEntity()).toList();
    } catch (e) {
      AppLogger.log('Fallback search for Up Nexts failed: $e', name: 'AudioRepository');
      return [];
    }
  }

  /// Phase 5: extracts the strongest available genre signal
  /// from a `UpNextsDetails` payload. The YouTube Music API
  /// does not expose a structured `genre` field; the only
  /// metadata available on the wire is `album.name`, which
  /// is a weak proxy (often a release title like "Greatest
  /// Hits"). We record whatever is there so the AI DJ routing
  /// layer can short-circuit when present; the crate miner
  /// still consults the listening-history ledger as a
  /// fallback for tracks where the proxy is empty.
  String? _captureGenreSignal(dynamic upNext) {
    try {
      final album = upNext.album;
      if (album == null) return null;
      final name = album.name as String?;
      if (name == null || name.trim().isEmpty) return null;
      return name.trim();
    } catch (_) {
      return null;
    }
  }

  /// Phase 5: persists a captured genre into both the SQLite
  /// `track_metadata.genre` column AND the Hive tracker box
  /// (when the track happens to be cached). Fire-and-forget;
  /// never throws.
  Future<void> _persistGenreCapture(String trackId, String? genre) async {
    try {
      await _database.setTrackGenre(trackId, genre);
    } catch (e) {
      AppLogger.log(
        'Genre capture (SQLite) failed for $trackId: $e',
        name: 'AudioRepository',
      );
    }
    final cache = _hybridCache;
    if (cache != null) {
      try {
        await cache.setGenre(trackId, genre);
      } catch (e) {
        AppLogger.log(
          'Genre capture (Hive) failed for $trackId: $e',
          name: 'AudioRepository',
        );
      }
    }
  }

  @override
  Future<void> preloadTrack(Track track) async {
    try {
      final audioUrl = await getAudioUrl(track);
      if (audioUrl.startsWith('http')) {
        await _cacheService.cacheStream(track.id, audioUrl, track: track);
        AppLogger.log('Successfully preloaded track: ${track.id}', name: 'AudioRepository');
      }
      // Spec §1: when a track is cached via the background look-ahead
      // prebuffer the caching service must also run the structural
      // lyrics validation. Fire-and-forget — a failed lyrics fetch
      // never aborts the audio cache write.
      unawaited(preloadTrackLyrics(track));
    } catch (e) {
      AppLogger.log('Failed to preload next track: $e', name: 'AudioRepository');
    }
  }

  @override
  Future<AudioSource> buildAudioSource(Track track) async {
    final url = await getAudioUrl(track);
    var finalUrl = url;

    // YouTube Stream URL Expiry Fix: Always re-fetch a fresh stream URL immediately before playback
    if ((track.source == TrackSource.youtube || track.source == TrackSource.youtube_music) &&
        finalUrl.contains('googlevideo.com')) {
      try {
        AppLogger.log('Fetching fresh YouTube stream URL at build time', name: 'AudioRepository');
        final rawId = stripTrackIdPrefixes(track.id);
        final freshUrl = await remoteDataSource.getAudioUrl(rawId, quality: 'adaptive');
        if (freshUrl.isNotEmpty) {
          finalUrl = freshUrl;
        }
      } catch (e) {
        AppLogger.log('Fresh fetch failed: $e, falling back to original URL', name: 'AudioRepository');
      }
    }

    if (finalUrl.startsWith('http')) {
      // Start caching the stream in the background
      _cacheService.cacheStream(track.id, finalUrl, track: track);
    }

    final headers = await _handler.getHeaders();
    final uri = finalUrl.startsWith('file://') || !finalUrl.startsWith('http')
        ? (finalUrl.startsWith('file://') ? Uri.parse(finalUrl) : Uri.file(finalUrl))
        : Uri.parse(finalUrl);

    final item = MediaItem(
      id: track.id,
      title: track.title,
      artist: track.author ?? '',
      album: track.album,
      artUri: track.thumbnailUrl != null
          ? Uri.tryParse(track.thumbnailUrl!)
          : null,
      duration: track.duration,
      extras: {
        'year': track.year,
        'source': 'youtube',
      },
    );

    final finalHeaders = uri.host.contains('googlevideo.com') ? null : headers;
    return AudioSource.uri(
      uri,
      headers: finalHeaders,
      tag: item,
    );
  }
}
