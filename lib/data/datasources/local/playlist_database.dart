import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../models/playlist_model.dart';
import '../../models/video_model.dart';

class PlaylistDatabase {
  static Database? _database;
  static final Completer<void> _initCompleter = Completer<void>();
  static bool _initStarted = false;

  Future<Database> get database async {
    if (_database != null) return _database!;
    if (!_initStarted) {
      _initStarted = true;
      _database = await _initDatabase();
      _initCompleter.complete();
    } else {
      await _initCompleter.future;
    }
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'ytmusix.db');
    return openDatabase(
      path,
      version: 8,
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
        videoCount INTEGER DEFAULT 0,
        createdAt INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000)
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
        source TEXT DEFAULT 'youtube',
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
        downloadedAt INTEGER NOT NULL,
        source TEXT DEFAULT 'youtube'
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_downloaded_tracks_playlistId
      ON downloaded_tracks(playlistId)
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS favorite_tracks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        thumbnailUrl TEXT,
        durationSeconds INTEGER DEFAULT 0,
        author TEXT,
        favoritedAt INTEGER NOT NULL,
        source TEXT DEFAULT 'youtube'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS favorite_albums (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        thumbnailUrl TEXT,
        artistName TEXT,
        year TEXT,
        favoritedAt INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS favorite_artists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        thumbnailUrl TEXT,
        favoritedAt INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE TABLE IF NOT EXISTS download_queue ('
      'id TEXT PRIMARY KEY, '
      'trackId TEXT NOT NULL, '
      'provider TEXT NOT NULL, '
      'quality TEXT NOT NULL, '
      'format TEXT NOT NULL, '
      'destinationPath TEXT NOT NULL, '
      'status TEXT NOT NULL, '
      'progress REAL DEFAULT 0.0, '
      'error TEXT, '
      'createdAt INTEGER NOT NULL, '
      'completedAt INTEGER'
      ')'
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS cache_manifest ('
      'trackId TEXT PRIMARY KEY, '
      'title TEXT NOT NULL, '
      'artist TEXT NOT NULL, '
      'provider TEXT NOT NULL, '
      'format TEXT NOT NULL, '
      'filePath TEXT NOT NULL, '
      'sizeBytes INTEGER NOT NULL, '
      'cachedAt INTEGER NOT NULL, '
      'lastAccessed INTEGER NOT NULL'
      ')'
    );
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
          downloadedAt INTEGER NOT NULL,
          source TEXT DEFAULT 'youtube'
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_downloaded_tracks_playlistId
        ON downloaded_tracks(playlistId)
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('''
        ALTER TABLE playlists ADD COLUMN createdAt INTEGER NOT NULL DEFAULT 0
      ''');
      await db.execute('''
        UPDATE playlists SET createdAt = (strftime('%s','now') * 1000)
      ''');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS favorite_tracks (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          thumbnailUrl TEXT,
          durationSeconds INTEGER DEFAULT 0,
          author TEXT,
          favoritedAt INTEGER NOT NULL,
          source TEXT DEFAULT 'youtube'
        )
      ''');
    }
    if (oldVersion < 6) {
      // Add source column to tracks if it doesn't exist.
      await db.execute('''
        ALTER TABLE tracks ADD COLUMN source TEXT DEFAULT 'youtube'
      ''');
      // For downloaded_tracks and favorite_tracks, they might have been created above with the source column,
      // but SQLite ALTER TABLE IF NOT EXISTS or catching exception is tricky. We'll just try catching it.
      try {
        await db.execute('''
          ALTER TABLE downloaded_tracks ADD COLUMN source TEXT DEFAULT 'youtube'
        ''');
      } catch (_) {}
      try {
        await db.execute('''
          ALTER TABLE favorite_tracks ADD COLUMN source TEXT DEFAULT 'youtube'
        ''');
      } catch (_) {}
    }
    if (oldVersion < 7) {
      await db.execute(
        'CREATE TABLE IF NOT EXISTS favorite_albums ('
        'id TEXT PRIMARY KEY, '
        'title TEXT NOT NULL, '
        'thumbnailUrl TEXT, '
        'artistName TEXT, '
        'year TEXT, '
        'favoritedAt INTEGER NOT NULL'
        ')'
      );
      await db.execute(
        'CREATE TABLE IF NOT EXISTS favorite_artists ('
        'id TEXT PRIMARY KEY, '
        'name TEXT NOT NULL, '
        'thumbnailUrl TEXT, '
        'favoritedAt INTEGER NOT NULL'
        ')'
      );
    }
    if (oldVersion < 8) {
      await db.execute(
        'CREATE TABLE IF NOT EXISTS download_queue ('
        'id TEXT PRIMARY KEY, '
        'trackId TEXT NOT NULL, '
        'provider TEXT NOT NULL, '
        'quality TEXT NOT NULL, '
        'format TEXT NOT NULL, '
        'destinationPath TEXT NOT NULL, '
        'status TEXT NOT NULL, '
        'progress REAL DEFAULT 0.0, '
        'error TEXT, '
        'createdAt INTEGER NOT NULL, '
        'completedAt INTEGER'
        ')'
      );
      await db.execute(
        'CREATE TABLE IF NOT EXISTS cache_manifest ('
        'trackId TEXT PRIMARY KEY, '
        'title TEXT NOT NULL, '
        'artist TEXT NOT NULL, '
        'provider TEXT NOT NULL, '
        'format TEXT NOT NULL, '
        'filePath TEXT NOT NULL, '
        'sizeBytes INTEGER NOT NULL, '
        'cachedAt INTEGER NOT NULL, '
        'lastAccessed INTEGER NOT NULL'
        ')'
      );
    }
  }

  Future<void> insertPlaylist(PlaylistModel playlist) async {
    final db = await database;
    final map = playlist.toMap();
    if (playlist.createdAt == 0) {
      map['createdAt'] = DateTime.now().millisecondsSinceEpoch;
    }
    await db.insert('playlists', map,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updatePlaylistTitle(String id, String newTitle) async {
    final db = await database;
    await db.update('playlists', {'title': newTitle},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> removeTrack(String playlistId, String trackId) async {
    final db = await database;
    await db.delete('tracks',
        where: 'id = ? AND playlistId = ?', whereArgs: [trackId, playlistId]);
    final remaining = await db.query('tracks',
        where: 'playlistId = ?', whereArgs: [playlistId], orderBy: 'idx ASC');
    final batch = db.batch();
    for (var i = 0; i < remaining.length; i++) {
      batch.update('tracks', {'idx': i},
          where: 'id = ? AND playlistId = ?',
          whereArgs: [remaining[i]['id'], playlistId]);
    }
    await batch.commit(noResult: true);
    await db.update('playlists', {'videoCount': remaining.length},
        where: 'id = ?', whereArgs: [playlistId]);
  }

  Future<void> reorderTracks(
      String playlistId, List<String> trackIdsInOrder) async {
    final db = await database;
    final batch = db.batch();
    for (var i = 0; i < trackIdsInOrder.length; i++) {
      batch.update('tracks', {'idx': i},
          where: 'id = ? AND playlistId = ?',
          whereArgs: [trackIdsInOrder[i], playlistId]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> deletePlaylist(String id) async {
    final db = await database;
    await db.delete('tracks', where: 'playlistId = ?', whereArgs: [id]);
    await db.delete('playlists', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<PlaylistModel>> getAllPlaylists() async {
    final db = await database;
    final maps = await db.query('playlists', orderBy: 'createdAt DESC');
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

  Future<void> toggleFavoriteTrack(TrackModel track) async {
    final db = await database;
    final existing = await db.query('favorite_tracks',
        where: 'id = ?', whereArgs: [track.id], limit: 1);
    if (existing.isNotEmpty) {
      await db.delete('favorite_tracks', where: 'id = ?', whereArgs: [track.id]);
    } else {
      await db.insert('favorite_tracks', {
        'id': track.id,
        'title': track.title,
        'thumbnailUrl': track.thumbnailUrl,
        'durationSeconds': track.durationSeconds,
        'author': track.author,
        'favoritedAt': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  Future<bool> isTrackFavorite(String trackId) async {
    final db = await database;
    final result = await db.query('favorite_tracks',
        where: 'id = ?', whereArgs: [trackId], limit: 1);
    return result.isNotEmpty;
  }

  Future<Set<String>> getFavoriteTrackIds() async {
    final db = await database;
    final result = await db.query('favorite_tracks', columns: ['id']);
    return result.map((r) => r['id'] as String).toSet();
  }

  Future<List<TrackModel>> getFavoriteTracks() async {
    final db = await database;
    final maps = await db.query('favorite_tracks', orderBy: 'favoritedAt DESC');
    final tracks = maps.map((m) => TrackModel.fromMap(m)).toList();
    for (var i = 0; i < tracks.length; i++) {
      tracks[i] = TrackModel(
        id: tracks[i].id,
        title: tracks[i].title,
        thumbnailUrl: tracks[i].thumbnailUrl,
        durationSeconds: tracks[i].durationSeconds,
        author: tracks[i].author,
        index: i,
      );
    }
    return tracks;
  }

  // ALbums
  Future<void> toggleFavoriteAlbum(String id, String title, String? thumbnailUrl, String? artistName, String? year) async {
    final db = await database;
    final existing = await db.query('favorite_albums', where: 'id = ?', whereArgs: [id], limit: 1);
    if (existing.isNotEmpty) {
      await db.delete('favorite_albums', where: 'id = ?', whereArgs: [id]);
    } else {
      await db.insert('favorite_albums', {
        'id': id,
        'title': title,
        'thumbnailUrl': thumbnailUrl,
        'artistName': artistName,
        'year': year,
        'favoritedAt': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  Future<bool> isAlbumFavorite(String id) async {
    final db = await database;
    final result = await db.query('favorite_albums', where: 'id = ?', whereArgs: [id], limit: 1);
    return result.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> getFavoriteAlbums() async {
    final db = await database;
    return db.query('favorite_albums', orderBy: 'favoritedAt DESC');
  }

  // Artists
  Future<void> toggleFavoriteArtist(String id, String name, String? thumbnailUrl) async {
    final db = await database;
    final existing = await db.query('favorite_artists', where: 'id = ?', whereArgs: [id], limit: 1);
    if (existing.isNotEmpty) {
      await db.delete('favorite_artists', where: 'id = ?', whereArgs: [id]);
    } else {
      await db.insert('favorite_artists', {
        'id': id,
        'name': name,
        'thumbnailUrl': thumbnailUrl,
        'favoritedAt': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  Future<bool> isArtistFavorite(String id) async {
    final db = await database;
    final result = await db.query('favorite_artists', where: 'id = ?', whereArgs: [id], limit: 1);
    return result.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> getFavoriteArtists() async {
    final db = await database;
    return db.query('favorite_artists', orderBy: 'favoritedAt DESC');
  }
}
