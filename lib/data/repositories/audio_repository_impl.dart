import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../../domain/entities/video.dart';
import '../../domain/repositories/audio_repository.dart';
import '../datasources/remote/youtube_remote_datasource.dart';
import '../datasources/local/playlist_database.dart';
import '../../service/audio_handler.dart';

class AudioRepositoryImpl implements AudioRepository {
  final YoutubeRemoteDataSource remoteDataSource;
  final MusicAudioHandler _handler;
  final PlaylistDatabase _database;

  AudioRepositoryImpl({
    required this.remoteDataSource,
    required this._handler,
    required this._database,
  });

  @override
  Future<String> getAudioUrl(Track track) async {
    final localPath = await _database.getDownloadedFilePath(track.id);
    if (localPath != null && File(localPath).existsSync()) {
      return localPath;
    }
    return remoteDataSource.getAudioUrl(track.id);
  }

  @override
  Future<void> playTrack(Track track, String audioUrl) async {
    final item = MediaItem(
      id: track.id,
      title: track.title,
      artist: track.author ?? '',
      artUri: track.thumbnailUrl != null
          ? Uri.tryParse(track.thumbnailUrl!)
          : null,
      duration: track.duration,
    );

    final isLocal = audioUrl.startsWith('/') ||
        audioUrl.startsWith('file://') ||
        !audioUrl.startsWith('http');
    final playUrl = isLocal
        ? audioUrl
        : await _handler.resolveRedirects(audioUrl);

    final queue = _handler.queue.value;
    if (queue.isNotEmpty && queue.any((e) => e.id == track.id)) {
      _handler.mediaItem.add(item);
      await _handler.playTrack(playUrl, item);
    } else {
      final newQueue = List<MediaItem>.from(queue);
      newQueue.add(item);
      _handler.queue.add(newQueue);
      await _handler.playTrack(playUrl, item);
    }
  }

  @override
  Future<void> play(String url) async {
    final resolved = await _handler.resolveRedirects(url);
    await _handler.playTrack(resolved, const MediaItem(id: '', title: ''));
  }

  @override
  Future<void> pause() => _handler.pause();

  @override
  Future<void> resume() => _handler.play();

  @override
  Future<void> stop() => _handler.stop();

  @override
  Future<void> seek(Duration position) => _handler.seek(position);

  @override
  Future<Duration> getPosition() async => _handler.position;

  @override
  Future<Duration> getDuration() async => _handler.duration;

  @override
  Stream<Duration> get positionStream => _handler.positionStream;

  @override
  Stream<Duration> get durationStream => _handler.durationStream;

  @override
  Future<bool> isPlaying() async => _handler.isPlaying;

  @override
  Stream<ProcessingState> get processingStateStream =>
      _handler.processingStateStream;

  @override
  bool get currentTrackCompleted => _handler.currentTrackCompleted;

  @override
  Stream<void> get onSkipNextRequested => _handler.skipNextRequested.stream;

  @override
  Stream<void> get onSkipPreviousRequested => _handler.skipPreviousRequested.stream;
}
