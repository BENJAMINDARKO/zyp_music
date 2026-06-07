import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../data/datasources/local/playlist_database.dart';
import '../../domain/entities/video.dart';
import 'dj_history_ledger.dart';
import 'hybrid_cache_service.dart';
import '../utils/app_logger.dart';

/// Function signature for the optional on-disk existence check used
/// by the crate miner. Production code resolves to `File(path).exists()`;
/// tests inject a fake so they can run on the host VM without a real
/// device filesystem.
typedef FileExists = Future<bool> Function(String path);

/// Function signature for the optional resolver that maps a Hive
/// `cache_tracker_box` trackId to a concrete audio file path on disk.
/// The HybridCacheService stores audio files at
/// `<docs>/audio_cache/<trackId>.<ext>` but does not record the
/// extension in the box; production code injects a resolver that
/// tries the common extensions and returns the first hit.
///
/// Tests inject a fake that returns null (skip the Hive tier
/// entirely) or returns a controlled path backed by a temp file.
typedef HiveAudioPathResolver = Future<String?> Function(String trackId);

/// Function signature for the SQLite source of the permanent
/// library. The default implementation queries
/// `PlaylistDatabase.rawQueryDownloadedTracks()`; tests inject a
/// fake that reads from an in-memory FFI database or a hardcoded
/// list.
typedef SqliteSource = Future<List<Map<String, dynamic>>> Function();

/// Aggregate-mined candidate pool for the AI DJ routing layer.
///
/// The crate is the union of two storage tiers plus a strict
/// on-disk existence filter:
///
///   1. **SQLite permanent library** — every row in
///      `downloaded_tracks` whose `filePath` column points at a file
///      that actually exists on the device. Track metadata (title,
///      author) is read from the same row.
///   2. **Hive transient cache** — every `trackId` in
///      `cache_tracker_box` whose resolved audio file path exists on
///      disk. Track metadata is enriched from the most recent row
///      in `dj_listening_history` for that id (Phase 1 ledger), so
///      the routing service can score by genre / artist without a
///      second round-trip per candidate.
///
/// The on-disk filter is the spec's "CRITICAL STEP" — markers in
/// the storage layers can become stale (the user cleared the cache,
/// the OS evicted a background-downloaded file, the SD card was
/// unmounted) and recommending a track whose file is not actually
/// there would cause a playback crash. The miner therefore treats
/// the file existence check as the source of truth and silently
/// drops anything that fails it.
class LocalCrateMiner {
  static const String _logTag = 'LocalCrateMiner';

  /// Maximum number of tracks to return per [mine] call. The routing
  /// service only needs the top-scoring candidate(s) so we cap the
  /// pool to keep the scoring loop bounded.
  final int poolLimit;

  final SqliteSource _sqliteSource;
  final HybridCacheService _hybridCache;
  final DJHistoryLedger? _historyLedger;
  final FileExists _fileExists;
  final HiveAudioPathResolver _hiveAudioPathResolver;

  /// Phase 6: kept as a public-ish field so the synthesis
  /// path inside [_mineFromHive] can consult the SQLite mirror
  /// for a single trackId (the existing [_sqliteSource] is a
  /// `()` → all-rows bulk reader, not a per-id resolver).
  /// Nullable for tests that wire a custom `sqliteSource` only.
  final PlaylistDatabase? libraryDatabase;

  LocalCrateMiner({
    SqliteSource? sqliteSource,
    PlaylistDatabase? libraryDatabase,
    required HybridCacheService hybridCache,
    DJHistoryLedger? historyLedger,
    FileExists? fileExists,
    HiveAudioPathResolver? hiveAudioPathResolver,
    this.poolLimit = 200,
  })  : _sqliteSource = sqliteSource ??
            (libraryDatabase == null
                ? _emptySqliteSource
                : () => libraryDatabase.rawQueryDownloadedTracks()),
        _hybridCache = hybridCache,
        _historyLedger = historyLedger,
        _fileExists = fileExists ?? _defaultFileExists,
        _hiveAudioPathResolver =
            hiveAudioPathResolver ?? _defaultHiveAudioPathResolver,
        libraryDatabase = libraryDatabase;

