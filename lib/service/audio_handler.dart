import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zyp_music/core/utils/app_logger.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import 'package:rxdart/rxdart.dart';
import '../core/utils/network_utils.dart';
import 'auth_service.dart';

class MusicAudioHandler extends BaseAudioHandler {
  final int _instanceId = DateTime.now().microsecondsSinceEpoch;
  AudioPlayer _player = AudioPlayer();
  final AuthService _authService = AuthService();

  /// Exposed for the gapless queue mixer (Phase 3) so it can
  /// wrap the same persistent player in a
  /// [ConcatenatingAudioSource] without spawning a second
  /// decoder. Production callers should go through the
  /// [play], [pause], [seek] methods; raw access is reserved
  /// for engine wiring.
  AudioPlayer get player => _player;

  /// Phase 4: replaces the internal player with [newPlayer]
  /// (typically the secondary `playerB` produced by the DSP
  /// crossfade engine). All active subscriptions are torn
  /// down, the new player's streams are re-wired, the current
  /// [playbackState] is re-emitted from the new player's
  /// state, and the old player is disposed.
  ///
  /// Callers (the DSP engine) must ensure [newPlayer] is
  /// already prepared, playing, and at the correct volume /
  /// speed before the swap — this method is a transport
  /// rebind, not a state reset.
  Future<void> replacePlayer(AudioPlayer newPlayer) async {
    // Capture state from the INCOMING player — it is already
    // playing the next track. Capturing from the old player
    // would snapshot its stopped/idle state and inject a
    // spurious playing=false into the UI.
    //
    // BUG FIX (bugs 1 & 8): the original code declared a first
    // pair of (wasPosition, wasPlaying) from _player (the old,
    // already-stopped player) and then re-declared the same
    // names from newPlayer, which is both a Dart compile error
    // (duplicate locals) and the root cause of the frozen UI:
    // the old-player snapshot wins and forces playing=false.
    final wasPosition = newPlayer.position;
    final wasPlaying = newPlayer.playing;
    final wasLoopMode = _player.loopMode;

    // Cancel all subscriptions BEFORE replacing _player so the
    // _listenToPlayerStreams() call below starts clean.
    await _playerStateSub?.cancel();
    await _processingSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _currentIndexSub?.cancel();
    await _bufferedPositionSub?.cancel();

    final oldPlayer = _player;
    _player = newPlayer;
    await _player.setLoopMode(wasLoopMode);

    // BUG FIX (bug 10): replacePlayer() previously called
    // _listenToPlayerStreams() AND also re-wired every stream
    // inline, resulting in three subscription rounds total
    // (constructor inline, replacePlayer inline, plus the
    // _listenToPlayerStreams() call).  We now delegate entirely
    // to _listenToPlayerStreams() — it already handles all six
    // streams correctly and forwards events into the
    // StreamControllers so external listeners are not dropped.
    _listenToPlayerStreams();

    // Re-emit a playback state derived from the NEW player so
    // any UI listeners that just received the final idle event
    // from the old player immediately see the correct state.
    final reemitState = (playbackState.valueOrNull ?? _defaultPlaybackState)
        .copyWith(
      updatePosition: wasPosition,
      playing: wasPlaying,
      processingState: _convertState(newPlayer.processingState),
      controls: _controls,
      systemActions: _systemActions,
      androidCompactActionIndices: [1, 0, 3],
    );
    debugPrint('[PBS-EMIT] (replacePlayer) playing=${reemitState.playing} '
        'proc=${reemitState.processingState} pos=${reemitState.updatePosition}');
    playbackState.add(reemitState);

    // Force-push the current MediaItem so the OS lockscreen
    // notification, media slider seekbar, and global album art
    // cache immediately attach to the active player thread
    // context instead of lingering on the old player's state.
    final sequence = _player.sequence;
    if (sequence != null && sequence.isNotEmpty) {
      final index = _player.currentIndex ?? 0;
      if (index >= 0 && index < sequence.length) {
        final source = sequence[index];
        if (source.tag is MediaItem) {
          final tagItem = source.tag as MediaItem;
          updateMediaItem(tagItem);
          AppLogger.log(
            '[MediaSessionSync] Re-anchored MediaItem to active player: '
            '${tagItem.id}',
            name: 'MusicAudioHandler',
          );
        }
      }
    }

    await oldPlayer.dispose();
  }

  final skipNextRequested = StreamController<void>.broadcast();
  final skipPreviousRequested = StreamController<void>.broadcast();

  static const _controls = [
    MediaControl.skipToPrevious,
    MediaControl.play,
    MediaControl.pause,
    MediaControl.skipToNext,
  ];

