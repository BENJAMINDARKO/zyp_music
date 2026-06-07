import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../models/playlist_model.dart';
import '../../models/video_model.dart';

class PlaylistDatabase {
  /// Test-only factory: instantiates a fresh [PlaylistDatabase]
  /// backed by [path] (caller is responsible for the file's
  /// lifecycle — the test uses a tmp path and deletes it in
  /// tearDown). Production callers should use the default
  /// `PlaylistDatabase()` constructor which uses the static
  /// singleton shared by all DAO consumers.
  factory PlaylistDatabase.forTesting(String path) {
    return PlaylistDatabase._withPath(path);
  }

  PlaylistDatabase._withPath(this._customPath);

  PlaylistDatabase() : _customPath = null;

  static Database? _database;
  static Completer<void> _initCompleter = Completer<void>();
  static bool _initStarted = false;

  final String? _customPath;

  Future<Database> get database async {
    // Test instances use their own database (no shared state).
    if (_customPath != null) {
      if (_database == null) {
        _database = await _initDatabase();
      }
      return _database!;
    }
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

  /// Closes the underlying database. The test harness uses
  /// this in tearDown. Production code does not close the
  /// singleton.
  Future<void> close() async {
    final db = _database;
    _database = null;
    if (_customPath == null) {
      // Reset the singleton init guard so a subsequent
      // `PlaylistDatabase()` can re-initialize after a test.
      _initStarted = false;
      _initCompleter = Completer<void>();
    }
    await db?.close();
  }

  Future<Database> _initDatabase() async {
    final String path;
    if (_customPath != null) {
      path = _customPath!;
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, 'ytmusix.db');
    }
    return openDatabase(
      path,
      version: 13,
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
    await db.execute(
      'CREATE TABLE IF NOT EXISTS dj_listening_history ('
      'id           INTEGER PRIMARY KEY AUTOINCREMENT, '
      'track_id     TEXT    NOT NULL, '
      'artist_name  TEXT    NOT NULL, '
      'primary_genre TEXT   DEFAULT \'Unknown\', '
      'bpm          REAL    DEFAULT 0.0, '
      'energy_level REAL    DEFAULT 0.5, '
      'timestamp    INTEGER NOT NULL'
      ')'
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_dj_history_artist '
      'ON dj_listening_history(artist_name)'
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS track_metadata ('
      'track_id          TEXT PRIMARY KEY, '
      'silence_start_ms  INTEGER DEFAULT NULL, '
      'bpm               REAL    DEFAULT NULL, '
      'genre             TEXT    DEFAULT NULL, '
      'scanned_at        INTEGER NOT NULL'
      ')'
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS artist_genres ('
      'normalized_artist TEXT PRIMARY KEY, '
      'display_name      TEXT    NOT NULL, '
      'mbid              TEXT    NOT NULL, '
      'genres_json       TEXT    NOT NULL, '
      'genre_count       INTEGER NOT NULL DEFAULT 0, '
      'fetched_at        INTEGER NOT NULL'
      ')'
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_artist_genres_fetched_at '
      'ON artist_genres(fetched_at)'
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
    if (oldVersion < 9) {
      // Phase 1 of the AI DJ engine: listening-history ledger that
      // serves as the baseline training corpus for the pattern engine.
      // Trimmed to 300 rows after each write by the application layer
      // (see DJHistoryLedger). BPM/energy/genre are sourced from the
      // local library metadata; unknown values fall back to the
      // DEFAULT clauses below.
      await db.execute(
        'CREATE TABLE IF NOT EXISTS dj_listening_history ('
        'id           INTEGER PRIMARY KEY AUTOINCREMENT, '
        'track_id     TEXT    NOT NULL, '
        'artist_name  TEXT    NOT NULL, '
        'primary_genre TEXT   DEFAULT \'Unknown\', '
        'bpm          REAL    DEFAULT 0.0, '
        'energy_level REAL    DEFAULT 0.5, '
        'timestamp    INTEGER NOT NULL'
        ')'
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_dj_history_artist '
        'ON dj_listening_history(artist_name)'
      );
    }
    if (oldVersion < 10) {
      // Phase 3 of the AI DJ engine: per-track audio metadata
      // (silence boundary, future BPM/energy/mood vectors). The
      // silence boundary is computed off-thread by
      // SilenceScanWorker and written here so the gapless mixer
      // can pre-trigger crossfades before the trailing dead-air
      // padding. BPM/energy/mood columns are intentionally
      // reserved for future phases — this migration only adds
      // the silence boundary column the spec calls out.
      await db.execute(
        'CREATE TABLE IF NOT EXISTS track_metadata ('
        'track_id          TEXT PRIMARY KEY, '
        'silence_start_ms  INTEGER DEFAULT NULL, '
        'scanned_at        INTEGER NOT NULL'
        ')'
      );
    }
    if (oldVersion < 11) {
      // Phase 4 of the AI DJ engine: per-track BPM marker used
      // by the DSP crossfade engine for tempo matching. The
      // column is added without a default value so existing rows
      // stay NULL; future writes from the crate miner / manual
      // user BPM edits populate it. The DSP engine falls back
      // to the listening-history ledger (dj_listening_history.bpm)
      // when this column is NULL.
      await db.execute(
        'ALTER TABLE track_metadata ADD COLUMN bpm REAL DEFAULT NULL'
      );
    }
    if (oldVersion < 12) {
      // Phase 5 of the AI DJ engine: per-track `genre` marker
      // captured at fetch time so the routing service can score
      // candidates without re-querying the remote scraper. The
      // column is intentionally nullable: the YouTube Music
      // `UpNextsDetails` payload exposes `album.name` only as a
      // weak proxy, so we record whatever signal was on the
      // wire and let the crate miner / listening-history ledger
      // fill the gap when the column is NULL.
      await db.execute(
        'ALTER TABLE track_metadata ADD COLUMN genre TEXT DEFAULT NULL'
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_track_metadata_genre '
        'ON track_metadata(genre)'
      );
    }
    if (oldVersion < 13) {
      // Phase 6 of the AI DJ engine: a per-artist cached genre
      // list sourced from MusicBrainz. The normalized artist
      // name is the key (Unicode-folded, case-folded, accent-
      // stripped) so the same artist recorded under multiple
      // spellings collapses to one row. `mbid` is stored so a
      // future re-fetch can hit MusicBrainz's per-artist
      // endpoint directly without re-running the name search.
      // `fetched_at` is epoch-ms; `genre_count` is the size of
      // the cached genre list at write time so the service can
      // cheaply decide whether to re-query (empty/thin lists
      // have a longer TTL than rich ones).
      await db.execute(
        'CREATE TABLE IF NOT EXISTS artist_genres ('
        'normalized_artist TEXT PRIMARY KEY, '
        'display_name      TEXT    NOT NULL, '
        'mbid              TEXT    NOT NULL, '
        'genres_json       TEXT    NOT NULL, '
        'genre_count       INTEGER NOT NULL DEFAULT 0, '
        'fetched_at        INTEGER NOT NULL'
        ')'
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_artist_genres_fetched_at '
        'ON artist_genres(fetched_at)'
      );
    }
  }

  Future<List<String>?> getCachedArtistGenres(String normalizedArtist) async {
    if (normalizedArtist.trim().isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      'artist_genres',
      columns: const ['genres_json', 'genre_count', 'fetched_at'],
      where: 'normalized_artist = ?',
      whereArgs: [normalizedArtist],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final genreCount = (row['genre_count'] as int?) ?? 0;
    final fetchedAt = (row['fetched_at'] as int?) ?? 0;
    final raw = row['genres_json'] as String?;
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! List) return null;
    final genres = decoded.whereType<String>().toList(growable: false);
    if (genres.isEmpty) return null;
    final ageMs = DateTime.now().millisecondsSinceEpoch - fetchedAt;
    const thinTtl = Duration(days: 90);
    final isThin = genreCount < 3;
    if (isThin && ageMs < thinTtl.inMilliseconds) {
      return genres;
    }
    if (!isThin) {
      return genres;
    }
    return null;
  }

  Future<void> cacheArtistGenres({
    required String normalizedArtist,
    required String displayName,
    required String mbid,
    required List<String> genres,
  }) async {
    if (normalizedArtist.trim().isEmpty) return;
    final db = await database;
    await db.insert(
      'artist_genres',
      {
        'normalized_artist': normalizedArtist,
        'display_name': displayName,
        'mbid': mbid,
        'genres_json': jsonEncode(genres),
        'genre_count': genres.length,
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
      {String title = '', String? thumbnailUrl, int? durationSeconds, String? author}) async {
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
    // Phase 3: fire-and-forget silence scan for the freshly
    // committed file. Runs in an isolate; never blocks the
    // download commit.
    _scheduleSilenceScan(trackId, filePath);
  }

  /// Backfills (or clears) the `durationSeconds` column for a
  /// already-persisted downloaded track. Used by the C2
  /// `probeDurationFromFile` flow: when a track landed on disk
  /// without a YouTube API duration (live streams, unlisted
  /// videos), the audio repository's `_backfillDuration` calls
  /// this with the probed integer seconds to retire the
  /// `—:—` placeholder in favour of a real value. Passing
  /// `seconds: null` writes SQL `NULL` (used by the backfill
  /// helper to "undo" a backfill if a later re-download
  /// supplies a definitive YouTube-API value).
  ///
  /// No-op when the track is not in `downloaded_tracks`
  /// (e.g. it was evicted between the cache write and the
  /// probe completing).
  ///
  /// [seconds] is nullable so the same call can both
  /// "backfill a probed value" and "restore the unknown
  /// sentinel" depending on the caller's intent.
  Future<void> updateTrackDuration(
    String trackId, {
    int? seconds,
  }) async {
    final db = await database;
    await db.update(
      'downloaded_tracks',
      {'durationSeconds': seconds},
      where: 'id = ?',
      whereArgs: [trackId],
    );
  }

  Future<bool> isTrackDownloaded(String trackId) async {
    final db = await database;
    final result = await db.query('downloaded_tracks',
        where: 'id = ?', whereArgs: [trackId], limit: 1);
    return result.isNotEmpty;
  }

  /// Setter for the silence-scan scheduler. Late-bound (not in
  /// the constructor) to avoid a cycle between the data and
  /// audio layers. The host wires this from `main.dart` after
  /// constructing the scheduler.
  /// ignore: prefer_final_fields
  static dynamic _scanScheduler;

  static void setSilenceScanScheduler(dynamic scheduler) {
    _scanScheduler = scheduler;
  }

  /// Fires a silence scan for the freshly-cached file. Called
  /// from [markTrackDownloaded] after the SQL row is written so
  /// the spec's "trigger in the background immediately following
  /// any new stream cache commit or file download task" hook is
  /// satisfied. Fire-and-forget; never throws.
  void _scheduleSilenceScan(String trackId, String filePath) {
    final scheduler = _scanScheduler;
    if (scheduler == null) return;
    try {
      // Duck-typed enqueue: the scheduler exposes an
      // `enqueue(trackId, filePath)` method (see
      // SilenceScanScheduler). The duck-typed call keeps the
      // data layer decoupled from the audio layer.
      // ignore: avoid_dynamic_calls
      scheduler.enqueue(trackId, filePath);
    } catch (_) {
      // Scan scheduling is best-effort; failures must not
      // bubble up into the download commit path.
    }
  }

  Future<String?> getDownloadedFilePath(String trackId) async {
    final db = await database;
    final result = await db.query('downloaded_tracks',
        where: 'id = ?', whereArgs: [trackId], limit: 1);
    if (result.isEmpty) return null;
    return result.first['filePath'] as String?;
  }

  /// Returns the full [downloaded_tracks] row for [trackId] as a
  /// column-name → value map, or `null` when no row exists.
  /// Backs the Phase 6 cached-metadata spec's three-tier
  /// synthesis lookup: Hive-only entries (no SQLite row) fall
  /// through to the Hive tier; entries that do have a row are
  /// rebuilt from these columns so the synthesis path can
  /// return a fully-populated [Track] without a second
  /// round-trip.
  ///
  /// Column reference (per `_createTables` schema, version 13):
  ///   * `id` (TEXT PK)
  ///   * `playlistId` (TEXT NOT NULL)
  ///   * `title` (TEXT NOT NULL)
  ///   * `thumbnailUrl` (TEXT?)
  ///   * `durationSeconds` (INTEGER DEFAULT 0 — null/zero treated
  ///     as "unknown" by the C1 honest-nulls spec)
  ///   * `author` (TEXT?)
  ///   * `filePath` (TEXT NOT NULL)
  ///   * `downloadedAt` (INTEGER NOT NULL)
  ///   * `source` (TEXT DEFAULT 'youtube')
  Future<Map<String, dynamic>?> getDownloadedTrack(String trackId) async {
    final db = await database;
    final result = await db.query('downloaded_tracks',
        where: 'id = ?', whereArgs: [trackId], limit: 1);
    if (result.isEmpty) return null;
    return result.first;
  }

  Future<List<Map<String, dynamic>>> getDownloadedTracks(String playlistId) async {
    final db = await database;
    return db.query('downloaded_tracks',
        where: 'playlistId = ?', whereArgs: [playlistId]);
  }

  /// Returns every row in `downloaded_tracks` (no playlist filter).
  /// Used by the AI DJ crate miner in Phase 2 to assemble the local
  /// candidate pool. Returns an empty list if the table is empty or
  /// not yet provisioned.
  Future<List<Map<String, dynamic>>> rawQueryDownloadedTracks() async {
    final db = await database;
    return db.query('downloaded_tracks');
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

  // ---------------------------------------------------------------------------
  // track_metadata (Phase 3: silence boundary scanner)
  // ---------------------------------------------------------------------------

  /// Upserts a single row of track metadata. The worker calls this
  /// after a successful RMS scan to persist the silence boundary.
  /// The `conflictAlgorithm.replace` clause means re-scanning a
  /// track overwrites its previous row.
  Future<void> upsertTrackMetadata(
      String trackId, int? silenceStartMs) async {
    final db = await database;
    await db.insert(
      'track_metadata',
      {
        'track_id': trackId,
        'silence_start_ms': silenceStartMs,
        'scanned_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns the silence boundary (in milliseconds from track
  /// start) for [trackId], or `null` if the row does not exist
  /// yet (i.e. the worker has not scanned this track). The mixer
  /// uses the spec's "duration - 5000ms" fallback when the
  /// returned value is null.
  Future<int?> getSilenceStartMs(String trackId) async {
    final db = await database;
    final rows = await db.query(
      'track_metadata',
      columns: ['silence_start_ms'],
      where: 'track_id = ?',
      whereArgs: [trackId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['silence_start_ms'] as int?;
  }

  /// Returns the full metadata row (trackId, silence boundary,
  /// scan timestamp) for the given track. Used by the validation
  /// gate tests to assert the worker wrote a sensible value.
  Future<Map<String, Object?>?> getTrackMetadata(String trackId) async {
    final db = await database;
    final rows = await db.query(
      'track_metadata',
      where: 'track_id = ?',
      whereArgs: [trackId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// Phase 4: per-track BPM marker used by the DSP crossfade
  /// engine for tempo matching.
  ///
  /// Returns the authoritative reading for [trackId] in this
  /// priority order:
  ///   1. `track_metadata.bpm` — the per-track authoritative
  ///      marker (set by the crate miner, the user's manual
  ///      BPM editor, or future automated analyzers).
  ///   2. `MAX(bpm) FROM dj_listening_history WHERE track_id = ?`
  ///      — the highest non-zero reading captured by the
  ///      history ledger (Phase 1). Multiple history rows
  ///      can accumulate per track as the user listens
  ///      repeatedly; the highest is the best signal.
  ///   3. `null` — no BPM is known. The DSP engine treats a
  ///      null BPM as "skip tempo matching, run a vanilla
  ///      equal-power crossfade at 1.0x".
  Future<double?> getTrackBpm(String trackId) async {
    final db = await database;
    final metaRows = await db.query(
      'track_metadata',
      columns: ['bpm'],
      where: 'track_id = ? AND bpm IS NOT NULL',
      whereArgs: [trackId],
      limit: 1,
    );
    if (metaRows.isNotEmpty) {
      final v = metaRows.first['bpm'];
      if (v is num && v > 0) return v.toDouble();
    }
    final histRows = await db.rawQuery(
      'SELECT MAX(bpm) AS m FROM dj_listening_history '
      'WHERE track_id = ? AND bpm > 0',
      [trackId],
    );
    if (histRows.isEmpty) return null;
    final v = histRows.first['m'];
    if (v is num && v > 0) return v.toDouble();
    return null;
  }

  /// Sets the per-track BPM marker (Phase 4). Pass `null` to
  /// clear. The DSP engine reads the marker on every
  /// `crossfadeReady` event so this method is intentionally
  /// cheap and overwrite-only.
  Future<void> setTrackBpm(String trackId, double? bpm) async {
    final db = await database;
    await db.insert(
      'track_metadata',
      {
        'track_id': trackId,
        'bpm': bpm,
        'scanned_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // -------------------------------------------------------------------------
  // Phase 5: per-track `genre` marker.
  //
  // Populated at fetch time by `AudioRepository.getUpNexts`
  // (the web-scraping pass) so the routing service can score
  // candidates against `current.genre` with zero extra round
  // trips. The crate miner also consults this column for tracks
  // that were never streamed through the YouTube Music endpoint
  // (e.g. local downloads imported before this migration).
  // -------------------------------------------------------------------------

  /// Sets the per-track genre marker. Pass `null` to clear.
  /// Overwrite-only: this is the canonical write surface for
  /// the genre capture hook. The `scanned_at` column is
  /// repurposed to record the last-write timestamp so the
  /// schema stays single-table.
  Future<void> setTrackGenre(String trackId, String? genre) async {
    final db = await database;
    await db.insert(
      'track_metadata',
      {
        'track_id': trackId,
        'genre': genre,
        'scanned_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns the genre string for [trackId], or `null` if no
  /// genre has been recorded. The crate miner / routing
  /// service use this to enrich candidates without re-querying
  /// the remote scraper.
  Future<String?> getTrackGenre(String trackId) async {
    final db = await database;
    final rows = await db.query(
      'track_metadata',
      columns: ['genre'],
      where: 'track_id = ? AND genre IS NOT NULL',
      whereArgs: [trackId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['genre'] as String?;
  }
}
