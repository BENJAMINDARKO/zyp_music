import 'package:dart_ytmusic_api/yt_music.dart';
import 'package:dart_ytmusic_api/types.dart';

void main() async {
  final ytmusic = YTMusic();
  await ytmusic.initialize();

  try {
    print('--- SEARCH GENERIC ---');
    final results = await ytmusic.search('Kendrick Lamar Not Like Us');
    for (var r in results.take(3)) {
      print('Type: ${r.type}');
      if (r is SongDetailedSearchResult) {
        final s = r.songDetailed;
        print('Song: ${s.name}, ID: ${s.videoId}');
      } else if (r is VideoDetailedSearchResult) {
        final v = r.videoDetailed;
        print('Video: ${v.name}, ID: ${v.videoId}');
      }
    }
  } catch (e) {
    print('Error: $e');
  }
}