  static const _systemActions = <MediaAction>{
    MediaAction.skipToPrevious,
    MediaAction.play,
    MediaAction.pause,
    MediaAction.skipToNext,
  };

  PlaybackState get _defaultPlaybackState => PlaybackState(
        controls: _controls,
        systemActions: _systemActions,
        androidCompactActionIndices: [1, 0, 3],
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
      );

  var _queue = <MediaItem>[];
  int? _currentIndex;

  StreamSubscription? _playerStateSub;
  StreamSubscription? _processingSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _currentIndexSub;
  StreamSubscription? _bufferedPositionSub;

  /// Tracks which MediaItem id the last [updateMediaItem] call
  /// targeted. Used as a guard in the [durationStream] listener
  /// so a stale duration event (emitted by the old audio source
  /// after a new track has already been pushed) does not revert
  /// the notification to the previous track's data.
  String? _pendingMediaItemId;

  // BUG FIX (bugs 2, 3): these StreamControllers are the
  // stable "public surface" for stream getters.  External
  // subscribers (PlayerProvider, etc.) attach to these once
  // and are never dropped when replacePlayer() swaps the
  // underlying AudioPlayer.  The _listenToPlayerStreams()
  // method re-targets each controller to the new player's
  // streams after every swap.
  final _positionController = BehaviorSubject<Duration>.seeded(Duration.zero);
  final _bufferedPositionController = BehaviorSubject<Duration>.seeded(Duration.zero);
  final _processingStateController = BehaviorSubject<ProcessingState>.seeded(ProcessingState.idle);
  final _durationController = BehaviorSubject<Duration>();

  MusicAudioHandler() {
    debugPrint('[HandlerInit] id=$_instanceId pid=${pid} '
        'this=${identityHashCode(this)} player=${identityHashCode(_player)}');
    debugPrint('[PBS-EMIT] (init) playing=${_defaultPlaybackState.playing} '
        'proc=${_defaultPlaybackState.processingState} '
        'pos=${_defaultPlaybackState.updatePosition}');
    playbackState.add(_defaultPlaybackState);
    _listenToPlayerStreams();
  }

  void _listenToPlayerStreams() {
    // Cancel all existing subscriptions before re-wiring so
    // we never end up with multiple listeners on the same stream.
    _playerStateSub?.cancel();
    _processingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _currentIndexSub?.cancel();
    _bufferedPositionSub?.cancel();

    // BUG FIX (bug 6): the original code added a second,
    // untracked _player.playerStateStream.listen() call for
    // debug logging, leaking one subscription per replacePlayer()
    // call. The debug output is folded into the tracked listener.
    _playerStateSub = _player.playerStateStream.listen((s) {
      debugPrint('[PlayerState] playing=${s.playing} proc=${s.processingState}');
      _onPlayerState(s);
    });

    // BUG FIX (bug 5): _processingSub was assigned twice —
    // first to a plain _onProcessingState listener, then
    // immediately overwritten with a combined listener that also
    // feeds the StreamController. Only the combined version is
    // needed; the first assignment leaked a subscription.
    _processingSub = _player.processingStateStream.listen((state) {
      _processingStateController.add(state);
      _onProcessingState(state);
    });

    // BUG FIX (bug 4): the original _positionSub lambda in
    // _listenToPlayerStreams() was truncated mid-copyWith,
    // missing processingState, controls, systemActions, and the
    // androidCompactActionIndices parameter, as well as the
    // closing debugPrint and playbackState.add calls.  The full
    // implementation matches the working version from replacePlayer().
    _positionSub = _player.positionStream.listen((pos) {
      _positionController.add(pos);
      final current = playbackState.valueOrNull ?? _defaultPlaybackState;
      final newState = current.copyWith(
        updatePosition: pos,
        playing: _player.playing,
        processingState: _convertState(_player.processingState),
        controls: _controls,
        systemActions: _systemActions,
        androidCompactActionIndices: [1, 0, 3],
      );
      debugPrint('[PBS-EMIT] playing=${newState.playing} '
          'proc=${newState.processingState} pos=${newState.updatePosition}');
      playbackState.add(newState);
    });

    _bufferedPositionSub = _player.bufferedPositionStream.listen((pos) {
      _bufferedPositionController.add(pos);
    });

    _durationSub = _player.durationStream.listen((dur) {
      if (dur != null) {
        _durationController.add(dur);
        final item = mediaItem.value;
        if (item != null && item.id == _pendingMediaItemId) {
          updateMediaItem(item.copyWith(duration: dur));
        }
      }
    });

    // BUG FIX (bug 7): the _currentIndexSub lambda was
    // truncated after `final sequence = _player.sequence;`
    // in the original _listenToPlayerStreams(); the full
    // MediaItem-update logic from the replacePlayer() version
    // is restored here.
    _currentIndexSub = _player.currentIndexStream.listen((index) {
      if (index != null && index >= 0) {
        final sequence = _player.sequence;
        if (sequence != null && index < sequence.length) {
          final source = sequence[index];
          if (source.tag is MediaItem) {
            final item = source.tag as MediaItem;
            if (mediaItem.valueOrNull?.id != item.id) {
              updateMediaItem(item);
            }
            final queueIndex = _queue.indexWhere((e) => e.id == item.id);
            if (queueIndex != -1) {
              _currentIndex = queueIndex;
            } else {
              _currentIndex = index;
            }
          }
        }
      }
    });
  }

