import 'package:flutter_test/flutter_test.dart';
import 'package:zyp_music/data/datasources/remote/youtube_remote_datasource.dart';
import 'package:zyp_music/service/auth_service.dart';

void main() {
  test('fetch charts', () async {
    final authService = AuthService();
    final ds = YoutubeRemoteDataSource(authService: authService);
    await ds.init();
    
    final r1 = await ds.searchPlaylists('Top Songs Ghana');
    if (r1.isNotEmpty) {
      print('Ghana: ${r1.first.id}, Title: ${r1.first.title}');
      final p1 = await ds.getPlaylist(r1.first.id);
      print('Ghana Playlist Tracks: ${p1.tracks.length}');
    }
    
    final r2 = await ds.searchPlaylists('Top Songs Global');
    if (r2.isNotEmpty) {
      print('Global: ${r2.first.id}, Title: ${r2.first.title}');
      final p2 = await ds.getPlaylist(r2.first.id);
      print('Global Playlist Tracks: ${p2.tracks.length}');
    }
  });
}
