import 'package:zyp_music/data/datasources/local/playlist_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = PlaylistDatabase();
  final playlists = await db.getAllPlaylists();
  print('Playlists: \${playlists.length}');
  for (final p in playlists) {
    print(' - \${p.id} / \${p.title}');
  }
}
