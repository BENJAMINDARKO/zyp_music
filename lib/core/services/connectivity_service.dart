import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../constants/network_state.dart';
import '../../data/repositories/audio_repository_impl.dart';
import '../../data/datasources/remote/youtube_remote_datasource.dart';
import '../../data/datasources/remote/lyrics_remote_datasource.dart';
import '../utils/app_logger.dart';

/// Global reactive listener for device connectivity.
///
/// Lifecycle:
///
/// 1. `main.dart` constructs an instance after the audio repository and
///    remote data sources exist, then calls [initialize] exactly once.
/// 2. [initialize] probes the current connectivity and synchronously
///    pushes the system into the right starting state (`online` or
///    `offline`). It then subscribes to `onConnectivityChanged` and
///    reacts to every transition for the rest of the app's lifetime.
/// 3. On an `offline -> online` transition the service explicitly wakes
///    the network clients by calling [YoutubeRemoteDataSource.refreshNetworkClientHeaders]
///    and [LyricsRemoteDataSource.retryPendingConnections]. This is the
///    critical fix for the bug where an app booted offline would stay
///    stuck on broken clients even after the radio came back.
///
/// The class is also a [ChangeNotifier] so the UI layer can `context.watch`
/// it (e.g. to render a small "offline" badge) without subscribing to the
/// stream directly.
class ConnectivityService extends ChangeNotifier {
  static const String _logTag = 'ConnectivityService';

  final AudioRepositoryImpl audioRepository;
  final YoutubeRemoteDataSource remoteDataSource;
  final LyricsRemoteDataSource lyricsDataSource;

  NetworkState _state = NetworkState.unknown;
  NetworkState get state => _state;
  bool get isOffline => _state == NetworkState.offline;
  bool get isOnline => _state == NetworkState.online;

  final StreamController<NetworkState> _stateController =
      StreamController<NetworkState>.broadcast();
  Stream<NetworkState> get stateStream => _stateController.stream;

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  ConnectivityService({
    required this.audioRepository,
    required this.remoteDataSource,
    required this.lyricsDataSource,
  });

  /// Performs the synchronous initial probe and attaches the long-lived
  /// listener. Safe to call once during `main()`; subsequent calls are
  /// ignored so we never end up with two parallel subscriptions.
  Future<void> initialize() async {
    if (_subscription != null) return;

    final connectivity = Connectivity();
    final initial = await connectivity.checkConnectivity();
    _handleChange(initial, isInitialProbe: true);

    _subscription = connectivity.onConnectivityChanged.listen(
      (results) => _handleChange(results, isInitialProbe: false),
    );
  }

  void _handleChange(
    List<ConnectivityResult> results, {
    required bool isInitialProbe,
  }) {
    final hasNetwork = results.any((r) => r != ConnectivityResult.none);

    if (!hasNetwork) {
      // Going (or starting) offline. We only need to flip the repository
      // flag; existing local-cache lookup structures and any in-flight
      // audio playback are left untouched.
      if (_state != NetworkState.offline) {
        AppLogger.log(
          isInitialProbe
              ? 'Startup with no active network — locking to offline mode'
              : 'Network lost — switching to offline mode',
          name: _logTag,
        );
        _transition(NetworkState.offline);
      }
      audioRepository.setOfflineMode(true);
      return;
    }

    final wasOffline = _state == NetworkState.offline;
    if (isInitialProbe) {
      AppLogger.log(
        'Startup with active network (${_describe(results)})',
        name: _logTag,
      );
    } else if (wasOffline) {
      AppLogger.log(
        'Network restored (${_describe(results)}) — waking up network clients',
        name: _logTag,
      );
    }
    _transition(NetworkState.online);
    audioRepository.setOfflineMode(false);

    // The CRITICAL FIX: when we just came back from offline, the YouTube
    // and YTMusic clients were initialised against a dead network. They
    // have to be rebuilt before any future search / stream / metadata
    // call can succeed. Existing audio playback is intentionally not
    // touched — this is a header / client refresh, not a re-play.
    if (wasOffline) {
      unawaited(_refreshNetworkClients());
    }
  }

  Future<void> _refreshNetworkClients() async {
    try {
      await remoteDataSource.refreshNetworkClientHeaders();
    } catch (e) {
      AppLogger.log('refreshNetworkClientHeaders failed: $e', name: _logTag);
    }
    try {
      lyricsDataSource.retryPendingConnections();
    } catch (e) {
      AppLogger.log('retryPendingConnections failed: $e', name: _logTag);
    }
  }

  String _describe(List<ConnectivityResult> results) {
    return results
        .where((r) => r != ConnectivityResult.none)
        .map((r) => r.name)
        .join('+');
  }

  void _transition(NetworkState newState) {
    if (_state == newState) return;
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _stateController.close();
    super.dispose();
  }
}
