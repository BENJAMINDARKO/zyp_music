import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:zyp_music/service/auth_service.dart';
import 'package:zyp_music/data/datasources/remote/authenticated_client.dart';
import 'package:zyp_music/data/datasources/remote/youtube_audio_extractor.dart'; // Just for dummy wrapper if needed

void main() async {
  final authService = AuthService();
  final cookies = await authService.getCookies();
  final inner = AuthenticatedClient(cookies: cookies);
  final yt = YoutubeExplode(httpClient: inner); // Actually YoutubeExplode needs YoutubeHttpClient
  
  try {
    final v = await yt.playlists.getVideos('OLAK5uy_I13RAEFxk5KvJs_E8JIqcyXaQ9FDIHiwY').toList();
    print('YtExplode with auth videos: ${v.length}');
  } catch (e) {
    print('YtExplode error: $e');
  }
  yt.close();
}
