import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/datasources/local/playlist_database.dart';
import '../../domain/entities/auto_dj_mode.dart';
import '../../domain/entities/video.dart';
import '../../domain/repositories/audio_repository.dart';
import '../../presentation/providers/player_provider.dart';
import '../constants/network_state.dart';
import '../utils/app_logger.dart';
import 'auto_dj_routing_service.dart';
import 'connectivity_service.dart';
import 'hybrid_cache_service.dart';

/// Centralised coordinator for the playback queue and the Auto DJ engine.
///
/// Responsibility matrix:
///
/// * **Manual queue** — tracks appended by the user (single tap, "Add to
///   Queue" from a context menu, playlist open, album open, ...). The
///   queue is finite and is the unit that "ends" — when it does, the
///   player must stop unless Auto DJ has been explicitly engaged.
/// * **Auto DJ** — explicit user choice. When `isAutoDJEnabled == true`, the
///   completion handler hands the baton to [generateNextAutoDJTrack] which
///   picks the next track from the appropriate source (online AutoNext, or
///   the offline Hive cache shuffle pool).
///
/// The class is a [ChangeNotifier] so the UI can `context.watch` the engine
/// state (e.g. to illuminate the Auto DJ icon when it is engaged).
class QueueManager extends ChangeNotifier {
  static const String _logTag = 'QueueManager';

  final AudioRepository audioRepository;
  final HybridCacheService hybridCache;
  final ConnectivityService connectivity;
  final PlaylistDatabase? libraryDatabase;

  /// Optional map of trackId -> cached metadata (title, author, thumbnail).
  /// The host wires this from the [PlayerProvider]'s recently played list so
  /// the offline pool can produce tracks with real titles instead of
  /// placeholder strings. Missing entries fall back to a minimal placeholder
  /// [Track] built from the trackId alone.
  Map<String, Track> Function() metadataResolver = () => const <String, Track>{};

  bool _isAutoDJEnabled = false;
  NetworkState _networkState = NetworkState.unknown;
  StreamSubscription<NetworkState>? _connectivitySub;

  /// Late-bound reverse reference to the host [PlayerProvider]. Set after
  /// construction (in `PlayerProvider`'s constructor) to break the
  /// `PlayerProvider ⇄ QueueManager` circular wiring at build time. Used
  /// exclusively by [toggleAutoDJ] to forward arm/disarm calls into the
  /// Phase 0 `startAutoQueue` / `disarmAutoQueue` API. Nullable so unit
  /// tests can construct `QueueManager` without spinning up a full
  /// `PlayerProvider`.
  PlayerProvider? _playerProvider;

  /// Phase 2: the per-mode router that drives the 5 active
  /// `AutoDJMode` strategies. Optional so legacy callers and unit
  /// tests can run without it. When bound, [generateNextAutoDJTrack]
  /// consults the router first; when unbound, the original online
  /// / offline shuffle path remains the fallback.
  AutoDjRoutingService? _router;

  /// The currently-selected Auto DJ mode, mirrored from
  /// [PlayerProvider.setAutoDJMode] so [generateNextAutoDJTrack] can
  /// pass the right mode to the router. Defaults to
  /// [AutoDJMode.off] so a router call before any mode selection
  /// is a clean null-return.
  AutoDJMode _currentMode = AutoDJMode.off;
  AutoDJMode get currentMode => _currentMode;

  /// Session-recently-played track id memory. Backs the spec's
  /// "runtime session memory array tracking recently played song
  /// IDs — never choose a track that has already been heard within
  /// the current active listening index". Bounded so the set
  /// doesn't grow without limit during long sessions.
  final Set<String> _recentSessionIds = <String>{};
  static const int _maxRecentSessionIds = 50;

