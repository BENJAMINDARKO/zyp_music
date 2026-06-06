import 'dart:async';
import 'package:zyp_music/core/utils/app_logger.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import '../core/utils/network_utils.dart';
import 'auth_service.dart';

class MusicAudioHandler extends BaseAudioHandler {
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
    // Capture the playback position / playing flag from the
    // old player so we can re-emit a state that is consistent
    // with the new player's state. The new player is the
    // source of truth for "is playing" — the engine has
    // already configured its speed + volume.
    final wasPosition = _player.position;
    final wasPlaying = _player.playing;
    await _playerStateSub?.cancel();
    await _processingSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _currentIndexSub?.cancel();
    final oldPlayer = _player;
    _player = newPlayer;
    _playerStateSub = _player.playerStateStream.listen(_onPlayerState);
    _processingSub = _player.processingStateStream.listen(_onProcessingState);
    _positionSub = _player.positionStream.listen((pos) {
      final current = playbackState.valueOrNull ?? _defaultPlaybackState;
      playbackState.add(current.copyWith(
        updatePosition: pos,
        controls: _controls,
        systemActions: _systemActions,
        androidCompactActionIndices: [1, 0, 3],
      ));
    });
    _durationSub = _player.durationStream.listen((dur) {
      if (dur != null) {
        final item = mediaItem.value;
        if (item != null) {
          mediaItem.add(item.copyWith(duration: dur));
        }
      }
    });
    _currentIndexSub = _player.currentIndexStream.listen((index) {
      if (index != null && index >= 0) {
        final sequence = _player.sequence;
        if (sequence != null && index < sequence.length) {
          final source = sequence[index];
          if (source.tag is MediaItem) {
            final item = source.tag as MediaItem;
            if (mediaItem.valueOrNull?.id != item.id) {
              mediaItem.add(item);
            }
            _currentIndex = index;
          }
        }
      }
    });
    // Re-emit a playback state derived from the new player
    // so any UI listeners that just received the last
    // old-player position flush don't latch onto a stale
    // "playing=false" state.
    playbackState.add((playbackState.valueOrNull ?? _defaultPlaybackState)
        .copyWith(
      updatePosition: wasPosition,
      playing: wasPlaying,
      controls: _controls,
      systemActions: _systemActions,
      androidCompactActionIndices: [1, 0, 3],
    ));

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
          mediaItem.add(source.tag as MediaItem);
          AppLogger.log(
            '[MediaSessionSync] Re-anchored MediaItem to active player: '
            '${(source.tag as MediaItem).id}',
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

  MusicAudioHandler() {
    playbackState.add(_defaultPlaybackState);
    _playerStateSub = _player.playerStateStream.listen(_onPlayerState);
    _processingSub = _player.processingStateStream.listen(_onProcessingState);
    _positionSub = _player.positionStream.listen((pos) {
      final current = playbackState.valueOrNull ?? _defaultPlaybackState;
      playbackState.add(current.copyWith(
        updatePosition: pos,
        controls: _controls,
        systemActions: _systemActions,
        androidCompactActionIndices: [1, 0, 3],
      ));
    });
    _durationSub = _player.durationStream.listen((dur) {
      if (dur != null) {
        final item = mediaItem.value;
        if (item != null) {
          mediaItem.add(item.copyWith(duration: dur));
        }
      }
    });
    _currentIndexSub = _player.currentIndexStream.listen((index) {
      if (index != null && index >= 0) {
        final sequence = _player.sequence;
        if (sequence != null && index < sequence.length) {
          final source = sequence[index];
          if (source.tag is MediaItem) {
            final item = source.tag as MediaItem;
            if (mediaItem.valueOrNull?.id != item.id) {
              mediaItem.add(item);
            }
            _currentIndex = index;
          }
        }
      }
    });
  }

  void _onPlayerState(PlayerState state) {
    final current = playbackState.valueOrNull ?? _defaultPlaybackState;
    playbackState.add(current.copyWith(
      playing: state.playing,
      processingState: _convertState(state.processingState),
      controls: _controls,
      systemActions: _systemActions,
      androidCompactActionIndices: [1, 0, 3],
    ));
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

  Duration get duration => _player.duration ?? Duration.zero;

  Stream<ProcessingState> get processingStateStream =>
      _player.processingStateStream;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;

  Stream<Duration> get durationStream =>
      _player.durationStream.where((d) => d != null).cast<Duration>();

  int? get currentIndex => _currentIndex;
  int get queueLength => _queue.length;

  bool get currentTrackCompleted =>
      !_player.playing && _player.processingState == ProcessingState.completed;

  Future<void> playTrack(String url, MediaItem item) async {
    // 1. Guard against empty paths matching log crash states
    if (url.trim().isEmpty || url.endsWith('/audio_cache/.mp3')) {
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
      ));
      throw ArgumentError("Aborting playback execution: Invalid or incomplete stream URL/Cache path.");
    }

    try {
      _currentIndex = _queue.indexWhere((e) => e.id == item.id);
      if (_currentIndex == -1) _currentIndex = null;
      mediaItem.add(item);

      final headers = await _getHeaders();

      final Uri uri;
      try {
        if (url.startsWith('file://') || !url.startsWith('http')) {
          uri = url.startsWith('file://') ? Uri.parse(url) : Uri.file(url);
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
      
      // 2. Pass headers down to AudioSource config to keep connections alive on YouTube paths
      if (uri.isScheme('HTTP') || uri.isScheme('HTTPS')) {
        final finalHeaders = uri.host.contains('googlevideo.com') ? null : headers;
        await _player.setAudioSource(
          AudioSource.uri(
            uri,
            headers: finalHeaders,
            tag: item,
          ),
        );
      } else {
        await _player.setAudioSource(AudioSource.uri(uri, tag: item));
      }
      
      unawaited(_player.play());
    } catch (e) {
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
      ));
      AppLogger.log('Error in MusicAudioHandler.playTrack: $e', name: 'MusicAudioHandler');
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
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    playbackState.add(_defaultPlaybackState.copyWith(
      controls: _controls,
      systemActions: _systemActions,
      androidCompactActionIndices: [1, 0, 3],
    ));
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
    _player.dispose();
  }
}
