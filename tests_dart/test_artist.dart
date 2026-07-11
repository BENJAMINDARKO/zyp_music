import 'package:dart_ytmusic_api/yt_music.dart';

void main() async {
  final ytMusic = YTMusic();
  await ytMusic.initialize();
  try {
    // get artist Beta Radio
    final a = await ytMusic.getArtist('UCfN7fWDE8JpB505q5c8tWkw');
    for (var al in a.topAlbums) {
      print('Album: ${al.name}, playlistId: ${al.playlistId}, albumId/browseId (using runtimeType)? ${al.toJson()}');
      break;
    }
  } catch (e) {
    print('YTMusic getArtist error: $e');
  }
}
