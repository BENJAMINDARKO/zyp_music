import 'package:dart_ytmusic_api/yt_music.dart';

void main() async {
  final ytMusic = YTMusic();
  await ytMusic.initialize();
  try {
    final a = await ytMusic.getAlbum('MPREb_QCbISUdNB3I');
    print('YTMusic album: ${a.name}, tracks: ${a.songs.length}');
  } catch (e) {
    print('YTMusic getAlbum error: $e');
  }
}
