import 'package:youtube_explode_dart/youtube_explode_dart.dart';
void main() async {
  final yt = YoutubeExplode();
  final v = await yt.videos.get("dQw4w9WgXcQ");
  print(v.thumbnails.mediumResUrl);
  yt.close();
}
