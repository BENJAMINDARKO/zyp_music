import 'package:audio_session/audio_session.dart';
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
  bool _androidConfigured = false;

  AudioRepositoryImpl({
    required this.remoteDataSource,
    AuthService? authService,
  }) : _authService = authService ?? AuthService();

  Future<void> _setupAndroid() async {
    if (_androidConfigured) return;
    _androidConfigured = true;

    try {
      await _player.setAndroidAudioAttributes(
        const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
      );
    } catch (_) {}
  }

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

  @override
  Future<void> playTrack(Track track, String audioUrl) async {
    await _setupAndroid();
    final resolvedUrl = await _resolveRedirects(audioUrl);
    await _player.setAudioSource(
      AudioSource.uri(Uri.parse(resolvedUrl)),
    );
    await _player.play();
  }

  @override
  Future<void> play(String url) async {
    final resolvedUrl = await _resolveRedirects(url);
    await _player.setAudioSource(
      AudioSource.uri(Uri.parse(resolvedUrl)),
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

  void dispose() {
    _player.dispose();
  }
}
