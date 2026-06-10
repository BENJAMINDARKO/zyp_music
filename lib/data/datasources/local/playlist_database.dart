import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../models/playlist_model.dart';
import '../../models/video_model.dart';

/// Lightweight return type for [PlaylistDatabase.getCachedArtistGenres].
/// Carries the raw MusicBrainz tags (for future re-normalization) and
/// the already-normalized matrix keys (for the AI DJ scoring hot path).
/// Spec 2A §3B. Spec 2E: [countryCode] is the ISO 3166-1 alpha-2
/// country code captured from the MB artist document; nullable for
/// bands and historical artists.
class CachedArtistGenres {
  final List<String> rawGenres;
  final List<String> normalizedGenres;
  final String? countryCode;

  const CachedArtistGenres({
    required this.rawGenres,
    required this.normalizedGenres,
    this.countryCode,
  });
}

/// Result of [PlaylistDatabase.getTopSongsPerTopGenre] — one track per
/// top-listened genre.
class TopGenreTrack {
  final String trackId;
  final String? title;
  final String? artistName;
  final String? thumbnailUrl;
  final String primaryGenre;
  final int playCount;

  const TopGenreTrack({
    required this.trackId,
    required this.title,
    required this.artistName,
    required this.thumbnailUrl,
    required this.primaryGenre,
    required this.playCount,
  });
}

/// Result of [PlaylistDatabase.getMostPlayedAlbumsAndSingles] — mixed list
/// of albums and singles.
class PopularItem {
  final String kind;
  final String id;
  final String? title;
  final String? artistName;
  final String? thumbnailUrl;
  final int playCount;

  const PopularItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.artistName,
    required this.thumbnailUrl,
    required this.playCount,
  });

  bool get isAlbum => kind == 'album';
  bool get isSingle => kind == 'single';
}

/// Result of [PlaylistDatabase.getListeningStats] — aggregate stats for
/// the Library Stats UI.
class ListeningStats {
  final int distinctGenreCount;
  final int distinctArtistCount;
  final List<ArtistPlayStat> topArtists;
  final List<AlbumPlayStat> topAlbums;

  const ListeningStats({
    required this.distinctGenreCount,
    required this.distinctArtistCount,
    required this.topArtists,
    required this.topAlbums,
  });

  static const ListeningStats empty = ListeningStats(
    distinctGenreCount: 0,
    distinctArtistCount: 0,
    topArtists: [],
    topAlbums: [],
  );
}

class ArtistPlayStat {
  final String artistName;
  final int playCount;
  const ArtistPlayStat({required this.artistName, required this.playCount});
}

class HistoryArtistEntry {
  final String artistName;
  final int playCount;
  final String? sampleTrackId;
  final String? thumbnailUrl;

  const HistoryArtistEntry({
    required this.artistName,
    required this.playCount,
    required this.sampleTrackId,
    required this.thumbnailUrl,
  });
}

class AlbumPlayStat {
  final String albumId;
  final String? albumTitle;
  final int playCount;
  const AlbumPlayStat({
    required this.albumId,
    required this.albumTitle,
    required this.playCount,
  });
}

class _AlbumAggregate {
  final String albumId;
  final String? albumTitle;
  final String? artistName;
  final String? thumbnailUrl;
  int playCount;

