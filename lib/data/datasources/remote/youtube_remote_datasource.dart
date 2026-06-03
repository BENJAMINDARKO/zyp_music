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
    var attempt = 0;
    final stopwatch = Stopwatch()..start();

    while (true) {
      attempt++;
      try {
        final ytPlaylist = await _yt.playlists
            .get(playlistId)
            .timeout(_timeout);

        final title = ytPlaylist.title;
        final author = ytPlaylist.author;

        final videos = await () async {
          try {
            return await _yt.playlists
                .getVideos(playlistId)
                .toList()
                .timeout(_timeout);
          } catch (e) {
            dev.log('Playlist videos fetch failed for $playlistId (attempt $attempt): $e',
                name: 'YoutubeRemoteDataSource');
            return <dynamic>[];
          }
        }();

        if (videos.isEmpty) {
          throw Exception('No videos found for playlist/mix $playlistId');
        }

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
          title: title,
          author: author,
          thumbnailUrl: thumbnailUrl,
          videoCount: tracks.length,
          tracks: tracks,
        );
      } on TimeoutException {
        dev.log('Attempt $attempt timed out for playlist $playlistId',
            name: 'YoutubeRemoteDataSource');
        if (attempt >= 3 || stopwatch.elapsed > const Duration(seconds: 45)) {
          rethrow;
        }
        await Future.delayed(Duration(seconds: 2 * attempt));
      } on Exception catch (e) {
        final msg = e.toString();
        dev.log('Playlist fetch attempt $attempt failed for $playlistId: $msg',
            name: 'YoutubeRemoteDataSource');
        if (attempt >= 3 || stopwatch.elapsed > const Duration(seconds: 45)) {
          rethrow;
        }
        await Future.delayed(Duration(seconds: 2 * attempt));
      }
    }
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

  Future<String> getAudioUrl(String videoId, {String quality = 'medium'}) async {
    var attempt = 0;
    final stopwatch = Stopwatch()..start();
    while (true) {
      try {
        final manifest = await _yt.videos.streams
            .getManifest(videoId)
            .timeout(_timeout);

        final muxed = manifest.muxed;
        if (muxed.isNotEmpty) {
          final best = _selectByQuality(muxed, quality);
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
        final bestAudio = _selectByQuality(candidates, quality);
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

  AudioStreamInfo _selectByQuality(List<AudioStreamInfo> streams, String quality) {
    final sorted = List<AudioStreamInfo>.from(streams)
      ..sort((a, b) => a.bitrate.compareTo(b.bitrate));
    switch (quality) {
      case 'low':
        return sorted.first;
      case 'high':
        return sorted.last;
      case 'medium':
      default:
        return sorted[sorted.length ~/ 2];
    }
  }

  Future<List<TrackModel>> getRelatedVideos(String videoId,
      {int maxResults = 20}) async {
    final video = await _yt.videos.get(videoId);
    final related = await _yt.videos.getRelatedVideos(video);
    final videos = related?.take(maxResults).toList() ?? [];
    final tracks = <TrackModel>[];
    for (var i = 0; i < videos.length; i++) {
      final v = videos[i];
      tracks.add(TrackModel(
        id: v.id.value,
        title: v.title,
        author: v.author,
        durationSeconds: v.duration?.inSeconds ?? 0,
        thumbnailUrl: v.thumbnails.mediumResUrl,
        index: i,
      ));
    }
    return tracks;
  }

  Future<List<TrackModel>> search(String query) async {
    final results = await _yt.search.search(query);
    final tracks = <TrackModel>[];
    for (var i = 0; i < results.length; i++) {
      final video = results[i];
      tracks.add(TrackModel(
        id: video.id.value,
        title: video.title,
        author: video.author,
        durationSeconds: video.duration?.inSeconds ?? 0,
        thumbnailUrl: video.thumbnails.mediumResUrl,
        index: i,
      ));
    }
    return tracks;
  }

  void dispose() {
    _yt.close();
  }
}