  // ── Public stream getters ─────────────────────────────────────────────────
  //
  // BUG FIX (bugs 2 & 3): these getters previously had two competing
  // declarations each — one returning _player.<stream> directly, one
  // returning the StreamController stream.  Dart does not allow duplicate
  // getter names, so the file would not compile.  The correct form is
  // always the StreamController version: those streams are stable across
  // replacePlayer() calls, whereas the direct-player streams become dead
  // the moment the old player is disposed.

  Duration get duration => _player.duration ?? Duration.zero;

  Stream<ProcessingState> get processingStateStream => _processingStateController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get bufferedPositionStream => _bufferedPositionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;

  // ─────────────────────────────────────────────────────────────────────────

  int? get currentIndex => _currentIndex;
  int get queueLength => _queue.length;
  bool get currentTrackCompleted =>
      !_player.playing &&
      _player.processingState == ProcessingState.completed;

  void _onPlayerState(PlayerState state) {
    final current = playbackState.valueOrNull ?? _defaultPlaybackState;
    final newState = current.copyWith(
      playing: state.playing,
      processingState: _convertState(state.processingState),
      controls: _controls,
      systemActions: _systemActions,
      androidCompactActionIndices: [1, 0, 3],
    );
    debugPrint('[PBS-EMIT] playing=${newState.playing} '
        'proc=${newState.processingState} pos=${newState.updatePosition}');
    playbackState.add(newState);
  }

  void _onProcessingState(ProcessingState state) {
    if (state == ProcessingState.completed && _queue.isEmpty && _currentIndex == null) {
      stop();
    }
  }

  AudioProcessingState _convertState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  bool get isPlaying => _player.playing;

  Duration get position => _player.position;

  Future<void> playTrack(String url, MediaItem item) async {
    // Guard against empty paths matching log crash states.
    if (url.trim().isEmpty || url.endsWith('/audio_cache/.mp3')) {
      final errState = playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
      );
      debugPrint('[PBS-EMIT] (playTrack guard) playing=${errState.playing} '
          'proc=${errState.processingState} pos=${errState.updatePosition}');
      playbackState.add(errState);
      throw ArgumentError(
          'Aborting playback execution: Invalid or incomplete stream URL/Cache path.');
    }

