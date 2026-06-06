import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../../data/datasources/local/playlist_database.dart';
import '../utils/app_logger.dart';
import 'silence_scanner.dart';

/// Background worker that scans a track's audio file for the
/// silence boundary and writes the result to the
/// `track_metadata.silence_start_ms` column. The Dart equivalent
/// of the spec's `CoroutineWorker` is `Isolate.run` — the work
/// runs off the platform thread so the live audio render path
/// is never blocked by RMS calculations.
///
/// ## Lifecycle
///
///   1. The cache-commit hook (HybridCacheService or
///      PlaylistDatabase.markTrackDownloaded) constructs a
///      `SilenceScanJob` with the trackId + filePath and calls
///      [SilenceScanScheduler.enqueue].
///   2. The scheduler spawns a one-shot isolate via
///      [Isolate.run] which calls [SilenceScanner.scan].
///   3. The isolate's return value is the silence boundary in
///      milliseconds (or null if the file was unreadable).
///   4. The scheduler re-opens the [PlaylistDatabase] on the
///      main isolate and calls `upsertTrackMetadata`.
///
/// The worker is fire-and-forget from the caller's perspective:
/// enqueueing does not block the cache commit, and scan errors
/// are logged but never propagated. The spec calls this out as
/// the "offline pre-computed silence scanner" — heavy work off
/// the critical audio render path.
class SilenceScanWorker {
  static const String _logTag = 'SilenceScanWorker';

  final PlaylistDatabase _db;

  SilenceScanWorker(this._db);

  /// Synchronously scans [filePath] for [trackId] in a Dart
  /// isolate and writes the result to the database.
  ///
  /// Returns the scanned millisecond value (for testing) or
  /// `null` if the file was unreadable.
  Future<int?> scanAndPersist(String trackId, String filePath) async {
    AppLogger.log(
      'SilenceScanWorker.start trackId=$trackId path=$filePath',
      name: _logTag,
    );
    final silenceStartMs = await Isolate.run(() async {
      // The isolate entry-point cannot capture non-static
      // closures, so we re-derive the result here via the
      // pure [SilenceScanner.scan] function. The file IO
      // and RMS work happens off the main thread.
      return await SilenceScanner.scan(filePath);
    });
    if (silenceStartMs == null) {
      AppLogger.log(
        'SilenceScanWorker: file unreadable, skipping write: $filePath',
        name: _logTag,
      );
      return null;
    }
    await _db.upsertTrackMetadata(trackId, silenceStartMs);
    AppLogger.log(
      'SilenceScanWorker.done trackId=$trackId silenceMs=$silenceStartMs',
      name: _logTag,
    );
    return silenceStartMs;
  }
}

/// Hook for the cache-commit + download-commit code paths.
/// Holds a single [SilenceScanWorker] bound to the shared
/// [PlaylistDatabase] and exposes a fire-and-forget
/// [enqueue] method that callers invoke from
/// HybridCacheService.markCaching completion and from
/// PlaylistDatabase.markTrackDownloaded.
///
/// The scheduler is intentionally idempotent: re-enqueuing the
/// same trackId+filePath pair (which can happen if both hooks
/// fire for the same track) is safe; the worker overwrites the
/// previous row via the `upsert` SQL clause.
class SilenceScanScheduler {
  static const String _logTag = 'SilenceScanScheduler';

  final SilenceScanWorker _worker;

  /// In-flight track ids, used to debounce duplicate enqueues
  /// for the same track within a single session. The set is
  /// bounded by the size of the local library in practice; the
  /// OS isolate cap is the actual ceiling.
  final Set<String> _inFlight = <String>{};

  SilenceScanScheduler(this._worker);

  /// Builds a scheduler bound to the shared [PlaylistDatabase]
  /// singleton. Use this in production code (from `main.dart`).
  static Future<SilenceScanScheduler> create() async {
    final db = PlaylistDatabase();
    // Open the database eagerly so the worker has a handle.
    await db.database;
    return SilenceScanScheduler(SilenceScanWorker(db));
  }

  /// Schedules a silence scan for [trackId]. Fire-and-forget;
  /// returns immediately. Errors are logged but never thrown.
  void enqueue(String trackId, String filePath) {
    if (_inFlight.contains(trackId)) return;
    _inFlight.add(trackId);
    unawaited(_run(trackId, filePath));
  }

  Future<void> _run(String trackId, String filePath) async {
    try {
      // Defensive: re-check the file in the main isolate in
      // case it was deleted between the enqueue call and the
      // worker pickup.
      if (!await File(filePath).exists()) {
        AppLogger.log(
          'SilenceScanScheduler: file vanished before scan: $filePath',
          name: _logTag,
        );
        return;
      }
      await _worker.scanAndPersist(trackId, filePath);
    } catch (e) {
      AppLogger.log(
        'SilenceScanScheduler: scan failed for $trackId: $e',
        name: _logTag,
      );
    } finally {
      _inFlight.remove(trackId);
    }
  }
}