  /// Session-recently-played **track** history (insertion order
  /// — most recent at index 0). Backs the Same-Genre
  /// 3-track extended memory artist-penalization matrix in
  /// [AutoDjRoutingService._sameGenre]. The matrix walks this
  /// list with index 0 = immediate last track, index 1 = two
  /// tracks ago, index 2 = three tracks ago. We deliberately
  /// do NOT expose a public setter: the engine fills this
  /// list itself via [rememberPlayedTrack] every time a track
  /// is committed to the history pipeline, so the matrix is
  /// always exactly the last 3 tracks played under the
  /// routing service's supervision.
  final List<Track> _sessionHistory = <Track>[];
  static const int _maxSessionHistoryLength = 3;

  /// Spec 2G Fix #5: read-only view of the recent session
  /// history (newest first, capped at 3 tracks by
  /// [_maxSessionHistoryLength]). Returned as
  /// [List.unmodifiable] so callers cannot accidentally
  /// mutate the QueueManager's internal state via shared
  /// reference — the engine is the sole writer to
  /// [_sessionHistory] (via [rememberPlayedTrack]).
  ///
  /// Used by the gapless mixer's lookahead callback so
  /// the Smart DJ artist-diversity term and the Same
  /// Genre artist-decay matrix receive actual recent-pick
  /// context instead of an empty list (the pre-fix
  /// behaviour, per audit §8.4).
  List<Track> get sessionHistory =>
      List<Track>.unmodifiable(_sessionHistory);

  void setRouter(AutoDjRoutingService router) {
    _router = router;
  }

  void setCurrentMode(AutoDJMode mode) {
    _currentMode = mode;
  }

  /// Re-anchors the Auto DJ engine's active seed parameters to
  /// [newTrack]. Called by [PlayerProvider.setQueue] when the user
  /// manually loads a new track (tile tap, context menu, search
  /// selection, playlist open) while Auto DJ is armed.
  ///
  /// Per the Manual Interruption Preservation rule:
  ///
  ///   * The engine state (`_isAutoDJEnabled`) is left untouched —
  ///     the miniplayer / fullscreen AUTODJ icon stays lit and the
  ///     continuation loop keeps running.
  ///   * The active seed parameters (artist / genre / sub-genre)
  ///     are forwarded to the routing service so the next
  ///     15-second-lookahead trigger parses the fresh target keys
  ///     and continues uninterrupted music generation in the
  ///     user-selected mode (Same Artist, Similar Songs, ...).
  ///   * The session dedupe set ([_recentSessionIds]) and the
  ///     per-mode rolling window held on the router are intentionally
  ///     preserved — the user's intent is "pivot the seed mid
  ///     session", not "start fresh".
  ///
  /// Safe to call when no router is bound (legacy / test path):
  /// the call is silently skipped.
  void updateActiveSeedProfile(Track newTrack) {
    _router?.updateActiveSeedProfile(newTrack);
  }

  void rememberPlayed(String trackId) {
    _recentSessionIds.add(trackId);
    if (_recentSessionIds.length > _maxRecentSessionIds) {
      // Drop the oldest insertion order entry. Set iteration order
      // is insertion order in Dart, so the first element is the
      // oldest.
      final oldest = _recentSessionIds.first;
      _recentSessionIds.remove(oldest);
    }
  }

  /// Pushes [track] onto the front of the session history
  /// (newest-first ordering) and trims the list to the last
  /// 3 entries. Backs the Same-Genre artist-decay matrix in
  /// [AutoDjRoutingService._sameGenre].
  ///
  /// The list is internal — the routing service reads it via
  /// the [resolveNext] `history` parameter — so callers should
  /// use the existing [rememberPlayed] path (which calls this
  /// method) instead of touching the field directly.
  void rememberPlayedTrack(Track track) {
    _sessionHistory.insert(0, track);
    if (_sessionHistory.length > _maxSessionHistoryLength) {
      _sessionHistory.removeRange(
        _maxSessionHistoryLength,
        _sessionHistory.length,
      );
    }
  }

  bool get isAutoDJEnabled => _isAutoDJEnabled;
  bool get isOffline => _networkState == NetworkState.offline;
  bool get isOnline => _networkState == NetworkState.online;
  NetworkState get networkState => _networkState;

