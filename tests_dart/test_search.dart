import 'package:dart_ytmusic_api/yt_music.dart';

void main() async {
  final ytMusic = YTMusic();
  await ytMusic.initialize();
  final res = await ytMusic.searchAlbums('Beta Radio');
  for (var a in res) {
    print('Album: ${a.name}, ID: ${a.albumId}');
  }
}
