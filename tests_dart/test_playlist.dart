import 'package:dart_ytmusic_api/yt_music.dart';

void main() async {
  final ytMusic = YTMusic();
  await ytMusic.initialize();
  try {
    final p = await ytMusic.getPlaylist('VLOLAK5uy_I13RAEFxk5KvJs_E8JIqcyXaQ9FDIHiwY');
    print('YTMusic playlist: ${p.name}, videos: ${p.videoCount}');
  } catch (e) {
    print('YTMusic getPlaylist error: $e');
  }
}
