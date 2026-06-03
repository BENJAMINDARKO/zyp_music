import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// Searches YouTube for a track and returns a list of results.
  Future<List<Video>> searchTracks(String query) async {
    final searchResults = await _yt.search.search(query);
    // Filter to videos that are likely music tracks (short duration, etc.) if needed.
    return searchResults.toList();
  }

  /// Gets the highest quality audio stream URL for a given YouTube video ID.
  Future<String?> getStreamUrl(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioStreams = manifest.audioOnly;
      
      if (audioStreams.isEmpty) return null;
      
      // Get the highest bitrate audio stream
      final highestAudio = audioStreams.withHighestBitrate();
      return highestAudio.url.toString();
    } catch (e) {
      print('Error getting YouTube stream: $e');
      return null;
    }
  }

  /// Fetches video metadata
  Future<Video?> getVideo(String videoId) async {
    try {
      return await _yt.videos.get(videoId);
    } catch (e) {
      print('Error getting video: $e');
      return null;
    }
  }

  void dispose() {
    _yt.close();
  }
}
