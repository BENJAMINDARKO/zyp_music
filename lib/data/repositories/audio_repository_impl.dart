import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../../domain/entities/video.dart';
import '../../domain/repositories/audio_repository.dart';
import '../../service/audio_handler.dart';
import '../datasources/remote/youtube_remote_datasource.dart';

class AudioRepositoryImpl implements AudioRepository {
  final YoutubeRemoteDataSource remoteDataSource;
  final YTMusixAudioHandler _handler;

  AudioRepositoryImpl({
    required this.remoteDataSource,
    required YTMusixAudioHandler handler,
  }) : _handler = handler;

  @override
  Future<String> getAudioUrl(Track track) async {
    return remoteDataSource.getAudioUrl(track.id);
  }

  @override
  Future<void> playTrack(Track track, String audioUrl) async {
    _handler.setMediaItem(MediaItem(
      id: audioUrl,
      title: track.title,
      artist: track.author ?? '',
      artUri: track.thumbnailUrl != null ? Uri.tryParse(track.thumbnailUrl!) : null,
    ));
    await _handler.player.setAudioSource(AudioSource.uri(Uri.parse(audioUrl)));
    await _handler.play();
  }

  @override
  Future<void> play(String url) async {
    await _handler.player.setAudioSource(AudioSource.uri(Uri.parse(url)));
    await _handler.play();
  }

  @override
  Future<void> pause() async {
    await _handler.pause();
  }

  @override
  Future<void> resume() async {
    await _handler.play();
  }

  @override
  Future<void> stop() async {
    await _handler.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _handler.seek(position);
  }

  @override
  Future<Duration> getPosition() async {
    return _handler.player.position;
  }

  @override
  Future<Duration> getDuration() async {
    return _handler.player.duration ?? Duration.zero;
  }

  @override
  Future<bool> isPlaying() async {
    return _handler.player.playing;
  }

  AudioPlayer get player => _handler.player;
  YTMusixAudioHandler get handler => _handler;

  void dispose() {
    _handler.dispose();
  }
}
