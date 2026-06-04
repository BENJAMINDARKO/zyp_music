import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/models/cache_tracker_model.dart';
import '../../core/utils/app_logger.dart';

/// Public cache state exposed to the UI layer.
enum CachedState { idle, caching, success }

/// Lightweight event pushed whenever a track transitions between cache states.
class CachedStateEvent {
  final String trackId;
  final CachedState state;
  const CachedStateEvent(this.trackId, this.state);
}

/// Hybrid two-tier cache backed by a single memory-mapped Hive box.
///
/// Tier A — **Favorites** (persistent, protected). Entries flagged with
/// `isFavorite = true` are completely immune to automated eviction and to
/// non-favorite LRU bounds.
///
/// Tier B — **Casual LRU** (bounded at [_maxCasualEntries], 200 by default).
/// When the box would exceed the cap, the 10 oldest non-favorite entries are
/// removed in a single `box.deleteAll(keys)` call. Their audio files and any
/// persisted lyrics are physically removed from local storage in the same step.
///
/// The service also exposes a transient in-memory `caching` set so the UI
/// can distinguish "actively writing bytes" from "fully cached" without
/// hitting disk. Persisted `timedLyrics` ride along with the box record and
/// are dropped together on eviction.
class HybridCacheService extends ChangeNotifier {
  static const String _logTag = 'HybridCacheService';
  static const String boxName = 'cache_tracker_box';

  static const int _maxCasualEntries = 200;
  static const int _evictBatchSize = 10;

  static const String _cacheSubdir = 'audio_cache';

  Box<CacheTrackerModel>? _box;
  final Set<String> _activeCaching = <String>{};
  final StreamController<CachedStateEvent> _stateEvents =
      StreamController<CachedStateEvent>.broadcast();

  Stream<CachedStateEvent> get stateStream => _stateEvents.stream;

  bool get isInitialized => _box?.isOpen ?? false;

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

  /// True iff the track is currently being written to disk.
  bool isActivelyCaching(String trackId) => _activeCaching.contains(trackId);

  /// Resolves the public state used by the download icon state machine.
  CachedState getCachedState(String trackId) {
    if (isActivelyCaching(trackId)) return CachedState.caching;
    if (isCached(trackId)) return CachedState.success;
    return CachedState.idle;
  }

  /// Returns the persisted LRC (or other timed-lyric blob) for a track, or
  /// `null` if no lyrics are stored. Synchronous — backed by memory-mapped
  /// Hive, so it is safe to call from a widget build.
  String? getLyrics(String trackId) {
    return _box?.get(trackId)?.timedLyrics;
  }

  bool isFavorite(String trackId) {
    return _box?.get(trackId)?.isFavorite ?? false;
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
    );
    await box.put(trackId, next);
    _activeCaching.remove(trackId);

    await _enforceCasualCap();
    _emit(trackId, CachedState.success);
  }

  /// Records a track access by bumping its `cachedAt` timestamp. Used for
  /// passive LRU tracking when a track is played (not just downloaded).
  Future<void> touch(String trackId) async {
    final box = _box;
    if (box == null) return;
    final existing = box.get(trackId);
    if (existing == null) return;
    await box.put(
      trackId,
      existing.copyWith(cachedAt: DateTime.now().millisecondsSinceEpoch),
    );
  }

  /// Persists timed-lyrics text against a track. If the track is not yet
  /// cached, a stub record is created so the lyrics survive across sessions.
  Future<void> setLyrics(String trackId, String lrc) async {
    final box = _box;
    if (box == null) return;
    final existing = box.get(trackId);
    final next = (existing ??
            CacheTrackerModel(
              trackId: trackId,
              cachedAt: DateTime.now().millisecondsSinceEpoch,
            ))
        .copyWith(timedLyrics: lrc);
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
    await _enforceCasualCap();
  }

  // ---------------------------------------------------------------------------
  // Hybrid eviction routine
  // ---------------------------------------------------------------------------

  /// Bounded LRU enforcement. Counts only non-favorite entries; if the
  /// count exceeds [_maxCasualEntries], sorts the protected-eligible set by
  /// `cachedAt` ascending, picks the [_evictBatchSize] oldest, deletes their
  /// physical audio files + their persisted lyrics, then batch-deletes the
  /// box keys in a single `box.deleteAll` call.
  Future<void> _enforceCasualCap() async {
    final box = _box;
    if (box == null) return;

    final casualEntries = <_CasualEntry>[];
    for (final key in box.keys) {
      final entry = box.get(key);
      if (entry == null) continue;
      if (entry.isFavorite) continue;
      casualEntries.add(_CasualEntry(key.toString(), entry.cachedAt));
    }

    final overflow = casualEntries.length - _maxCasualEntries;
    if (overflow <= 0) return;

    casualEntries.sort((a, b) => a.cachedAt.compareTo(b.cachedAt));
    final toEvict = casualEntries
        .take(_evictBatchSize)
        .map((e) => e.trackId)
        .toList(growable: false);

    await _deletePhysicalAssetsFor(toEvict);
    await box.deleteAll(toEvict);

    AppLogger.log(
      'LRU eviction: removed ${toEvict.length} casual entries (had ${casualEntries.length})',
      name: _logTag,
    );
  }

  Future<void> _deletePhysicalAssetsFor(List<String> trackIds) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${docs.path}/$_cacheSubdir');
      if (!cacheDir.existsSync()) return;
      for (final id in trackIds) {
        final matches = cacheDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.split('/').last.startsWith('$id.'));
        for (final f in matches) {
          try {
            if (f.existsSync()) await f.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      AppLogger.log('Physical eviction failed: $e', name: _logTag);
    }
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
    _stateEvents.close();
    _box?.close();
    super.dispose();
  }
}

class _CasualEntry {
  final String trackId;
  final int cachedAt;
  const _CasualEntry(this.trackId, this.cachedAt);
}
