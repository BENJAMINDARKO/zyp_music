import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/datasources/local/playlist_database.dart';
import '../../domain/entities/video.dart';
import '../../domain/repositories/audio_repository.dart';
import '../constants/network_state.dart';
import '../utils/app_logger.dart';
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

  /// Flips the Auto DJ engine state. Returns the new state for convenience.
  bool toggleAutoDJ() {
    if (_isAutoDJEnabled) {
      disableAutoDJ();
    } else {
      enableAutoDJ();
    }
    return _isAutoDJEnabled;
  }

  /// True iff the engine will hand the next-track baton to
  /// [generateNextAutoDJTrack] when the current track completes.
  bool get isActive => _isAutoDJEnabled;

  /// Produces the next track for the Auto DJ engine. Selects the online
  /// or offline source based on the current network state, with a graceful
  /// fallback if the online path throws.
  ///
  /// Returns `null` when no candidate is available (e.g. an empty offline
  /// pool with no network).
  Future<Track?> generateNextAutoDJTrack(Track currentTrack) async {
    if (!_isAutoDJEnabled) return null;

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
    return _buildTrackFromId(nextId);
  }

  Track _buildTrackFromId(String trackId) {
    final metadata = metadataResolver();
    final cached = metadata[trackId];
    if (cached != null) return cached;
    return Track(
      id: trackId,
      title: 'Cached Track',
      duration: Duration.zero,
      source: TrackSource.youtube,
    );
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }
}
