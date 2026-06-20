import 'package:dart_ytmusic_api/yt_music.dart';

void main() async {
  final ytMusic = YTMusic();
  await ytMusic.initialize();
  try {
    final a = await ytMusic.getPlaylist('VLPL4fGSI1pccIYy1C-G0Z3oE5J7qXJqf9Qy');
    print('YTMusic playlist tracks: ${a.songs.length}');
  } catch (e) {
    print('YTMusic getPlaylist error: $e');
  }
}