    try {
      _currentIndex = _queue.indexWhere((e) => e.id == item.id);
      if (_currentIndex == -1) _currentIndex = null;

      updateMediaItem(item);

      final headers = await _getHeaders();
      final Uri uri;
      try {
        if (url.startsWith('file://') || !url.startsWith('http')) {
          uri = url.startsWith('file://')
              ? Uri.parse(url)
              : Uri.file(url);
        } else {
          final client = http.Client();
          try {
            uri = Uri.parse(
              await NetworkUtils.resolveRedirects(
                client,
                url,
                headers: headers,
              ),
            );
          } finally {
            client.close();
          }
        }
      } catch (e) {
        throw Exception('Failed to resolve URL: $e');
      }

      AppLogger.log('Playing Resolved URL: $uri', name: 'MusicAudioHandler');
      await _player.stop();

      // Pass headers down to AudioSource config to keep
      // connections alive on YouTube paths.
      if (uri.isScheme('HTTP') || uri.isScheme('HTTPS')) {
        await _player.setAudioSource(
          LockCachingAudioSource(uri, headers: headers, tag: item),
        );
      } else {
        await _player.setAudioSource(AudioSource.uri(uri, tag: item));
      }

      unawaited(_player.play());
    } catch (e) {
      final errState = playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
      );
      debugPrint('[PBS-EMIT] (playTrack catch) playing=${errState.playing} '
          'proc=${errState.processingState} pos=${errState.updatePosition}');
      playbackState.add(errState);
      AppLogger.log('Error in MusicAudioHandler.playTrack: $e',
          name: 'MusicAudioHandler');
      rethrow;
    }
  }

  Future<void> setQueue(List<MediaItem> items, {int startIndex = 0}) async {
    _queue = List.from(items);
    _currentIndex = startIndex;
    queue.add(_queue);
  }

  void clearQueue() {
    _queue = [];
    _currentIndex = null;
  }

  @override
  Future<void> play() async {
    debugPrint(
        '[HandlerCmd] play() CALLED id=$_instanceId pid=${pid}\n${StackTrace.current}');
    await _player.play();
  }

  @override
  Future<void> pause() async {
    debugPrint(
        '[HandlerCmd] pause() CALLED id=$_instanceId pid=${pid}\n${StackTrace.current}');
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> stop() async {
    await _player.stop();
    final stopState = _defaultPlaybackState.copyWith(
      controls: _controls,
      systemActions: _systemActions,
      androidCompactActionIndices: [1, 0, 3],
    );
    debugPrint('[PBS-EMIT] (stop) playing=${stopState.playing} '
        'proc=${stopState.processingState} pos=${stopState.updatePosition}');
    playbackState.add(stopState);
  }

  @override
  Future<void> skipToNext() async {
    if (_currentIndex != null && _currentIndex! + 1 < _queue.length) {
      skipNextRequested.add(null);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_currentIndex != null && _currentIndex! > 0) {
      skipPreviousRequested.add(null);
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final loopMode = _convertAudioServiceRepeatMode(repeatMode);
    await _player.setLoopMode(loopMode);
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
  }

  LoopMode _convertAudioServiceRepeatMode(AudioServiceRepeatMode mode) {
    switch (mode) {
      case AudioServiceRepeatMode.none:
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        return LoopMode.off;
      case AudioServiceRepeatMode.one:
        return LoopMode.one;
    }
  }

  Future<Map<String, String>> _getHeaders() async {
    final cookies = await _authService.getCookies();
    final headers = <String, String>{
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
    };
    headers['Referer'] = 'https://www.youtube.com/';
    if (cookies != null && cookies.isNotEmpty) {
      headers['Cookie'] = cookies;
    }
    return headers;
  }

  Future<Map<String, String>> getHeaders() => _getHeaders();

  Future<String> resolveRedirects(String url) async {
    final client = http.Client();
    try {
      return await NetworkUtils.resolveRedirects(client, url, headers: null);
    } finally {
      client.close();
    }
  }

  void dispose() {
    _playerStateSub?.cancel();
    _processingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _currentIndexSub?.cancel();
    _bufferedPositionSub?.cancel();
    _processingStateController.close();
    _positionController.close();
    _bufferedPositionController.close();
    _durationController.close();
    _player.dispose();
  }

  Future<Uri?> _getLocalArtUri(Uri? remoteUri) async {
    if (remoteUri == null) return null;
    if (remoteUri.isScheme('file')) return remoteUri;
    try {
      final cacheDir = await getTemporaryDirectory();
      final fileName = 'art_${remoteUri.toString().hashCode}.jpg';
      final file = File('${cacheDir.path}/$fileName');
      if (await file.exists()) {
        return file.uri;
      }
      final response = await http.get(remoteUri);
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        return file.uri;
      }
    } catch (e) {
      AppLogger.log('Error caching artwork: $e', name: 'MusicAudioHandler');
    }
    return remoteUri;
  }

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {
    _pendingMediaItemId = mediaItem.id;
    if (mediaItem.artUri != null && !mediaItem.artUri!.isScheme('file')) {
      this.mediaItem.add(mediaItem);
      final localUri = await _getLocalArtUri(mediaItem.artUri);
      if (localUri != null && localUri != mediaItem.artUri) {
        if (this.mediaItem.valueOrNull?.id == mediaItem.id) {
          this.mediaItem.add(mediaItem.copyWith(artUri: localUri));
        }
      }
    } else {
      this.mediaItem.add(mediaItem);
    }
  }

  @override
  Future<dynamic> customAction(
      String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'clearQueue':
        _queue = [];
        _currentIndex = null;
        return true;
      case 'setQueue':
        if (extras != null) {
          final items = (extras['items'] as List).cast<MediaItem>();
          final startIndex = extras['startIndex'] as int? ?? 0;
          _queue = List.from(items);
          _currentIndex = startIndex;
          queue.add(_queue);
        }
        return true;
    }
    return super.customAction(name, extras);
  }
}
