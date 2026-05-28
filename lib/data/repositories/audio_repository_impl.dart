import 'package:just_audio/just_audio.dart';
import '../../domain/entities/video.dart';
import '../../domain/repositories/audio_repository.dart';
import '../datasources/remote/youtube_remote_datasource.dart';

class AudioRepositoryImpl implements AudioRepository {
  final YoutubeRemoteDataSource remoteDataSource;
  final AudioPlayer _player = AudioPlayer();

  AudioRepositoryImpl({required this.remoteDataSource});

  @override
  Future<String> getAudioUrl(Track track) async {
    return remoteDataSource.getAudioUrl(track.id);
  }

  @override
  Future<void> play(String url) async {
    await _player.setAudioSource(AudioSource.uri(Uri.parse(url)));
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> resume() async {
    await _player.play();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  @override
  Future<Duration> getPosition() async {
    return _player.position;
  }

  @override
  Future<Duration> getDuration() async {
    return _player.duration ?? Duration.zero;
  }

  @override
  Future<bool> isPlaying() async {
    return _player.playing;
  }

  AudioPlayer get player => _player;

  void dispose() {
    _player.dispose();
  }
}