  QueueManager({
    required this.audioRepository,
    required this.hybridCache,
    required this.connectivity,
    this.libraryDatabase,
  });

  /// Late-binding setter. The host [PlayerProvider] calls this from its
  /// constructor (right after the [QueueManager] is handed in) so the
  /// `QueueManager.toggleAutoDJ` chain can route arm/disarm calls back
  /// into the new `PlayerProvider` API. Idempotent — calling more than
  /// once simply rebinds to the latest reference.
  void setPlayerProvider(PlayerProvider playerProvider) {
    _playerProvider = playerProvider;
  }

  /// Wires the connectivity listener so the offline / online mode of
  /// [generateNextAutoDJTrack] flips automatically when the device
  /// transitions. Idempotent — call once during [main].
  void start() {
    if (_connectivitySub != null) return;
    _networkState = connectivity.state;
    _connectivitySub = connectivity.stateStream.listen((state) {
      if (_networkState == state) return;
      _networkState = state;
      AppLogger.log(
        'Network state -> ${state.name} (Auto DJ hot handoff armed)',
        name: _logTag,
      );
      notifyListeners();
    });
  }

  /// Engages the Auto DJ engine. The player will continue generating
  /// next tracks after the manual queue is exhausted.
  void enableAutoDJ() {
    if (_isAutoDJEnabled) return;
    _isAutoDJEnabled = true;
    AppLogger.log('Auto DJ enabled', name: _logTag);
    notifyListeners();
  }

  /// Disengages the Auto DJ engine. After the current track finishes the
  /// player will stop.
  void disableAutoDJ() {
    if (!_isAutoDJEnabled) return;
    _isAutoDJEnabled = false;
    AppLogger.log('Auto DJ disabled', name: _logTag);
    notifyListeners();
  }

  /// Flips the Auto DJ engine state, then forwards the flip into the
  /// Phase 0 `PlayerProvider` API:
  ///
  /// * **Arming** — calls `PlayerProvider.startAutoQueue(currentTrack)`
  ///   so the new predictive engine flag is raised against the
  ///   currently-loaded track. Skipped if no track is loaded (e.g. the
  ///   user tapped the icon before any track started playing).
  /// * **Disarming** — calls `PlayerProvider.disarmAutoQueue()` so the
  ///   predictive engine flag drops. The manual queue is preserved and
  ///   playback is NOT interrupted, per the spec.
  ///
  /// Returns the new visual state for convenience (mirrors the legacy
  /// `isAutoDJEnabled` getter so `PlayerProvider.toggleAutoDJ` can keep
  /// its existing return contract).
  bool toggleAutoDJ() {
    debugPrint('QueueManager.toggleAutoDJ: wasEnabled=$_isAutoDJEnabled');
    if (_isAutoDJEnabled) {
      disableAutoDJ();
      // Disarm — do not clear the queue, just stop the engine from
      // appending. Uses the `?.` operator so unit tests that
      // construct QueueManager without a PlayerProvider don't crash.
      _playerProvider?.disarmAutoQueue();
    } else {
      enableAutoDJ();
      // Arm — point the predictive engine at whatever track is
      // currently loaded. If nothing is loaded, the arm is a no-op
      // (the flag flips to enabled but the engine has no seed).
      final provider = _playerProvider;
      if (provider != null) {
        final currentTrack = provider.currentTrack;
        if (currentTrack != null) {
          provider.startAutoQueue(currentTrack);
        }
      }
    }
    return _isAutoDJEnabled;
  }

  /// True iff the engine will hand the next-track baton to
  /// [generateNextAutoDJTrack] when the current track completes.
  bool get isActive => _isAutoDJEnabled;

