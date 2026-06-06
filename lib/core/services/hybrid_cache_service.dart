import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/datasources/local/playlist_database.dart';
import '../../data/models/cache_tracker_model.dart';
import '../../core/utils/app_logger.dart';

/// Public cache state exposed to the UI layer.
enum CachedState { idle, caching, success, removed }

/// Lightweight event pushed whenever a track transitions between cache states.
class CachedStateEvent {
  final String trackId;
  final CachedState state;
  const CachedStateEvent(this.trackId, this.state);
}

/// Hybrid two-tier cache backed by a single memory-mapped Hive box
/// (transient cache tier) cross-referenced against the SQLite-backed
/// [PlaylistDatabase] (permanent library tier).
///
/// Tier A — **Favorites** (persistent, protected). Entries flagged with
/// `isFavorite = true` are completely immune to automated eviction and to
/// non-favorite LRU bounds.
///
/// Tier B — **Casual LRU** (bounded at [casualLimit], 200 by default).
/// When the box would exceed the cap, the [evictionBatchSize] oldest
/// non-favorite entries are removed in a single `box.deleteAll(keys)` call.
/// Their audio files and any persisted lyrics are physically removed from
/// local storage in the same step.
///
/// The eviction pipeline always cross-references the SQLite library before
/// purging any file from disk — see [evaluateAndEvictCasualCache]. This
/// prevents the system from accidentally deleting a cached file that the user
/// has marked as a favorite in the permanent library, even when the Hive
/// favourite flag has drifted out of sync.
///
/// The service also exposes a transient in-memory `caching` set so the UI
/// can distinguish "actively writing bytes" from "fully cached" without
/// hitting disk. Persisted `timedLyrics` ride along with the box record and
/// are dropped together on eviction.
class HybridCacheService extends ChangeNotifier {
  static const String _logTag = 'HybridCacheService';
  static const String boxName = 'cache_tracker_box';

  /// Hard cap on the Hive transient tracker box (per the hybrid architecture
  /// spec). Exposed publicly so tests and external coordinators can use the
  /// same number the eviction pipeline uses.
  static const int casualLimit = 200;

  /// Number of oldest entries inspected per eviction pass. Exposed publicly
  /// for the same reason as [casualLimit].
  static const int evictionBatchSize = 10;

  static const String _cacheSubdir = 'audio_cache';

  /// Optional handle to the SQLite-backed permanent library. When supplied,
  /// the eviction pipeline uses it as the source of truth for the
  /// "saved in library" cross-check. When omitted, eviction falls back to
  /// the in-box `isFavorite` flag and never touches the SQLite tier.
  final PlaylistDatabase? libraryDatabase;

  Box<CacheTrackerModel>? _box;
  final Set<String> _activeCaching = <String>{};
  /// Sync in-memory mirror of the SQLite `downloaded_tracks` table.
  /// Populated eagerly on [init] and updated whenever the cache
  /// migration hook promotes a track from the Hive transient cache to
  /// the permanent library. Backs the dual-source checkmark check
  /// called out in spec §5: the download icon's success state must
  /// fire when **either** `hiveBox.containsKey(trackId)` is true
  /// **or** `favoritesDao.isTrackDownloaded(trackId)` is true.
  final Set<String> _sqliteDownloadedIds = <String>{};
  final StreamController<CachedStateEvent> _stateEvents =
      StreamController<CachedStateEvent>.broadcast();

  Stream<CachedStateEvent> get stateStream => _stateEvents.stream;

  bool get isInitialized => _box?.isOpen ?? false;

