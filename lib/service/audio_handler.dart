import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import '../core/utils/network_utils.dart';
import 'auth_service.dart';

class MusicAudioHandler extends BaseAudioHandler {
  final AudioPlayer _player = AudioPlayer();
  final AuthService _authService = AuthService();

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

  MusicAudioHandler() {
    playbackState.add(_defaultPlaybackState);
    _playerStateSub = _player.playerStateStream.listen(_onPlayerState);
    _processingSub = _player.processingStateStream.listen(_onProcessingState);
    _positionSub = _player.positionStream.listen((pos) {
      final current = playbackState.valueOrNull ?? _defaultPlaybackState;
      playbackState.add(
        current.copyWith(
          updatePosition: pos,
          controls: _controls,
          systemActions: _systemActions,
          androidCompactActionIndices: [1, 0, 3],
        ),
      );
    });
    _durationSub = _player.durationStream.listen((dur) {
      if (dur != null) {
        final item = mediaItem.value;
        if (item != null) {
          mediaItem.add(item.copyWith(duration: dur));
        }
      }
    });
  }

  void _onPlayerState(PlayerState state) {
    final current = playbackState.valueOrNull ?? _defaultPlaybackState;
    playbackState.add(
      current.copyWith(
        playing: state.playing,
        processingState: _convertState(state.processingState),
        controls: _controls,
        systemActions: _systemActions,
        androidCompactActionIndices: [1, 0, 3],
      ),
    );
  }

  void _onProcessingState(ProcessingState state) {
    if (state == ProcessingState.completed &&
        _queue.isEmpty &&
        _currentIndex == null) {
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
    _currentIndex = _queue.indexWhere((e) => e.id == item.id);
    if (_currentIndex == -1) _currentIndex = null;
    mediaItem.add(item);
    final client = http.Client();
    final Uri uri;
    try {
      uri = url.startsWith('http') || url.startsWith('https')
          ? Uri.parse(
              await NetworkUtils.resolveRedirects(
                client,
                url,
                headers: await _getHeaders(),
              ),
            )
          : Uri.file(url);
    } finally {
      client.close();
    }
    await _player.stop();
    await _player.setAudioSource(AudioSource.uri(uri, tag: item));
    unawaited(_player.play());
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
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    playbackState.add(
      _defaultPlaybackState.copyWith(
        controls: _controls,
        systemActions: _systemActions,
        androidCompactActionIndices: [1, 0, 3],
      ),
    );
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
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
      'Referer': 'https://www.youtube.com/',
    };
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
    _player.dispose();
  }
}
