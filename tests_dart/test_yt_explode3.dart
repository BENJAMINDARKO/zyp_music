import 'package:youtube_explode_dart/youtube_explode_dart.dart';
void main() async {
  final yt = YoutubeExplode();
  try {
    final p = await yt.playlists.get("PLWwAypSqD3pUXq1zZgI0U6kE_X6f1wI0Z");
    print(p.title);
    final videos = await yt.playlists.getVideos("PLWwAypSqD3pUXq1zZgI0U6kE_X6f1wI0Z").take(2).toList();
    for (var v in videos) {
      print(v.title);
      print(v.author);
    }
  } catch (e) {
    print(e);
  } finally {
    yt.close();
  }
}
