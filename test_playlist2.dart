import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  final yt = YoutubeExplode();
  try {
    final v = await yt.playlists.getVideos('VLOLAK5uy_I13RAEFxk5KvJs_E8JIqcyXaQ9FDIHiwY').toList();
    print('YtExplode videos (with VL): ${v.length}');
  } catch (e) {
    print('YtExplode error (with VL): $e');
  }
  yt.close();
}
