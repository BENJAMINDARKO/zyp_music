import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/datasources/local/playlist_database.dart';
import '../../data/models/cache_tracker_model.dart';
import '../utils/app_logger.dart';

/// One-time migration that hydrates the Phase 6 display-metadata
/// fields (`title` / `author` / `thumbnailUrl`) on existing
/// [CacheTrackerModel] entries from the SQLite `downloaded_tracks`
/// mirror.
///
/// **Why a migration is needed.** The Phase 6 cached-metadata
/// spec adds three nullable fields to the [CacheTrackerModel]
/// Hive type. Records written before this version of the app
/// ship with `null` for all three. The synthesis paths in
/// `QueueManager._buildTrackFromId` and
/// `LocalCrateMiner._mineFromHive` consult the Hive tier as a
/// fallback when the SQLite tier misses — without a backfill,
/// those paths would return the legacy `'Cached Track'` stub
/// for every track that was cached before the upgrade, even
/// when the SQLite mirror has the full row.
///
/// **Why a flag.** The migration is idempotent (the inner
/// `title` null-check skips entries that already have display
/// metadata) so re-running it is safe. We still gate it on a
/// `SharedPreferences` flag so a 200-entry Hive box does not
/// have to be scanned on every launch. The flag uses a
/// versioned key (`_v1_`) so a future Phase-7 metadata
/// backfill can use `_v2_` and run independently.
///
/// **Failure handling.** If the migration throws partway
/// through (database corruption, disk full, etc.), the flag is
/// not set, and the migration retries on the next launch. The
/// per-entry `title` null-check ensures already-hydrated
/// entries are not re-processed; partial progress is preserved
/// and the migration eventually completes on a subsequent
/// launch when the underlying issue is resolved.
class CacheMetadataBackfill {
  static const String _logTag = 'CacheMetadataBackfill';

  /// Versioned flag key. Bump to `_v2_` (etc.) if a future
  /// Phase adds a fourth display-metadata field that also
  /// needs backfill — the new migration can then run
  /// independently without re-processing the entries that
  /// v1 already hydrated.
  static const String _completedFlag = 'cache_metadata_backfill_v1_done';

  final Box<CacheTrackerModel> _trackerBox;
  final PlaylistDatabase _database;

  CacheMetadataBackfill({
    required Box<CacheTrackerModel> trackerBox,
    required PlaylistDatabase database,
  })  : _trackerBox = trackerBox,
        _database = database;

  /// Runs the migration once. Idempotent — safe to call on
  /// every app start; the flag check makes subsequent calls
  /// no-ops.
  Future<void> runIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_completedFlag) ?? false) {
      return;
    }

    int hydrated = 0;
    int skippedAlreadyPopulated = 0;
    int skippedNoSqliteMirror = 0;

    for (final key in _trackerBox.keys) {
      final entry = _trackerBox.get(key);
      if (entry == null) continue;

      // Idempotency: skip entries that already have display
      // metadata. This is what makes partial progress
      // resumable across failed launches.
      if (entry.title != null && entry.title!.isNotEmpty) {
        skippedAlreadyPopulated++;
        continue;
      }

      // Look up the SQLite mirror. A miss here is the
      // normal case for gapless pre-buffer tracks that
      // never made it into the permanent library — the
      // track was cached in Hive but has no SQLite row to
      // hydrate from. Those entries stay with
      // `title = null` and fall through to the
      // `'Cached Track'` stub at synthesis time, which is
      // the same behaviour as before the backfill was
      // written. Acceptable.
      final downloaded = await _database.getDownloadedTrack(entry.trackId);
      if (downloaded == null) {
        skippedNoSqliteMirror++;
        continue;
      }

      final hydratedEntry = entry.copyWith(
        title: downloaded['title'] as String?,
        author: downloaded['author'] as String?,
        thumbnailUrl: downloaded['thumbnailUrl'] as String?,
      );
      await _trackerBox.put(entry.trackId, hydratedEntry);
      hydrated++;
    }

    await prefs.setBool(_completedFlag, true);
    AppLogger.log(
      'CacheMetadataBackfill v1 complete: '
      'hydrated=$hydrated skippedAlreadyPopulated=$skippedAlreadyPopulated '
      'skippedNoSqliteMirror=$skippedNoSqliteMirror',
      name: _logTag,
    );
  }
}
