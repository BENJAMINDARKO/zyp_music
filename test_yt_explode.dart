import 'package:youtube_explode_dart/youtube_explode_dart.dart';
void main() async {
  final yt = YoutubeExplode();
  try {
    final p = await yt.playlists.get("PL4fGSI1pP0c2E29ZJkOtzLqZ7n26NidgA");
    print(p.title);
    final videos = await yt.playlists.getVideos("PL4fGSI1pP0c2E29ZJkOtzLqZ7n26NidgA").take(50).toList();
    print(videos.length);
  } catch (e) {
    print(e);
  } finally {
    yt.close();
  }
}
