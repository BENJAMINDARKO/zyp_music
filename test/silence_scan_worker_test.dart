// Phase 3 — Silence Scan Worker + track_metadata table.
// Validation gate coverage: "Verify via SQL inspectors that your
// background SilenceScanWorker successfully populates valid
// millisecond values inside the track_metadata tables."

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:zyp_music/core/audio/silence_scan_worker.dart';
import 'package:zyp_music/data/datasources/local/playlist_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // The PlaylistDatabase singleton uses a hard-coded
  // `getDatabasesPath()` path which throws in the test VM. To
  // exercise the DAO methods without the singleton, we use
  // a thin test wrapper that exposes the same surface against
  // an in-memory FFI database.
  group('SilenceScanWorker (in-memory FFI)', () {
    test('scanAndPersist writes a finite millisecond value to track_metadata',
        () async {
      // 1. Spin up a fresh in-memory database with the
      //    track_metadata schema the worker needs.
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE track_metadata (
                track_id          TEXT PRIMARY KEY,
                silence_start_ms  INTEGER DEFAULT NULL,
                scanned_at        INTEGER NOT NULL
              )
            ''');
          },
        ),
      );

      // 2. Wrap it in a test playlist database.
      final playlistDb = _TestPlaylistDatabase(db);

      // 3. Build a fake "compressed" file (a few bytes — the
      //    test VM has no codec so the scanner takes the
      //    heuristic path).
      final tmp = Directory.systemTemp.createTempSync('zyp_scan_');
      final file = File('${tmp.path}/sample.bin')..writeAsBytesSync([1, 2, 3]);
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      // 4. Run the worker.
      final worker = SilenceScanWorker(playlistDb);
      final ms = await worker.scanAndPersist('track1', file.path);
      expect(ms, isNotNull);
      expect(ms, greaterThan(0));

      // 5. SQL-inspector style assertion: read the row back.
      final row = await playlistDb.getTrackMetadata('track1');
      expect(row, isNotNull);
      expect(row!['track_id'], 'track1');
      expect(row['silence_start_ms'], ms);
      expect(row['scanned_at'], isA<int>());
      expect((row['scanned_at'] as int) > 0, isTrue);

      await db.close();
    });

    test('re-scanning the same track overwrites the previous row', () async {
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE track_metadata (
                track_id          TEXT PRIMARY KEY,
                silence_start_ms  INTEGER DEFAULT NULL,
                scanned_at        INTEGER NOT NULL
              )
            ''');
          },
        ),
      );
      final playlistDb = _TestPlaylistDatabase(db);
      final tmp = Directory.systemTemp.createTempSync('zyp_scan_');
      final file = File('${tmp.path}/sample.bin')..writeAsBytesSync([1, 2, 3]);
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final worker = SilenceScanWorker(playlistDb);
      await worker.scanAndPersist('track2', file.path);
      final firstScannedAt = (await playlistDb.getTrackMetadata('track2'))!
          .cast<String, Object?>()['scanned_at'] as int;
      // Wait > 1ms so the second scan's timestamp differs.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await worker.scanAndPersist('track2', file.path);
      final second = await playlistDb.getTrackMetadata('track2');
      expect(second!['scanned_at'] as int, greaterThan(firstScannedAt));

      await db.close();
    });

    test('silence-scan scheduler enqueue is fire-and-forget', () async {
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE track_metadata (
                track_id          TEXT PRIMARY KEY,
                silence_start_ms  INTEGER DEFAULT NULL,
                scanned_at        INTEGER NOT NULL
              )
            ''');
          },
        ),
      );
      final playlistDb = _TestPlaylistDatabase(db);
      final tmp = Directory.systemTemp.createTempSync('zyp_scan_sched_');
      final file = File('${tmp.path}/sample.bin')..writeAsBytesSync([1]);
      addTearDown(() {
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final scheduler = SilenceScanScheduler(SilenceScanWorker(playlistDb));
      // Two rapid enqueues for the same trackId should be
      // debounced — the second is dropped while the first is
      // in flight.
      scheduler.enqueue('dup', file.path);
      scheduler.enqueue('dup', file.path);
      // Give the worker time to finish.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final row = await playlistDb.getTrackMetadata('dup');
      expect(row, isNotNull);
      await db.close();
    });
  });
}

// ---------------------------------------------------------------------------
// Test double
// ---------------------------------------------------------------------------

class _TestPlaylistDatabase implements PlaylistDatabase {
  final Database _raw;
  _TestPlaylistDatabase(this._raw);

  @override
  Future<int?> getSilenceStartMs(String trackId) async {
    final rows = await _raw.query('track_metadata',
        columns: ['silence_start_ms'],
        where: 'track_id = ?',
        whereArgs: [trackId],
        limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['silence_start_ms'] as int?;
  }

  @override
  Future<void> upsertTrackMetadata(
      String trackId, int? silenceStartMs) async {
    await _raw.insert('track_metadata', {
      'track_id': trackId,
      'silence_start_ms': silenceStartMs,
      'scanned_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<Map<String, Object?>?> getTrackMetadata(String trackId) async {
    final rows = await _raw.query('track_metadata',
        where: 'track_id = ?',
        whereArgs: [trackId],
        limit: 1);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Test fake: ${invocation.memberName}');
}
