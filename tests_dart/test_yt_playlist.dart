import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
void main() async {
  final yt = YTMusic();
  try {
    final p = await yt.getPlaylist("PL4fGSI1pP0c2E29ZJkOtzLqZ7n26NidgA");
    print(p.name);
    print(p.songs.length);
  } catch (e) {
    print(e);
  }
}