  _AlbumAggregate({
    required this.albumId,
    required this.albumTitle,
    required this.artistName,
    required this.thumbnailUrl,
    required this.playCount,
  });
}

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
      version: 16,
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
        album TEXT DEFAULT NULL,
        albumId TEXT DEFAULT NULL,
        year INTEGER DEFAULT NULL,
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
      'normalized_artist        TEXT PRIMARY KEY, '
      'display_name             TEXT    NOT NULL, '
      'mbid                     TEXT    NOT NULL, '
      'genres_json              TEXT    NOT NULL, '
      'genre_count              INTEGER NOT NULL DEFAULT 0, '
      'fetched_at               INTEGER NOT NULL, '
      'normalized_genres_json   TEXT    NOT NULL DEFAULT \'[]\', '
      'normalization_version    INTEGER NOT NULL DEFAULT 1, '
      'confidence               INTEGER DEFAULT NULL, '
      'country_code             TEXT    DEFAULT NULL'
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
    if (oldVersion < 14) {
      // Spec 2A: persist the normalized matrix keys alongside
      // the raw MusicBrainz tags so the AI DJ scoring engine
      // can read them on a hot path without re-running the
      // normalization dictionary. `normalization_version`
      // starts at 1; bump and add a one-time re-normalization
      // pass if a major dictionary revision ever lands.
      await db.execute(
        'ALTER TABLE artist_genres ADD COLUMN '
        'normalized_genres_json TEXT NOT NULL DEFAULT \'[]\'',
      );
      await db.execute(
        'ALTER TABLE artist_genres ADD COLUMN '
        'normalization_version INTEGER NOT NULL DEFAULT 1',
      );
      await db.execute(
        'ALTER TABLE artist_genres ADD COLUMN '
        'confidence INTEGER DEFAULT NULL',
      );
    }
    if (oldVersion < 15) {
      // Spec 2E: persist the artist's ISO 3166-1 alpha-2 country
      // code captured from MusicBrainz's `country` field on the
      // artist document. Nullable: bands, historical artists, and
      // MB entries that pre-date the field will return NULL, and
      // [CountryBonusService.scoreFor] treats either side being
      // null as `unknown` → neutral 1.0 bonus. The routing layer
      // never blocks the hot path on this column — the bonus is
      // multiplicative and the seeded Track always short-circuits
      // the artist-already-played test before we get here.
      await db.execute(
        'ALTER TABLE artist_genres ADD COLUMN '
        'country_code TEXT DEFAULT NULL',
      );
    }
    if (oldVersion < 16) {
      // Phase 1: add album/albumId/year columns to downloaded_tracks
      // for the Home Feed data layer (album/single classification and
      // album aggregation queries). Existing rows get NULL; new rows
      // are populated by markTrackDownloaded from the Track entity.
      await db.execute(
        'ALTER TABLE downloaded_tracks ADD COLUMN '
        'album TEXT DEFAULT NULL',
      );
      await db.execute(
        'ALTER TABLE downloaded_tracks ADD COLUMN '
        'albumId TEXT DEFAULT NULL',
      );
      await db.execute(
        'ALTER TABLE downloaded_tracks ADD COLUMN '
        'year INTEGER DEFAULT NULL',
      );
    }
  }

  Future<CachedArtistGenres?> getCachedArtistGenres(String normalizedArtist) async {
    if (normalizedArtist.trim().isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      'artist_genres',
      columns: const [
        'genres_json',
        'genre_count',
        'fetched_at',
        'normalized_genres_json',
        'country_code',
      ],
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

    final normalizedRaw = row['normalized_genres_json'] as String?;
    List<String> normalizedGenres = const <String>[];
    if (normalizedRaw != null && normalizedRaw.isNotEmpty) {
      final decodedNorm = jsonDecode(normalizedRaw);
      if (decodedNorm is List) {
        normalizedGenres = decodedNorm.whereType<String>().toList(growable: false);
      }
    }

    final countryCodeRaw = row['country_code'] as String?;
    final countryCode = (countryCodeRaw != null && countryCodeRaw.isNotEmpty)
        ? countryCodeRaw
        : null;

    final ageMs = DateTime.now().millisecondsSinceEpoch - fetchedAt;
    const thinTtl = Duration(days: 90);
    final isThin = genreCount < 3;
    if (isThin && ageMs < thinTtl.inMilliseconds) {
      return CachedArtistGenres(
        rawGenres: genres,
        normalizedGenres: normalizedGenres,
        countryCode: countryCode,
      );
    }
    if (!isThin) {
      return CachedArtistGenres(
        rawGenres: genres,
        normalizedGenres: normalizedGenres,
        countryCode: countryCode,
      );
    }
    return null;
  }

  Future<void> cacheArtistGenres({
    required String normalizedArtist,
    required List<String> genres,
    required List<String> normalizedGenres,
    String? mbid,
    String? displayName,
    int? confidence,
    String? countryCode,
  }) async {
    if (normalizedArtist.trim().isEmpty) return;
    final db = await database;
    await db.insert(
      'artist_genres',
      {
        'normalized_artist': normalizedArtist,
        'display_name': displayName ?? '',
        'mbid': mbid ?? '',
        'genres_json': jsonEncode(genres),
        'genre_count': genres.length,
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
        'normalized_genres_json': jsonEncode(normalizedGenres),
        'normalization_version': 1,
        'confidence': confidence,
        'country_code': (countryCode != null && countryCode.isNotEmpty)
            ? countryCode
            : null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Batched ISO 3166-1 alpha-2 country lookup for a set of
  /// artist display names. Returns a map keyed by the input
  /// (display) names — misses are absent from the result. The
  /// crate miner passes the YouTube `t.author` value directly;
  /// we look up against `display_name` (case-insensitive)
  /// because the YouTube artist string usually matches MB's
  /// `name` field and the miner has no normaliser dependency.
  /// The bonus service treats `null` as "unknown" → 1.0, so
  /// a miss never disqualifies a candidate. Spec 2E §3.
  Future<Map<String, String?>> getArtistCountries(Set<String> displayArtists) async {
    if (displayArtists.isEmpty) return const <String, String?>{};
    final db = await database;
    final lower = displayArtists
        .map((a) => a.toLowerCase().trim())
        .where((a) => a.isNotEmpty)
        .toList(growable: false);
    if (lower.isEmpty) return const <String, String?>{};
    final rows = await db.query(
      'artist_genres',
      columns: const ['display_name', 'country_code'],
      where: 'LOWER(display_name) IN ('
          '${List.filled(lower.length, '?').join(',')})',
      whereArgs: lower,
    );
    final lowerToCode = <String, String?>{};
    for (final row in rows) {
      final dn = (row['display_name'] as String?)?.toLowerCase().trim();
      if (dn == null) continue;
      final raw = row['country_code'] as String?;
      lowerToCode[dn] = (raw != null && raw.isNotEmpty) ? raw : null;
    }
    final out = <String, String?>{};
    for (final original in displayArtists) {
      final key = original.toLowerCase().trim();
      if (key.isEmpty) continue;
      if (lowerToCode.containsKey(key)) {
        out[original] = lowerToCode[key];
      }
    }
    return out;
  }

  /// Spec 2H: return the count of downloaded tracks per
  /// normalised genre cluster. Used by the Shuffle Library
  /// filter sub-menu to display a ranked list of genre
  /// options. INNER JOIN excludes unenriched artists (no
  /// useful filter on those). The result is a count per
  /// canonical genre key (matching the proximity-matrix
  /// schema), descending by count.
  Future<Map<String, int>> getGenreClusterCounts() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT ag.normalized_genres_json AS genres
      FROM downloaded_tracks dt
      INNER JOIN artist_genres ag
        ON LOWER(ag.display_name) = LOWER(dt.author)
      WHERE ag.normalized_genres_json IS NOT NULL
        AND ag.normalized_genres_json != '[]'
    ''');
    final counts = <String, int>{};
    for (final row in rows) {
      final raw = row['genres'] as String?;
      if (raw == null || raw.isEmpty) continue;
      final decoded = jsonDecode(raw);
      if (decoded is! List) continue;
      for (final g in decoded) {
        if (g is! String) continue;
        final key = g.trim();
        if (key.isEmpty) continue;
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    return counts;
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
      {String title = '', String? thumbnailUrl, int? durationSeconds, String? author,
      String? album, String? albumId, int? year}) async {
    final db = await database;
    await db.insert('downloaded_tracks', {
      'id': trackId,
      'playlistId': playlistId,
      'title': title,
      'thumbnailUrl': thumbnailUrl,
      'durationSeconds': durationSeconds,
      'author': author,
      'album': album,
      'albumId': albumId,
      'year': year,
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

  /// Returns all rows from downloaded_tracks, ordered by most recently
  /// downloaded first.
  Future<List<Map<String, dynamic>>> getAllDownloadedTracks() async {
    final db = await database;
    return db.rawQuery('''
      SELECT *
      FROM downloaded_tracks
      ORDER BY downloadedAt DESC
    ''');
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

  // -------------------------------------------------------------------------
  // Home Feed Queries (Phase 1)
  // -------------------------------------------------------------------------

  /// Returns the top track from each of the top N most-played genres in the
  /// full 180-day window of dj_listening_history.
  Future<List<TopGenreTrack>> getTopSongsPerTopGenre({
    int genreLimit = 6,
    int trackLimitPerGenre = 1,
  }) async {
    final db = await database;

    final topGenresResult = await db.rawQuery('''
      SELECT primary_genre, COUNT(*) as plays
      FROM dj_listening_history
      WHERE primary_genre != 'Unknown' AND primary_genre IS NOT NULL
      GROUP BY primary_genre
      ORDER BY plays DESC
      LIMIT ?
    ''', [genreLimit]);

    if (topGenresResult.isEmpty) return [];

    final result = <TopGenreTrack>[];

    for (final genreRow in topGenresResult) {
      final genre = genreRow['primary_genre'] as String;

      final trackResult = await db.rawQuery('''
        SELECT
          h.track_id,
          h.artist_name,
          h.primary_genre,
          COUNT(*) as plays,
          dt.title,
          dt.thumbnailUrl
        FROM dj_listening_history h
        LEFT JOIN downloaded_tracks dt ON dt.id = h.track_id
        WHERE h.primary_genre = ?
        GROUP BY h.track_id
        ORDER BY plays DESC
        LIMIT ?
      ''', [genre, trackLimitPerGenre]);

      for (final trackRow in trackResult) {
        result.add(TopGenreTrack(
          trackId: trackRow['track_id'] as String,
          title: trackRow['title'] as String?,
          artistName: trackRow['artist_name'] as String?,
          thumbnailUrl: trackRow['thumbnailUrl'] as String?,
          primaryGenre: trackRow['primary_genre'] as String,
          playCount: trackRow['plays'] as int,
        ));
      }
    }

    return result;
  }

  /// Returns the top N most-played items, mixed between albums and singles,
  /// ranked by total play count in the 180-day window.
  Future<List<PopularItem>> getMostPlayedAlbumsAndSingles({
    int limit = 10,
  }) async {
    final db = await database;

    final rows = await db.rawQuery('''
      SELECT
        h.track_id,
        h.artist_name,
        COUNT(*) as plays,
        dt.title,
        dt.author,
        dt.album,
        dt.albumId,
        dt.thumbnailUrl
      FROM dj_listening_history h
      LEFT JOIN downloaded_tracks dt ON dt.id = h.track_id
      GROUP BY h.track_id
    ''');

    final albumAggregates = <String, _AlbumAggregate>{};
    final singleEntries = <PopularItem>[];

    for (final row in rows) {
      final trackId = row['track_id'] as String;
      final title = row['title'] as String?;
      final album = row['album'] as String?;
      final albumId = row['albumId'] as String?;
      final plays = row['plays'] as int;
      final artistName = row['author'] as String?;
      final thumbnailUrl = row['thumbnailUrl'] as String?;

      final isSingle = album == null ||
          album.isEmpty ||
          (title != null && album.toLowerCase() == title.toLowerCase());

      if (isSingle) {
        singleEntries.add(PopularItem(
          kind: 'single',
          id: trackId,
          title: title ?? 'Unknown',
          artistName: artistName,
          thumbnailUrl: thumbnailUrl,
          playCount: plays,
        ));
      } else if (albumId != null) {
        final existing = albumAggregates[albumId];
        if (existing == null) {
          albumAggregates[albumId] = _AlbumAggregate(
            albumId: albumId,
            albumTitle: album,
            artistName: artistName,
            thumbnailUrl: thumbnailUrl,
            playCount: plays,
          );
        } else {
          existing.playCount += plays;
        }
      }
    }

    final albumEntries = albumAggregates.values.map((agg) => PopularItem(
          kind: 'album',
          id: agg.albumId,
          title: agg.albumTitle,
          artistName: agg.artistName,
          thumbnailUrl: agg.thumbnailUrl,
          playCount: agg.playCount,
        ));

    final all = [...albumEntries, ...singleEntries];
    all.sort((a, b) => b.playCount.compareTo(a.playCount));

    return all.take(limit).toList();
  }

  /// Returns aggregate listening statistics for the last 30 days.
  Future<ListeningStats> getListeningStats() async {
    final db = await database;
    final cutoffMs = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;

    final countsResult = await db.rawQuery('''
      SELECT
        COUNT(DISTINCT primary_genre) as genre_count,
        COUNT(DISTINCT artist_name) as artist_count
      FROM dj_listening_history
      WHERE timestamp > ?
        AND primary_genre IS NOT NULL
        AND primary_genre != 'Unknown'
        AND artist_name IS NOT NULL
        AND artist_name != ''
        AND artist_name != 'Unknown'
    ''', [cutoffMs]);

    if (countsResult.isEmpty) return ListeningStats.empty;

    final distinctGenres = countsResult.first['genre_count'] as int? ?? 0;
    final distinctArtists = countsResult.first['artist_count'] as int? ?? 0;

    if (distinctArtists == 0) return ListeningStats.empty;

    final topArtistsResult = await db.rawQuery('''
      SELECT artist_name, COUNT(*) as plays
      FROM dj_listening_history
      WHERE timestamp > ?
        AND artist_name IS NOT NULL
        AND artist_name != ''
        AND artist_name != 'Unknown'
      GROUP BY artist_name
      ORDER BY plays DESC
      LIMIT 3
    ''', [cutoffMs]);

    final topArtists = topArtistsResult.map((r) => ArtistPlayStat(
          artistName: r['artist_name'] as String,
          playCount: r['plays'] as int,
        )).toList();

    final albumsRaw = await db.rawQuery('''
      SELECT
        dt.albumId,
        dt.album,
        COUNT(*) as plays
      FROM dj_listening_history h
      INNER JOIN downloaded_tracks dt ON dt.id = h.track_id
      WHERE h.timestamp > ?
        AND dt.albumId IS NOT NULL
        AND dt.album IS NOT NULL
        AND dt.album != ''
        AND LOWER(dt.album) != LOWER(dt.title)
      GROUP BY dt.albumId
      ORDER BY plays DESC
      LIMIT 3
    ''', [cutoffMs]);

    final topAlbums = albumsRaw.map((r) => AlbumPlayStat(
          albumId: r['albumId'] as String,
          albumTitle: r['album'] as String?,
          playCount: r['plays'] as int,
        )).toList();

    return ListeningStats(
      distinctGenreCount: distinctGenres,
      distinctArtistCount: distinctArtists,
      topArtists: topArtists,
      topAlbums: topAlbums,
    );
  }

  Future<List<HistoryArtistEntry>> getTopArtistsFromHistory({
    int limit = 10,
  }) async {
    final db = await database;
    final topArtistsResult = await db.rawQuery('''
      SELECT artist_name, COUNT(*) as plays
      FROM dj_listening_history
      WHERE artist_name IS NOT NULL
        AND artist_name != ''
        AND artist_name != 'Unknown'
      GROUP BY artist_name
      ORDER BY plays DESC
      LIMIT ?
    ''', [limit]);

    if (topArtistsResult.isEmpty) return [];

    final result = <HistoryArtistEntry>[];

    for (final artistRow in topArtistsResult) {
      final artistName = artistRow['artist_name'] as String;
      final playCount = artistRow['plays'] as int;

      final sampleResult = await db.rawQuery('''
        SELECT
          h.track_id,
          dt.thumbnailUrl,
          COUNT(*) as track_plays
        FROM dj_listening_history h
        LEFT JOIN downloaded_tracks dt ON dt.id = h.track_id
        WHERE h.artist_name = ?
        GROUP BY h.track_id
        ORDER BY track_plays DESC
        LIMIT 1
      ''', [artistName]);

      final sampleRow = sampleResult.isNotEmpty ? sampleResult.first : null;

      result.add(HistoryArtistEntry(
        artistName: artistName,
        playCount: playCount,
        sampleTrackId: sampleRow?['track_id'] as String?,
        thumbnailUrl: sampleRow?['thumbnailUrl'] as String?,
      ));
    }

    return result;
  }
}