  /// Produces the next track for the Auto DJ engine. The Phase 2
  /// flow is:
  ///
  ///   1. **Off mode** → return `null` immediately so the parent
  ///      service halts the queue.
  ///   2. **Router is bound** → ask the [AutoDjRoutingService] to
  ///      pick the next track for [_currentMode], passing
  ///      [_recentSessionIds] as the dedupe set.
  ///   3. **Router is unbound** (legacy / test) → fall back to the
  ///      pre-Phase-2 online AutoNext path, then the offline
  ///      shuffle pool. Kept intact so existing call sites (and
  ///      the regression tests for the original spec) keep
  ///      working without any router wiring.
  ///
  /// The returned `Track?` is fed to `PlayerProvider._generateAutoDJNext`
  /// unchanged, so the Phase 0 contract — "resolve the upcoming
  /// item token" — is preserved.
  Future<Track?> generateNextAutoDJTrack(Track currentTrack) async {
    if (!_isAutoDJEnabled) return null;
    rememberPlayed(currentTrack.id);
    rememberPlayedTrack(currentTrack);

    if (_currentMode == AutoDJMode.off) return null;

    final router = _router;
    if (router != null) {
      // Guard against the cold-start race where `resolveNext`
      // lands on the routing service before the Smart-DJ
      // bootstrap fusion has populated its Top-Artists /
      // Top-Genres cache. The completer on `PlayerProvider`
      // fires once `_maybeBootstrapSmartDjFusion` finishes
      // pushing the liked-songs aggregation into the router;
      // awaiting it here means the first `resolveNext` always
      // sees a primed cache. Idempotent: if bootstrap already
      // completed this is a microtask-level no-op. The
      // optional chain covers unit tests that construct
      // `QueueManager` without binding a `PlayerProvider`.
      final pp = _playerProvider;
      if (pp != null) {
        await pp.smartDjBootstrapInitialization;
      }
      try {
        final pick = await router.resolveNext(
          mode: _currentMode,
          current: currentTrack,
          recentIds: Set<String>.from(_recentSessionIds),
          history: List<Track>.unmodifiable(_sessionHistory),
        );
        if (pick != null) return pick;
      } catch (e) {
        AppLogger.log(
          'Router failed (${_currentMode.name}); falling back to legacy path: $e',
          name: _logTag,
        );
      }
    }

    if (_networkState == NetworkState.online) {
      try {
        final upNexts = await audioRepository.getUpNexts(currentTrack);
        if (upNexts.isNotEmpty) {
          return upNexts.first;
        }
      } catch (e) {
        AppLogger.log(
          'Online AutoNext failed, falling back to local pool: $e',
          name: _logTag,
        );
      }
    }

    return _selectOfflineTrack(currentTrack);
  }

  /// Builds the offline shuffle pool: every trackId registered in the Hive
  /// tracker box, plus the union of favorite and downloaded trackIds stored
  /// in the SQLite library (the "cross-database integrity" requirement from
  /// the spec). Excludes [currentTrackId] and resolves each surviving id to
  /// a [Track] using the configured [metadataResolver] (falling back to a
  /// minimal placeholder).
  Future<Track?> _selectOfflineTrack(Track currentTrack) async {
    final pool = <String>{};

    // 1. Hive casual cache (the 200 last-played / pre-buffered tracks).
    pool.addAll(hybridCache.getCachedTrackIds());

    // 2. SQLite library cross-check: enrich the pool with anything the
    //    user has marked as part of the permanent library (favorites and
    //    tracks bound to downloaded albums).
    final db = libraryDatabase;
    if (db != null) {
      try {
        final favIds = await db.getFavoriteTrackIds();
        if (favIds.isNotEmpty) pool.addAll(favIds);
        final downloadedIds = await db.getAllDownloadedTrackIds();
        if (downloadedIds.isNotEmpty) pool.addAll(downloadedIds);
      } catch (e) {
        AppLogger.log(
          'SQLite cross-check for offline pool failed: $e',
          name: _logTag,
        );
      }
    }

    pool.remove(currentTrack.id);
    if (pool.isEmpty) {
      AppLogger.log(
        'Offline Auto DJ pool is empty after exclusion',
        name: _logTag,
      );
      return null;
    }

    final shuffled = pool.toList()..shuffle();
    final nextId = shuffled.first;
    AppLogger.log(
      'Offline Auto DJ picked $nextId (pool size ${pool.length})',
      name: _logTag,
    );
    return await _buildTrackFromId(nextId);
  }

