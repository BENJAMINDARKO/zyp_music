import 'package:dart_ytmusic_api/yt_music.dart';

void main() async {
  final ytMusic = YTMusic();
  await ytMusic.initialize();
  final results = await ytMusic.searchSongs("Master KG Uthando");
  if (results.isNotEmpty) {
    final song = results.first;
    print("Song name: ${song.name}");
    print("Thumbnails:");
    for (var thumb in song.thumbnails) {
      print("- ${thumb.url}");
    }
  }
}
