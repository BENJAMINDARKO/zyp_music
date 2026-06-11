import 'package:youtube_explode_dart/youtube_explode_dart.dart';
void main() async {
  final yt = YoutubeExplode();
  try {
    // Top 50 Global playlist
    final listId = "PL4fGSI1pP0c2E29ZJkOtzLqZ7n26NidgA"; // Actually let's use a known valid one
    // PLFgquLnL59alCl_2epm10C2SWAZ-xUJb5
    final p = await yt.playlists.get("PLFgquLnL59alCl_2epm10C2SWAZ-xUJb5");
    print(p.title);
    final videos = await yt.playlists.getVideos("PLFgquLnL59alCl_2epm10C2SWAZ-xUJb5").take(2).toList();
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
