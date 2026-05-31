import 'dart:async';
import 'dart:developer' as dev;
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    hide Playlist, Video;
import '../../models/playlist_model.dart';
import '../../models/video_model.dart';
import '../../../service/auth_service.dart';
import 'authenticated_client.dart';

class YoutubeRemoteDataSource {
  static const _timeout = Duration(seconds: 30);

  final AuthService _authService;
  late final YoutubeExplode _yt;

  YoutubeRemoteDataSource({AuthService? authService})
      : _authService = authService ?? AuthService();

  Future<void> init() async {
    final cookies = await _authService.getCookies();
    final inner = AuthenticatedClient(cookies: cookies);
    final ytHttp = YoutubeHttpClient(inner);
    _yt = YoutubeExplode(httpClient: ytHttp);
  }

  Future<PlaylistModel> getPlaylist(String playlistId) async {
    final ytPlaylist = await _yt.playlists.get(playlistId);
    final videos = await _yt.playlists.getVideos(playlistId).toList();

    final tracks = <TrackModel>[];
    for (var i = 0; i < videos.length; i++) {
      final video = videos[i];
      tracks.add(TrackModel(
        id: video.id.value,
        title: video.title,
        author: video.author,
        durationSeconds: video.duration?.inSeconds ?? 0,
        thumbnailUrl: video.thumbnails.mediumResUrl,
        index: i,
      ));
    }

    final thumbnailUrl = tracks.isNotEmpty ? tracks.first.thumbnailUrl : null;

    return PlaylistModel(
      id: playlistId,
      title: ytPlaylist.title,
      author: ytPlaylist.author,
      thumbnailUrl: thumbnailUrl,
      videoCount: tracks.length,
      tracks: tracks,
    );
  }

  Future<TrackModel> getVideo(String videoId) async {
    final video = await _yt.videos.get(videoId);
    return TrackModel(
      id: video.id.value,
      title: video.title,
      author: video.author,
      durationSeconds: video.duration?.inSeconds ?? 0,
      thumbnailUrl: video.thumbnails.mediumResUrl,
      index: 0,
    );
  }

  Future<String> getAudioUrl(String videoId) async {
    var attempt = 0;
    final stopwatch = Stopwatch()..start();
    while (true) {
      try {
        final manifest = await _yt.videos.streams
            .getManifest(videoId)
            .timeout(_timeout);

        final muxed = manifest.muxed;
        if (muxed.isNotEmpty) {
          final best = muxed
              .reduce((a, b) => a.bitrate.compareTo(b.bitrate) < 0 ? a : b);
          return best.url.toString();
        }

        final audioStreams = manifest.audioOnly.toList();
        if (audioStreams.isEmpty) {
          throw Exception('No audio streams available for video $videoId');
        }
        var candidates = audioStreams
            .where((s) =>
                s.container == StreamContainer.mp4 ||
                s.container == StreamContainer.webM)
            .toList();
        if (candidates.isEmpty) {
          candidates = audioStreams;
        }
        final bestAudio = candidates
            .reduce((a, b) => a.bitrate.compareTo(b.bitrate) < 0 ? a : b);
        return bestAudio.url.toString();
      } on TimeoutException {
        attempt++;
        dev.log('Attempt $attempt timed out for video $videoId',
            name: 'YoutubeRemoteDataSource');
        if (attempt >= 3 || stopwatch.elapsed > const Duration(seconds: 45)) {
          rethrow;
        }
        await Future.delayed(Duration(seconds: 2 * attempt));
      } on Exception catch (e) {
        attempt++;
        final msg = e.toString();
        if (attempt >= 3 || stopwatch.elapsed > const Duration(seconds: 45)) {
          dev.log('All $attempt attempts failed for video $videoId: $msg',
              name: 'YoutubeRemoteDataSource');
          rethrow;
        }
        if (msg.contains('requestLimit') || msg.contains('429')) {
          dev.log('Rate limited on attempt $attempt for video $videoId',
              name: 'YoutubeRemoteDataSource');
          await Future.delayed(Duration(seconds: 2 * attempt));
        } else {
          dev.log('Non-retryable error on attempt $attempt for video $videoId: $msg',
              name: 'YoutubeRemoteDataSource');
          rethrow;
        }
      }
    }
  }

  void dispose() {
    _yt.close();
  }
}
