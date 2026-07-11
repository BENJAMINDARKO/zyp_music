import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  final yt = YoutubeExplode();
  final list = await yt.playlists.getVideos('PLFgquLnL59alCl_2zTGL111x9c1t58R').take(1).toList();
  print(list.first.thumbnails.highResUrl);
  print(list.first.thumbnails.maxResUrl);
  yt.close();
}
