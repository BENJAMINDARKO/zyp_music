import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import '../../domain/entities/video.dart';
import '../../domain/repositories/audio_repository.dart';
import '../datasources/remote/youtube_remote_datasource.dart';
import '../../service/auth_service.dart';

class AudioRepositoryImpl implements AudioRepository {
  final YoutubeRemoteDataSource remoteDataSource;
  final AuthService _authService;
  final AudioPlayer _player = AudioPlayer();
  String? _tempFilePath;

  AudioRepositoryImpl({
    required this.remoteDataSource,
    AuthService? authService,
  }) : _authService = authService ?? AuthService();

  @override
  Future<String> getAudioUrl(Track track) async {
    return remoteDataSource.getAudioUrl(track.id);
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

  @override
  Future<void> playTrack(Track track, String audioUrl) async {
    final headers = await _getHeaders();

    final client = http.Client();
    final req = http.Request('GET', Uri.parse(audioUrl));
    req.headers.addAll(headers);
    final resp = await client.send(req);

    final dir = Directory.systemTemp;
    _tempFilePath = '${dir.path}/yt_${track.id}.mp4';
    final file = File(_tempFilePath!);
    final sink = file.openWrite();
    await resp.stream.pipe(sink);
    await sink.flush();
    await sink.close();
    client.close();

    await _player.setAudioSource(AudioSource.file(_tempFilePath!));
    await _player.play();
  }

  @override
  Future<void> play(String url) async {
    final headers = await _getHeaders();
    await _player.setAudioSource(
      AudioSource.uri(Uri.parse(url), headers: headers),
    );
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
    _cleanup();
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

  @override
  Stream<ProcessingState> get processingStateStream =>
      _player.processingStateStream;

  @override
  bool get currentTrackCompleted =>
      _player.processingState == ProcessingState.completed &&
      _player.playing == false;

  void _cleanup() {
    if (_tempFilePath != null) {
      try {
        File(_tempFilePath!).delete();
      } catch (_) {}
      _tempFilePath = null;
    }
  }

  void dispose() {
    _player.dispose();
    _cleanup();
  }
}
