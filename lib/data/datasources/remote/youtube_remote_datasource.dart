import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    hide Playlist, Video;
import '../../models/playlist_model.dart';
import '../../models/video_model.dart';

class YoutubeRemoteDataSource {
  final YoutubeExplode _yt = YoutubeExplode();

  Future<PlaylistModel> getPlaylist(String playlistId) async {
    final ytPlaylist = await _yt.playlists.get(playlistId);
    final playlistVideos = _yt.playlists.getVideos(playlistId);

    final trackModels = <TrackModel>[];
    var index = 0;
    await for (final ytVideo in playlistVideos) {
      trackModels.add(TrackModel(
        id: ytVideo.id.value,
        title: ytVideo.title,
        thumbnailUrl: ytVideo.thumbnails.highResUrl,
        durationSeconds: ytVideo.duration?.inSeconds ?? 0,
        author: ytVideo.author,
        index: index++,
      ));
    }

    return PlaylistModel(
      id: ytPlaylist.id.value,
      title: ytPlaylist.title,
      description: ytPlaylist.description,
      thumbnailUrl: ytPlaylist.thumbnails.highResUrl,
      author: ytPlaylist.author,
      videoCount: trackModels.length,
      tracks: trackModels,
    );
  }

  Future<String> getAudioUrl(String videoId) async {
    final manifest = await _yt.videos.streams.getManifest(videoId);
    final audioStreams = manifest.audioOnly;
    if (audioStreams.isEmpty) {
      throw Exception('No audio streams available for video $videoId');
    }
    var candidates = audioStreams
        .where((s) =>
            s.container == StreamContainer.mp4 ||
            s.container == StreamContainer.webM)
        .toList();
    if (candidates.isEmpty) {
      candidates = audioStreams.toList();
    }
    final bestAudio = candidates
        .reduce((a, b) => a.bitrate.compareTo(b.bitrate) > 0 ? a : b);
    return bestAudio.url.toString();
  }

  void dispose() {
    _yt.close();
  }
}