  /// Resolves a [TrackId] to a [Track] via the three-tier
  /// synthesis path (Phase 6 cached-metadata spec):
  ///
  ///   1. **In-memory resolver** — the live `metadataResolver()`
  ///      closure (typically backed by `PlayerProvider`'s
  ///      recently-played list). Fast path; returns whatever
  ///      the host wired.
  ///   2. **SQLite permanent library** — `PlaylistDatabase.getDownloadedTrack`
  ///      is consulted for a full metadata row. This is the
  ///      authoritative source for tracks the user has
  ///      downloaded or favorited.
  ///   3. **Hive transient cache** — `hybridCache.getTrackerEntry`
  ///      is consulted for the display-metadata fields added in
  ///      Phase 6 (`title` / `author` / `thumbnailUrl`). If the
  ///      entry is present and its `title` is non-null, the
  ///      synthesis returns a populated `Track` from the Hive
  ///      tier alone.
  ///   4. **Stub fallback** — returns the legacy
  ///      `'Cached Track'` placeholder. This is the
  ///      last-resort path; reaching it means the track is in
  ///      neither storage tier (e.g. a gapless pre-buffer that
  ///      crashed before the cache commit landed).
  Future<Track> _buildTrackFromId(String trackId) async {
    // Tier 1: in-memory resolver (existing fast path)
    final metadata = metadataResolver();
    final cached = metadata[trackId];
    if (cached != null) return cached;

    // Tier 2: SQLite downloaded_tracks mirror
    final db = libraryDatabase;
    if (db != null) {
      try {
        final downloaded = await db.getDownloadedTrack(trackId);
        if (downloaded != null) {
          return Track(
            id: trackId,
            title: (downloaded['title'] as String?) ?? 'Cached Track',
            author: downloaded['author'] as String?,
            thumbnailUrl: downloaded['thumbnailUrl'] as String?,
            // C1: preserve null. `0` would silently render as
            // `0:00` in the UI; null renders as the em-dash
            // placeholder via [formatDuration]. Live-stream
            // tracks and unlisted videos with no API duration
            // now show as unknown in the queue.
            duration: (downloaded['durationSeconds'] as int?) == null
                ? null
                : Duration(seconds: downloaded['durationSeconds'] as int),
            source: TrackSource.youtube,
          );
        }
      } catch (e) {
        AppLogger.log(
          '_buildTrackFromId: SQLite tier lookup failed for $trackId: $e',
          name: _logTag,
        );
      }
    }

    // Tier 3: Hive tracker entry (display metadata when populated).
    // The Hive tracker does not carry a duration field, so the
    // synthesised Track reports `null` (the C1 "unknown" sentinel)
    // — the UI renders it as `—:—` via [formatDuration]. C3
    // contract: no `Duration.zero` leak in the synthesis paths.
    final hiveEntry = hybridCache.getTrackerEntry(trackId);
    if (hiveEntry != null && hiveEntry.title != null) {
      return Track(
        id: trackId,
        title: hiveEntry.title!,
        author: hiveEntry.author,
        thumbnailUrl: hiveEntry.thumbnailUrl ?? '',
        duration: null,
        source: TrackSource.youtube,
      );
    }

    // Final fallback: stub. Unknown in every dimension; duration
    // is `null` not `Duration.zero` for the same reason as the
    // Hive branch above. Per C1, "no metadata" must not be
    // mis-rendered as "0 seconds long".
    return Track(
      id: trackId,
      title: 'Cached Track',
      duration: null,
      source: TrackSource.youtube,
    );
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }
}
