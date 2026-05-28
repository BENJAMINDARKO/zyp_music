import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class YTMusixAudioHandler extends BaseAudioHandler {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlaybackEvent>? _eventSubscription;

  YTMusixAudioHandler() {
    _eventSubscription = _player.playbackEventStream.listen(_onPlaybackEvent);
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
    await _player.setAudioSource(AudioSource.uri(Uri.parse('')));
  }

  @override
  Future<void> skipToNext() async {}

  @override
  Future<void> skipToPrevious() async {}

  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }

  void setMediaItem(MediaItem item) {
    mediaItem.add(item);
  }

  void playUri(String uri) async {
    await _player.setAudioSource(AudioSource.uri(Uri.parse(uri)));
    await _player.play();
  }

  void playAudioSource(AudioSource source) async {
    await _player.setAudioSource(source);
    await _player.play();
  }

  AudioPlayer get player => _player;

  Future<Duration> get duration async =>
      _player.duration ?? Duration.zero;

  void _onPlaybackEvent(PlaybackEvent event) {
    playbackState.add(playbackState.value.copyWith(
      playing: _player.playing,
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: {
        MediaAction.seek,
      },
      processingState: _processingState(_player.processingState),
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _player.currentIndex,
    ));
  }

  static AudioProcessingState _processingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
      case ProcessingState.buffering:
        return AudioProcessingState.loading;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  void dispose() {
    _eventSubscription?.cancel();
    _player.dispose();
  }
}