  HybridCacheService({this.libraryDatabase});

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Opens the Hive box. Idempotent: subsequent calls are no-ops.
  /// **Does NOT clear the box** — persisted entries survive app restarts and
  /// phone reboots. This is the explicit design rule for this tier.
  ///
  /// After opening, fires a best-effort filesystem reconcile in the
  /// background: any audio file sitting in `<docs>/audio_cache/` whose
  /// trackId is not yet in the box gets a fresh record added. Existing
  /// records and files are never modified or removed.
  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    _box = await Hive.openBox<CacheTrackerModel>(boxName);
    AppLogger.log(
      'Hive box "$boxName" opened with ${_box!.length} persisted entries',
      name: _logTag,
    );
    // Eagerly populate the sync SQLite mirror so the spec §5 dual-source
    // checkmark check works from the very first frame after launch.
    await refreshSqliteDownloadedCache();
    // Defer so callers see a usable box immediately. Failures are logged
    // but never thrown — the next reconcile on a future launch can recover.
    Future<void>(() => _reconcileWithFilesystem());
  }

  /// Scans the on-disk audio cache directory and registers any orphan
  /// trackId (file present, no Hive entry) as a casual-tier cache record.
  /// Purely additive — never modifies or deletes existing entries, never
  /// touches the audio files themselves. This brings the index into sync
  /// with reality for tracks that were pre-buffered (or downloaded) before
  /// the Hive tier was wired up.
  Future<void> _reconcileWithFilesystem() async {
    final box = _box;
    if (box == null) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${docs.path}/$_cacheSubdir');
      if (!cacheDir.existsSync()) return;

      final orphans = <String, CacheTrackerModel>{};
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final entry in cacheDir.listSync().whereType<File>()) {
        final name = entry.path.split('/').last;
        if (name.endsWith('.tmp') || name.endsWith('.part')) continue;
        if (entry.lengthSync() == 0) continue;
        final dot = name.lastIndexOf('.');
        if (dot <= 0) continue;
        final trackId = name.substring(0, dot);
        if (trackId.isEmpty) continue;
        if (box.containsKey(trackId)) continue;
        orphans[trackId] = CacheTrackerModel(trackId: trackId, cachedAt: now);
      }
      if (orphans.isEmpty) return;
      await box.putAll(orphans);
      AppLogger.log(
        'Filesystem reconcile: indexed ${orphans.length} orphan cache files',
        name: _logTag,
      );
    } catch (e) {
      AppLogger.log('Filesystem reconcile failed: $e', name: _logTag);
    }
  }

  // ---------------------------------------------------------------------------
  // State queries (synchronous, O(1) for box reads)
  // ---------------------------------------------------------------------------

  /// True iff the track has a persisted cache record.
  bool isCached(String trackId) {
    return _box?.containsKey(trackId) ?? false;
  }

  /// Snapshot of every trackId currently registered in the Hive tracker box.
  ///
  /// Used by the Auto DJ offline shuffle pool to draw from the 200 casual
  /// cached tracks. The returned list is a fresh, mutable copy — callers are
  /// free to shuffle it. Returns an empty list when the box has not been
  /// opened yet.
  List<String> getCachedTrackIds() {
    final box = _box;
    if (box == null) return const <String>[];
    return box.keys.map((k) => k.toString()).toList(growable: false);
  }

  /// True iff the track is currently being written to disk.
  bool isActivelyCaching(String trackId) => _activeCaching.contains(trackId);

  /// Resolves the public state used by the download icon state machine.
  ///
  /// Per spec §5, the checkmark state is derived from BOTH the Hive
  /// transient cache box AND the SQLite permanent library. A track
  /// that was migrated from Hive to SQLite (or downloaded directly
  /// into the library) still renders the success checkmark even
  /// though the Hive entry was gently evicted.
  CachedState getCachedState(String trackId) {
    if (isActivelyCaching(trackId)) return CachedState.caching;
    if (isCached(trackId)) return CachedState.success;
    if (_sqliteDownloadedIds.contains(trackId)) return CachedState.success;
    return CachedState.idle;
  }

  /// Synchronous mirror of `libraryDatabase.isTrackDownloaded(trackId)`.
  /// Backed by [_sqliteDownloadedIds] so the UI build can check the
  /// SQLite library tier without awaiting a database round-trip. The
  /// mirror is populated by [refreshSqliteDownloadedCache] and updated
  /// by the cache migration hook.
  bool isDownloadedInSqlite(String trackId) {
    return _sqliteDownloadedIds.contains(trackId);
  }

  /// Eagerly refreshes the [_sqliteDownloadedIds] mirror from the
  /// library database. Safe to call multiple times — the previous
  /// snapshot is replaced atomically.
  Future<void> refreshSqliteDownloadedCache() async {
    final db = libraryDatabase;
    if (db == null) {
      _sqliteDownloadedIds.clear();
      return;
    }
    try {
      final ids = await db.getAllDownloadedTrackIds();
      _sqliteDownloadedIds
        ..clear()
        ..addAll(ids);
    } catch (e) {
      AppLogger.log(
        'refreshSqliteDownloadedCache failed: $e',
        name: _logTag,
      );
    }
  }

  /// Returns the persisted LRC (or other timed-lyric blob) for a track, or
  /// `null` if no lyrics are stored. Synchronous — backed by memory-mapped
  /// Hive, so it is safe to call from a widget build.
  String? getLyrics(String trackId) {
    return _box?.get(trackId)?.timedLyrics;
  }

  /// True iff the most recent write-time validation pass confirmed that
  /// the on-disk LRC file and the in-box `timedLyrics` blob both hold the
  /// same non-empty payload for [trackId]. Defaults to `true` for legacy
  /// records that predate the [CacheTrackerModel.kFieldLyricsVerified]
  /// schema bump, so a one-shot migration is not required.
  bool isLyricsVerified(String trackId) {
    return _box?.get(trackId)?.lyricsVerified ?? true;
  }

  /// Marks a track's lyrics payload as **untrusted**. Called by the
  /// lyrics-write validation flow when the immediate assertion pass
  /// (`File.exists()` for the LRC, `box.get(trackId).timedLyrics` not null)
  /// fails. The next read on the offline cascade will still return whatever
  /// it can find in the blob, but future eviction passes can use this flag
  /// to drop the lyrics on a casual-tier purge.
  Future<void> markLyricsMissing(String trackId) async {
    final box = _box;
    if (box == null) return;
    final existing = box.get(trackId);
    if (existing == null) {
      await box.put(
        trackId,
        CacheTrackerModel(
          trackId: trackId,
          cachedAt: DateTime.now().millisecondsSinceEpoch,
          lyricsVerified: false,
        ),
      );
      return;
    }
    if (existing.lyricsVerified) {
      await box.put(
        trackId,
        existing.copyWith(lyricsVerified: false),
      );
    }
  }

  /// Structural validation for a lyrics write. Returns `true` only when
  /// all three conditions hold:
  ///
  /// 1. [lyrics] is not null and not empty.
  /// 2. The on-disk LRC file at [lyricsFilePath] exists and is non-empty.
  /// 3. The in-box `timedLyrics` blob equals [lyrics] (i.e. the mirror
  ///    write to Hive committed successfully).
  ///
  /// This is the public assertion entry point the offline-lyrics spec
  /// calls out — every cache transaction (download, prebuffer, favorite)
  /// must run this check before declaring the lyrics write successful. On
  /// failure, callers are expected to either retry the fetch or invoke
  /// [markLyricsMissing] so the cache state stays honest.
  static bool validateLyricsWrite({
    required String trackId,
    required String? lyrics,
    required String lyricsFilePath,
    required HybridCacheService cache,
  }) {
    if (lyrics == null || lyrics.isEmpty) return false;
    try {
      final file = File(lyricsFilePath);
      if (!file.existsSync()) return false;
      if (file.lengthSync() == 0) return false;
    } catch (_) {
      return false;
    }
    final blob = cache.getLyrics(trackId);
    if (blob == null || blob.isEmpty) return false;
    return blob == lyrics;
  }

  bool isFavorite(String trackId) {
    return _box?.get(trackId)?.isFavorite ?? false;
  }

  /// Returns the persisted cache record for [trackId], or `null` if the
  /// box has no entry. Used by the Hive-to-SQLite cache migration hook
  /// to extract the original `cachedAt` timestamp and any stored
  /// `timedLyrics` blob before the entry is gently evicted.
  CacheTrackerModel? getCacheEntry(String trackId) {
    return _box?.get(trackId);
  }

  /// Removes the tracking record for [trackId] from the Hive box
  /// without touching any on-disk files. This is the "gently evict"
  /// primitive used by the cache migration hook once the SQLite
  /// library has absorbed the metadata. After the call returns the
  /// box no longer reports [trackId] as cached, but the audio and
  /// lyrics files on disk remain in place so the SQLite row still
  /// resolves to a valid local file URL.
  ///
  /// The migration hook calls this immediately after writing the
  /// SQLite row, so we also keep the [_sqliteDownloadedIds] mirror
  /// in sync — the spec §5 dual-source checkmark check depends on it.
  Future<void> evictFromTracker(String trackId) async {
    final box = _box;
    if (box == null) return;
    if (!box.containsKey(trackId)) return;
    await box.delete(trackId);
    _sqliteDownloadedIds.add(trackId);
    final exists = isActivelyCaching(trackId);
    if (!exists) {
      _emit(trackId, CachedState.idle);
    }
  }

  // ---------------------------------------------------------------------------
  // State mutations
  // ---------------------------------------------------------------------------

  /// Marks a track as actively writing to disk. Idempotent. The state
  /// persists until [markSuccessAfterWrite] or [markNotCaching] is called.
  void markCaching(String trackId) {
    if (_activeCaching.add(trackId)) {
      _emit(trackId, CachedState.caching);
    }
  }

  /// Clears the transient "actively writing" flag without recording success.
  /// Used when a download aborts before completing.
  void markNotCaching(String trackId) {
    if (_activeCaching.remove(trackId)) {
      final newState = isCached(trackId) ? CachedState.success : CachedState.idle;
      _emit(trackId, newState);
    }
  }

  /// Persists a successful cache write. If [expectedFilePath] is provided,
  /// the entry is only recorded when the file actually exists on disk — this
  /// is the explicit "as soon as the file write handle closes successfully
  /// and `File.exists()` evaluates to true" rule from the spec.
  ///
  /// Always triggers the LRU eviction pass after a successful write.
  Future<void> markSuccessAfterWrite(
    String trackId, {
    String? expectedFilePath,
  }) async {
    final box = _box;
    if (box == null) return;

    if (expectedFilePath != null) {
      if (!File(expectedFilePath).existsSync()) {
        AppLogger.log(
          'markSuccessAfterWrite: file missing for $trackId at $expectedFilePath; not recording',
          name: _logTag,
        );
        markNotCaching(trackId);
        return;
      }
    }

    final existing = box.get(trackId);
    final next = CacheTrackerModel(
      trackId: trackId,
      cachedAt: DateTime.now().millisecondsSinceEpoch,
      isFavorite: existing?.isFavorite ?? false,
      timedLyrics: existing?.timedLyrics,
      lyricsFilePath: existing?.lyricsFilePath,
      lyricsVerified: existing?.lyricsVerified ?? true,
    );
    await box.put(trackId, next);
    _activeCaching.remove(trackId);

    await evaluateAndEvictCasualCache();
    _emit(trackId, CachedState.success);
  }

  /// Records a track access by bumping its `cachedAt` timestamp. Used for
  /// passive LRU tracking when a track is played (not just downloaded).
  Future<void> touch(String trackId) async {
    final box = _box;
    if (box == null) return;
    final existing = box.get(trackId);
    if (existing == null) return;
    await box.put(trackId, existing.copyWith(
      cachedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    await evaluateAndEvictCasualCache();
  }

  /// Phase 5: records the per-track `genre` string in the
  /// Hive tracker box. Called by
  /// `AudioRepository.getUpNexts` so the AI DJ routing layer
  /// can score Hive-only candidates without a SQLite round
  /// trip per lookup. Idempotent: if the track is not yet in
  /// Hive, the call is a no-op (the Hive tier is built
  /// opportunistically as files are cached, not by the fetch
  /// path).
  Future<void> setGenre(String trackId, String? genre) async {
    final box = _box;
    if (box == null) return;
    final existing = box.get(trackId);
    if (existing == null) return;
    await box.put(trackId, existing.copyWith(
      genre: genre,
      clearGenre: genre == null,
    ));
  }

  /// Persists timed-lyrics text against a track. If the track is not yet
  /// cached, a stub record is created so the lyrics survive across sessions.
  /// If [filePath] is provided, the on-disk lyrics file path is also recorded
  /// so the cross-database eviction pipeline can purge the file alongside the
  /// Hive entry. The persisted record is stamped [CacheTrackerModel.lyricsVerified]
  /// = `true` so the offline read cascade trusts the payload until the
  /// write-time validator runs and explicitly flips the flag.
  Future<void> setLyrics(String trackId, String lrc, {String? filePath}) async {
    final box = _box;
    if (box == null) return;
    final existing = box.get(trackId);
    final next = (existing ??
            CacheTrackerModel(
              trackId: trackId,
              cachedAt: DateTime.now().millisecondsSinceEpoch,
            ))
        .copyWith(
          timedLyrics: lrc,
          lyricsFilePath: filePath,
          lyricsVerified: true,
        );
    await box.put(trackId, next);
  }

  /// Marks a track as a favorite. Favorite entries are protected from
  /// LRU eviction and have no cap.
  Future<void> markFavorite(String trackId) async {
    final box = _box;
    if (box == null) return;
    final existing = box.get(trackId);
    final next = (existing ??
            CacheTrackerModel(
              trackId: trackId,
              cachedAt: DateTime.now().millisecondsSinceEpoch,
            ))
        .copyWith(isFavorite: true);
    await box.put(trackId, next);
  }

  Future<void> unmarkFavorite(String trackId) async {
    final box = _box;
    if (box == null) return;
    final existing = box.get(trackId);
    if (existing == null) return;
    await box.put(trackId, existing.copyWith(isFavorite: false));
    await evaluateAndEvictCasualCache();
  }

  // ---------------------------------------------------------------------------
  // Hybrid eviction routine
  // ---------------------------------------------------------------------------

  /// Bounded LRU enforcement with a cross-database guard.
  ///
  /// This is the core execution flow for the cache coordinator. It is the
  /// single entry point that bridges the Hive transient cache tier with the
  /// SQLite permanent library tier.
  ///
  /// Operational logic, lifted from the hybrid architecture spec:
  ///
  ///   1. Check whether the Hive transient tracker box exceeds [casualLimit]
  ///      (200). If not, no eviction runs.
  ///   2. Sort the entire in-memory Hive list by `cachedAt` ascending and take
  ///      the [evictionBatchSize] (10) oldest entries as candidates.
  ///   3. For each candidate, **ask the SQLite library** whether the track is
  ///      either favorited or bound to a downloaded album. This cross-check
  ///      is mandatory — the in-box `isFavorite` flag is a cached projection
  ///      and is not the source of truth.
  ///   4. If the track is **not** in the SQLite library: delete the local
  ///      audio file, the local lyrics file, and the Hive box entry.
  ///   5. If the track **is** in the SQLite library: leave the file in
  ///      place and update the Hive entry to flip `isFavorite = true` so
  ///      subsequent LRU passes skip it.
  ///
  /// When [libraryDatabase] is null, the SQLite cross-check is skipped and
  /// the in-box `isFavorite` flag is used as a best-effort fallback. This
  /// preserves the previous behaviour for callers that wire the service
  /// without a database handle.
  Future<void> evaluateAndEvictCasualCache() async {
    final box = _box;
    if (box == null) return;

    if (box.length <= casualLimit) return;

    final sortedCache = box.values.toList()
      ..sort((a, b) => a.cachedAt.compareTo(b.cachedAt));
    final evictionCandidates = sortedCache.take(evictionBatchSize).toList();

    final db = libraryDatabase;
    var removed = 0;
    var guarded = 0;

    for (final track in evictionCandidates) {
      final isSavedInLibrary = await _isSavedInLibrary(db, track.trackId);
      if (!isSavedInLibrary) {
        await deleteLocalAudioFile(track.trackId);
        await deleteLocalLyricsFile(track.trackId);
        await box.delete(track.trackId);
        removed++;
      } else {
        // Guard action: the track is in the permanent library. Update the
        // Hive flag so the next eviction pass treats it as protected.
        if (!track.isFavorite) {
          await box.put(
            track.trackId,
            track.copyWith(isFavorite: true),
          );
        }
        // Keep the sync SQLite mirror in sync with the library.
        _sqliteDownloadedIds.add(track.trackId);
        guarded++;
      }
    }

    AppLogger.log(
      'Hybrid eviction pass: removed=$removed guarded=$guarded '
      '(box size now ${box.length}, cap $casualLimit)',
      name: _logTag,
    );
  }

  /// Asks the SQLite library whether [trackId] is part of the user's
  /// permanent library — i.e. either favorited or bound to a downloaded
  /// album. Falls back to the in-box Hive flag when no database handle is
  /// available.
  Future<bool> _isSavedInLibrary(PlaylistDatabase? db, String trackId) async {
    if (db == null) {
      return _box?.get(trackId)?.isFavorite ?? false;
    }
    try {
      final isFavorite = await db.isTrackFavorite(trackId);
      if (isFavorite) return true;
      return await db.isTrackDownloaded(trackId);
    } catch (e) {
      AppLogger.log(
        'SQLite cross-check failed for $trackId: $e; falling back to Hive flag',
        name: _logTag,
      );
      return _box?.get(trackId)?.isFavorite ?? false;
    }
  }

  /// Removes the local audio file(s) for [trackId] from the audio cache
  /// directory. The search is best-effort: any file whose name starts with
  /// `<trackId>.` inside `<docs>/audio_cache/` is purged. Errors are
  /// swallowed — the next reconcile pass can recover any orphan files.
  Future<void> deleteLocalAudioFile(String trackId) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${docs.path}/$_cacheSubdir');
      if (!cacheDir.existsSync()) return;
      for (final f in cacheDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.split('/').last.startsWith('$trackId.'))) {
        try {
          if (f.existsSync()) await f.delete();
        } catch (_) {}
      }
    } catch (e) {
      AppLogger.log('deleteLocalAudioFile failed for $trackId: $e',
          name: _logTag);
    }
  }

  /// Removes the local timed-lyrics file for [trackId] from the documents
  /// directory. The file path is derived deterministically from [trackId] —
  /// `<docs>/<trackId>-lyrics.lrc` — which matches the convention used by
  /// `AudioRepositoryImpl` when it caches fetched lyrics. If the cached
  /// [CacheTrackerModel] also records an explicit [CacheTrackerModel.lyricsFilePath],
  /// that path is purged first as a belt-and-braces measure.
  Future<void> deleteLocalLyricsFile(String trackId) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final deterministic = File('${docs.path}/$trackId-lyrics.lrc');
      if (await deterministic.exists()) {
        await deterministic.delete();
      }
      final entry = _box?.get(trackId);
      final tracked = entry?.lyricsFilePath;
      if (tracked != null && tracked.isNotEmpty && tracked != deterministic.path) {
        final trackedFile = File(tracked);
        if (await trackedFile.exists()) {
          await trackedFile.delete();
        }
      }
    } catch (e) {
      AppLogger.log(
        'deleteLocalLyricsFile failed for $trackId: $e',
        name: _logTag,
      );
    }
  }

  /// Removes a single track from every cache tier and the permanent
  /// library at once. Called by the "Remove from Cache" entry in the
  /// track and album context menus. The method is idempotent — a
  /// missing file or a non-existent row is treated as a no-op rather
  /// than an error so the caller does not have to special-case
  /// "already removed" states.
  ///
  /// The pipeline is:
  /// 1. Delete the on-disk audio file (`<docs>/audio_cache/<id>.<ext>`)
  ///    and the deterministic lyrics file
  ///    (`<docs>/<id>-lyrics.lrc`) plus any tracked lyrics path.
  /// 2. Drop the Hive box entry.
  /// 3. Remove the SQLite `downloaded_tracks` row (if any).
  /// 4. Refresh the sync SQLite mirror.
  /// 5. Emit a `removed` state event so the download icon switches
  ///    back to the unsatisfied (white download) glyph without
  ///    needing a full provider refresh.
  Future<void> removeTrackCompletely(String trackId) async {
    await deleteLocalAudioFile(trackId);
    await deleteLocalLyricsFile(trackId);
    await evictFromTracker(trackId);
    final db = libraryDatabase;
    if (db != null) {
      try {
        await db.removeDownloadedTrack(trackId);
      } catch (e) {
        AppLogger.log(
          'removeTrackCompletely: SQLite row removal failed for $trackId: $e',
          name: _logTag,
        );
      }
    }
    // Mirror is updated in-place by `evictFromTracker` for the Hive
    // add path; we still drop the id defensively in case the row was
    // SQLite-only and the Hive path was a no-op.
    _sqliteDownloadedIds.remove(trackId);
    _emit(trackId, CachedState.removed);
    notifyListeners();
    AppLogger.log(
      'removeTrackCompletely: purged $trackId from cache + library',
      name: _logTag,
    );
  }

  // ---------------------------------------------------------------------------
  // Preload loop
  // ---------------------------------------------------------------------------

  /// Iterates over the [lookAheadLimit] tracks immediately following
  /// [currentIndex] in [queue]. For each track whose trackId is not already
  /// in the Hive box, the [streamUrlResolver] is invoked and the resulting
  /// URL is handed to [cacheStream] for background download.
  ///
  /// The loop is sequential and never blocks playback. If [streamUrlResolver]
  /// is omitted, the call is a no-op for any uncached track (callers can
  /// still rely on `isCached` / `markCaching` to track state).
  Future<void> preloadFromQueue({
    required List<dynamic> queue,
    required int currentIndex,
    required int lookAheadLimit,
    Future<String?> Function(dynamic track)? streamUrlResolver,
    Future<void> Function(String trackId, String streamUrl)? cacheStream,
  }) async {
    if (queue.isEmpty) return;
    final lookAhead = lookAheadLimit < 0 ? 0 : lookAheadLimit;
    final start = currentIndex + 1;
    if (start >= queue.length) return;
    final end = (start + lookAhead).clamp(0, queue.length);

    for (var i = start; i < end; i++) {
      final track = queue[i];
      if (track == null) continue;
      final trackId = (track as dynamic).id as String?;
      if (trackId == null) continue;
      if (isCached(trackId)) continue;
      if (isActivelyCaching(trackId)) continue;

      if (streamUrlResolver == null || cacheStream == null) continue;

      try {
        final url = await streamUrlResolver(track);
        if (url == null || url.isEmpty || !url.startsWith('http')) continue;
        markCaching(trackId);
        unawaited(
          cacheStream(trackId, url).whenComplete(() {
            markNotCaching(trackId);
          }),
        );
      } catch (e) {
        AppLogger.log('Preload resolve failed for $trackId: $e',
            name: _logTag);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _emit(String trackId, CachedState state) {
    if (_stateEvents.isClosed) return;
    _stateEvents.add(CachedStateEvent(trackId, state));
    notifyListeners();
  }

  @override
  void dispose() {
    _sqliteDownloadedIds.clear();
    _stateEvents.close();
    _box?.close();
    super.dispose();
  }
}