  static Future<List<Map<String, dynamic>>> _emptySqliteSource() async =>
      const <Map<String, dynamic>>[];

  static Future<bool> _defaultFileExists(String path) async {
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }

  /// Default resolver for Hive-cached audio files. The cache stores
  /// audio under `<docs>/audio_cache/<trackId>.<ext>` where `<ext>`
  /// is one of the known container extensions. We probe each in
  /// order and return the first hit, mirroring the convention the
  /// HybridCacheService eviction pipeline uses.
  static Future<String?> _defaultHiveAudioPathResolver(
      String trackId) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      const candidates = ['m4a', 'mp3', 'aac', 'ogg', 'opus'];
      for (final ext in candidates) {
        final path = '${docs.path}/audio_cache/$trackId.$ext';
        if (await File(path).exists()) return path;
      }
    } catch (_) {
      // path_provider throws on the test VM; treat the whole Hive
      // tier as unavailable rather than letting it bubble.
    }
    return null;
  }

  /// Mines the candidate pool. Returns up to [poolLimit] tracks,
  /// each carrying the best-known genre metadata (from
  /// `dj_listening_history` if available, otherwise null).
  ///
  /// [excludeIds] is applied **after** the file-existence filter so
  /// the result set never includes the currently-playing track or
  /// any of the recently-played session memory list.
  Future<List<Track>> mine({Set<String>? excludeIds}) async {
    final out = <String, Track>{};

    await _mineFromSqlite(out);
    await _mineFromHive(out);

    // Enrich with the most recent known genre for each trackId.
    if (_historyLedger != null) {
      try {
        final recent = await _historyLedger.getRecent(limit: poolLimit * 3);
        for (final row in recent) {
          final t = out[row.trackId];
          if (t == null) continue;
          // Don't overwrite an existing genre with a missing one.
          if (t.genre != null) continue;
          out[row.trackId] = t.copyWith(genre: row.primaryGenre);
        }
      } catch (e) {
        AppLogger.log('Crate genre enrichment failed: $e', name: _logTag);
      }
    }

    // Spec 2E: enrich each track with the artist's ISO 3166-1
    // alpha-2 country code (from `artist_genres.country_code`).
    // Batched single SQL query keyed on the distinct set of
    // normalised authors in the pool — O(1) round-trips
    // regardless of pool size. Failures fall through silently:
    // the bonus service treats `null` countries as "unknown"
    // and returns a neutral 1.0 multiplier, so a missing country
    // never disqualifies a candidate.
    if (libraryDatabase != null) {
      try {
        final distinctAuthors = <String>{};
        for (final t in out.values) {
          final author = t.author?.trim();
          if (author == null || author.isEmpty) continue;
          distinctAuthors.add(author);
        }
        if (distinctAuthors.isNotEmpty) {
          final countryMap = await libraryDatabase!
              .getArtistCountries(distinctAuthors);
          for (final entry in countryMap.entries) {
            if (entry.value == null) continue;
            // The country map key matches the author's
            // *unnormalised* display name (the miner's
            // author set is built from `t.author` directly
            // and the DB stores the unnormalised value in
            // `display_name`/the raw query). The DB query
            // normalises internally; we look up by display
            // name as a defensive secondary pass and fall
            // through if it misses.
            for (final t in out.values) {
              if (t.country != null) continue;
              if (t.author?.trim() == entry.key) {
                out[t.id] = t.copyWith(country: entry.value);
              }
            }
          }
        }
      } catch (e) {
        AppLogger.log('Crate country enrichment failed: $e', name: _logTag);
      }
    }

    var list = out.values.toList();
    if (excludeIds != null && excludeIds.isNotEmpty) {
      list = list.where((t) => !excludeIds.contains(t.id)).toList();
    }
    if (list.length > poolLimit) {
      list = list.sublist(0, poolLimit);
    }
    return list;
  }

  /// Same as [mine] but returns the set of ids only — cheaper when
  /// the caller only needs presence (e.g. to filter a candidate
  /// list against the on-disk pool).
  Future<Set<String>> mineIds({Set<String>? excludeIds}) async {
    final tracks = await mine(excludeIds: excludeIds);
    return tracks.map((t) => t.id).toSet();
  }

  Future<void> _mineFromSqlite(Map<String, Track> out) async {
    try {
      final rows = await _sqliteSource();
      for (final row in rows) {
        final id = row['id'] as String?;
        final filePath = row['filePath'] as String?;
        if (id == null || filePath == null || filePath.isEmpty) continue;
        if (!await _fileExists(filePath)) {
          AppLogger.log(
            'Dropping $id — file not on disk: $filePath',
            name: _logTag,
          );
          continue;
        }
        out[id] = Track(
          id: id,
          title: (row['title'] as String?) ?? 'Unknown',
          author: row['author'] as String?,
          thumbnailUrl: row['thumbnailUrl'] as String?,
          // C1: preserve null rather than coercing to 0 (which
          // would render as `0:00` in the UI). See
          // [formatDuration] for the em-dash fallback.
          duration: (row['durationSeconds'] as int?) == null
              ? null
              : Duration(seconds: row['durationSeconds'] as int),
          genre: row['genre'] as String?,
          // Spec 2F: year is read straight from the row when
          // present (test stubs populate it; production
          // `downloaded_tracks` rows are joined against
          // `track_metadata.year` upstream). The bonus
          // service treats `null` as unknown → neutral, so
          // a missing year never disqualifies a candidate.
          year: row['year'] as int?,
        );
      }
    } catch (e) {
      AppLogger.log('SQLite crate sweep failed: $e', name: _logTag);
    }
  }

  Future<void> _mineFromHive(Map<String, Track> out) async {
    try {
      final cachedIds = _hybridCache.getCachedTrackIds();
      for (final id in cachedIds) {
        if (out.containsKey(id)) continue; // SQLite tier already won.
        final path = await _hiveAudioPathResolver(id);
        if (path == null) continue;
        if (!await _fileExists(path)) {
          AppLogger.log(
            'Dropping Hive $id — file not on disk: $path',
            name: _logTag,
          );
          continue;
        }

        // Tier 2 (defensive): consult the SQLite mirror in
        // case the row was added after `_mineFromSqlite` ran.
        // Cheap; primary-key lookup.
        final db = libraryDatabase;
        if (db != null) {
          try {
            final downloaded = await db.getDownloadedTrack(id);
            if (downloaded != null) {
              out[id] = Track(
                id: id,
                title: (downloaded['title'] as String?) ?? 'Cached Track',
                author: downloaded['author'] as String?,
                thumbnailUrl: downloaded['thumbnailUrl'] as String?,
                // C1: preserve null. See sibling block above.
                duration: (downloaded['durationSeconds'] as int?) == null
                    ? null
                    : Duration(seconds: downloaded['durationSeconds'] as int),
              );
              continue;
            }
          } catch (e) {
            AppLogger.log(
              '_mineFromHive: SQLite tier lookup failed for $id: $e',
              name: _logTag,
            );
          }
        }

        // Tier 3: Hive tracker entry (display metadata when
        // populated). The Hive tracker does not carry a
        // duration field, so the synthesised Track reports
        // `null` (the C1 "unknown" sentinel) — the UI renders
        // it as `—:—` via [formatDuration]. C3 contract: no
        // `Duration.zero` leak in the synthesis paths.
        final hiveEntry = _hybridCache.getTrackerEntry(id);
        if (hiveEntry != null && hiveEntry.title != null) {
          out[id] = Track(
            id: id,
            title: hiveEntry.title!,
            author: hiveEntry.author,
            thumbnailUrl: hiveEntry.thumbnailUrl,
            duration: null,
          );
          continue;
        }

        // Final fallback: stub. Unknown in every dimension;
        // duration is `null` not `Duration.zero` for the
        // same reason as the Hive branch above. Per C1,
        // "no metadata" must not be mis-rendered as
        // "0 seconds long".
        out[id] = Track(
          id: id,
          title: 'Cached Track',
          duration: null,
        );
      }
    } catch (e) {
      AppLogger.log('Hive crate sweep failed: $e', name: _logTag);
    }
  }
}
