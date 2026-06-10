import 'dart:async';
import 'package:just_audio/just_audio.dart';
import '../entities/video.dart';

abstract class AudioRepository {
  Future<String> getAudioUrl(Track track, {String quality = 'adaptive'});
  Future<void> playTrack(Track track, String audioUrl);
  Future<void> play(String url);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<Duration> getPosition();
  Future<Duration> getDuration();
  Future<bool> isPlaying();
  Stream<bool> get playingStream;
  Stream<ProcessingState> get processingStateStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get bufferedPositionStream;
  Stream<Duration> get durationStream;
  bool get currentTrackCompleted;
  Stream<void> get onSkipNextRequested;
  Stream<void> get onSkipPreviousRequested;

  Future<String?> getLyrics(Track track);
  Future<String?> getLyricsOffline(Track track);
  Future<String?> refreshLyrics(Track track);
  Future<List<Track>> getUpNexts(Track track);
  Future<void> preloadTrack(Track track);
  Future<void> preloadTrackLyrics(Track track);
  Future<AudioSource> buildAudioSource(Track track);
  Future<void> setPlaybackSpeed(double speed);
}
