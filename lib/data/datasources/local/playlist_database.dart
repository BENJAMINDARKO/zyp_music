import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../models/playlist_model.dart';
import '../../models/video_model.dart';

class PlaylistDatabase {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'ytmusix.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: _createTables,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE playlists (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        thumbnailUrl TEXT,
        author TEXT,
        videoCount INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE tracks (
        id TEXT NOT NULL,
        playlistId TEXT NOT NULL,
        title TEXT NOT NULL,
        thumbnailUrl TEXT,
        durationSeconds INTEGER DEFAULT 0,
        author TEXT,
        idx INTEGER DEFAULT 0,
        PRIMARY KEY (id, playlistId),
        FOREIGN KEY (playlistId) REFERENCES playlists(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE downloaded_tracks (
        id TEXT PRIMARY KEY,
        playlistId TEXT NOT NULL,
        title TEXT NOT NULL,
        thumbnailUrl TEXT,
        durationSeconds INTEGER DEFAULT 0,
        author TEXT,
        filePath TEXT NOT NULL,
        downloadedAt INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS downloaded_tracks (
          id TEXT PRIMARY KEY,
          playlistId TEXT NOT NULL,
          title TEXT NOT NULL,
          thumbnailUrl TEXT,
          durationSeconds INTEGER DEFAULT 0,
          author TEXT,
          filePath TEXT NOT NULL,
          downloadedAt INTEGER NOT NULL
        )
      ''');
    }
  }

  Future<void> insertPlaylist(PlaylistModel playlist) async {
    final db = await database;
    await db.insert('playlists', playlist.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deletePlaylist(String id) async {
    final db = await database;
    await db.delete('tracks', where: 'playlistId = ?', whereArgs: [id]);
    await db.delete('playlists', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<PlaylistModel>> getAllPlaylists() async {
    final db = await database;
    final maps = await db.query('playlists', orderBy: 'title ASC');
    return maps.map((m) => PlaylistModel.fromMap(m)).toList();
  }

  Future<void> insertTrack(String playlistId, TrackModel track) async {
    final db = await database;
    await db.insert('tracks', {
      ...track.toMap(),
      'playlistId': playlistId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertTracks(
      String playlistId, List<TrackModel> tracks) async {
    final db = await database;
    final batch = db.batch();
    for (final track in tracks) {
      batch.insert('tracks', {
        ...track.toMap(),
        'playlistId': playlistId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<TrackModel>> getTracks(String playlistId) async {
    final db = await database;
    final maps = await db.query('tracks',
        where: 'playlistId = ?',
        whereArgs: [playlistId],
        orderBy: 'idx ASC');
    return maps.map((m) => TrackModel.fromMap(m)).toList();
  }

  Future<void> markTrackDownloaded(
      String trackId, String playlistId, String filePath,
      {String title = '', String? thumbnailUrl, int durationSeconds = 0, String? author}) async {
    final db = await database;
    await db.insert('downloaded_tracks', {
      'id': trackId,
      'playlistId': playlistId,
      'title': title,
      'thumbnailUrl': thumbnailUrl,
      'durationSeconds': durationSeconds,
      'author': author,
      'filePath': filePath,
      'downloadedAt': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> isTrackDownloaded(String trackId) async {
    final db = await database;
    final result = await db.query('downloaded_tracks',
        where: 'id = ?', whereArgs: [trackId], limit: 1);
    return result.isNotEmpty;
  }

  Future<String?> getDownloadedFilePath(String trackId) async {
    final db = await database;
    final result = await db.query('downloaded_tracks',
        where: 'id = ?', whereArgs: [trackId], limit: 1);
    if (result.isEmpty) return null;
    return result.first['filePath'] as String?;
  }

  Future<List<Map<String, dynamic>>> getDownloadedTracks(String playlistId) async {
    final db = await database;
    return db.query('downloaded_tracks',
        where: 'playlistId = ?', whereArgs: [playlistId]);
  }

  Future<void> removeDownloadedTrack(String trackId) async {
    final db = await database;
    await db.delete('downloaded_tracks', where: 'id = ?', whereArgs: [trackId]);
  }

  Future<List<String>> getDownloadedFilePaths(String playlistId) async {
    final db = await database;
    final result = await db.query('downloaded_tracks',
        columns: ['filePath'],
        where: 'playlistId = ?', whereArgs: [playlistId]);
    return result.map((r) => r['filePath'] as String).toList();
  }

  Future<void> removeDownloadedPlaylist(String playlistId) async {
    final db = await database;
    await db.delete('downloaded_tracks',
        where: 'playlistId = ?', whereArgs: [playlistId]);
  }

  Future<Set<String>> getAllDownloadedTrackIds() async {
    final db = await database;
    final result = await db.query('downloaded_tracks', columns: ['id']);
    return result.map((r) => r['id'] as String).toSet();
  }

  Future<Set<String>> getFullyDownloadedPlaylistIds() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT p.id FROM playlists p
      WHERE p.videoCount > 0
        AND p.videoCount <= (
          SELECT COUNT(*) FROM downloaded_tracks d
          WHERE d.playlistId = p.id
        )
    ''');
    return result.map((r) => r['id'] as String).toSet();
  }
}
