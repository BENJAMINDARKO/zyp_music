import '../entities/video.dart';

abstract class AudioRepository {
  Future<String> getAudioUrl(Track track);
  Future<void> play(String url);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<Duration> getPosition();
  Future<Duration> getDuration();
  Future<bool> isPlaying();
}
