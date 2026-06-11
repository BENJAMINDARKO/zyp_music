import 'package:zyp_music/data/datasources/local/playlist_database.dart';
import 'package:zyp_music/data/models/playlist_model.dart';
import 'package:zyp_music/data/models/track_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = PlaylistDatabase();
  
  final id1 = 'local_${DateTime.now().millisecondsSinceEpoch}';
  await Future.delayed(Duration(seconds: 1));
  final id2 = 'local_${DateTime.now().millisecondsSinceEpoch}';

  await db.insertPlaylist(PlaylistModel(id: id1, title: 'Playlist A', createdAt: 0));
  await db.insertPlaylist(PlaylistModel(id: id2, title: 'Playlist B', createdAt: 0));

  final lists = await db.getAllPlaylists();
  for (final p in lists) {
    print('ID: ${p.id}, Title: ${p.title}');
  }
}
