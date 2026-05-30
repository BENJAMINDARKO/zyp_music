import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class MusicAudioHandler extends BaseAudioHandler {
  final AudioPlayer _player = AudioPlayer();
  final AuthService _authService = AuthService();

  final skipNextRequested = StreamController<void>.broadcast();
  final skipPreviousRequested = StreamController<void>.broadcast();

  final _controls = [
    MediaControl.skipToPrevious,
    MediaControl.play,
    MediaControl.pause,
    MediaControl.skipToNext,
  ];

  final _systemActions = <MediaAction>{
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

  MusicAudioHandler() {
    playbackState.add(_defaultPlaybackState);
    _player.playerStateStream.listen(_onPlayerState);
    _player.processingStateStream.listen(_onProcessingState);
    _player.positionStream.listen((pos) {
      final current = playbackState.valueOrNull ?? _defaultPlaybackState;
      playbackState.add(current.copyWith(
        updatePosition: pos,
        controls: _controls,
        systemActions: _systemActions,
        androidCompactActionIndices: [1, 0, 3],
      ));
    });
    _player.durationStream.listen((dur) {
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

  int? get currentIndex => _currentIndex;
  int get queueLength => _queue.length;

  bool get currentTrackCompleted =>
      !_player.playing && _player.processingState == ProcessingState.completed;

  Future<void> playTrack(String url, MediaItem item) async {
    _currentIndex = _queue.indexWhere((e) => e.id == item.id);
    if (_currentIndex == -1) _currentIndex = null;
    mediaItem.add(item);
    final uri = url.startsWith('http') || url.startsWith('https')
        ? Uri.parse(await _resolveRedirects(url))
        : Uri.file(url);
    await _player.setAudioSource(
      AudioSource.uri(uri, tag: item),
    );
    await _player.play();
  }

  Future<void> setQueue(List<MediaItem> items, {int startIndex = 0}) async {
    _queue = List.from(items);
    _currentIndex = startIndex;
    queue.add(_queue);
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

  Future<String> _resolveRedirects(String url) async {
    final client = http.Client();
    try {
      var current = url;
      for (var i = 0; i < 10; i++) {
        final req = http.Request('GET', Uri.parse(current));
        req.headers.addAll(await _getHeaders());
        req.followRedirects = false;
        final resp = await client.send(req);
        final status = resp.statusCode;
        await resp.stream.drain();
        if (status >= 300 && status < 400) {
          final location = resp.headers['location'];
          if (location == null) break;
          current = Uri.parse(location).isAbsolute
              ? location
              : Uri.parse(current).resolve(location).toString();
        } else {
          return current;
        }
      }
      return current;
    } finally {
      client.close();
    }
  }

  Future<Map<String, String>> _getHeaders() async {
    final cookies = await _authService.getCookies();
    final headers = <String, String>{
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
      'Referer': 'https://www.youtube.com/',
    };
    if (cookies != null && cookies.isNotEmpty) {
      headers['Cookie'] = cookies;
    }
    return headers;
  }

  Future<Map<String, String>> getHeaders() => _getHeaders();

  Future<String> resolveRedirects(String url) => _resolveRedirects(url);

  void dispose() {
    _player.dispose();
  }
}
