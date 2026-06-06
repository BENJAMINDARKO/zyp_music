// Phase 2 — Local Crate Miner
// Validation gate coverage: the spec's "CRITICAL STEP" — the
// on-disk existence filter. Every track whose file does not
// physically reside on the device must be dropped from the crate.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import 'package:zyp_music/core/services/hybrid_cache_service.dart';
import 'package:zyp_music/core/services/local_crate_miner.dart';

void main() {
  setUpAll(() {
    // Hive needs a temp dir on the host VM; we point it at a
    // per-run scratch directory to keep tests isolated. The crate
    // miner's Hive tier is exercised through the fake hybrid
    // cache (we don't actually need a populated box), but the
    // Hive init is required for the import graph to load.
    Hive.init(Directory.systemTemp
        .createTempSync('zyp_crate_hive_')
        .path);
  });

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('zyp_crate_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('LocalCrateMiner.file-existence filter', () {
    test('drops SQLite rows whose filePath does not exist on disk',
        () async {
      final realFile = File(p.join(tempDir.path, 'real.m4a'))
        ..writeAsBytesSync([]);
      final miner = LocalCrateMiner(
        sqliteSource: () async => [
          {
            'id': 'real',
            'title': 'Real',
            'filePath': realFile.path,
            'durationSeconds': 100,
            'author': 'A',
          },
          {
            'id': 'stale',
            'title': 'Stale',
            'filePath': '/no/such/path.m4a',
            'durationSeconds': 100,
            'author': 'B',
          },
        ],
        hybridCache: _FakeHybridCache(const []),
        hiveAudioPathResolver: (_) async => null,
      );
      final crate = await miner.mine();
      expect(crate.map((t) => t.id).toSet(), {'real'});
    });

    test('drops Hive entries whose resolved audio file does not exist',
        () async {
      final fakeFile = File(p.join(tempDir.path, 'cached.m4a'))
        ..writeAsBytesSync([]);
      final miner = LocalCrateMiner(
        sqliteSource: () async => const <Map<String, dynamic>>[],
        hybridCache: _FakeHybridCache(const ['present', 'absent']),
        fileExists: (path) async => path == fakeFile.path,
        hiveAudioPathResolver: (id) async =>
            id == 'present' ? fakeFile.path : null,
      );
      final crate = await miner.mine();
      expect(crate.map((t) => t.id).toSet(), {'present'});
    });

    test('union of SQLite + Hive survives with deduplication', () async {
      final realFile = File(p.join(tempDir.path, 'real.m4a'))
        ..writeAsBytesSync([]);
      final miner = LocalCrateMiner(
        sqliteSource: () async => [
          {
            'id': 'a',
            'title': 'A',
            'filePath': realFile.path,
            'durationSeconds': 100,
            'author': 'X',
          },
          // 'shared' exists in both tiers; SQLite should win.
          {
            'id': 'shared',
            'title': 'Shared (sqlite)',
            'filePath': realFile.path,
            'durationSeconds': 100,
            'author': 'Y',
          },
        ],
        hybridCache: _FakeHybridCache(const ['shared', 'hive-only']),
        fileExists: (path) async => path == realFile.path,
        hiveAudioPathResolver: (_) async => realFile.path,
      );
      final crate = await miner.mine();
      final ids = crate.map((t) => t.id).toSet();
      expect(ids, {'a', 'shared', 'hive-only'});
      // SQLite tier wins ties: 'shared' keeps the SQLite title.
      final shared = crate.firstWhere((t) => t.id == 'shared');
      expect(shared.title, 'Shared (sqlite)');
    });

    test('excludeIds filter is applied after the file filter', () async {
      final f1 = File(p.join(tempDir.path, 'a.m4a'))..writeAsBytesSync([]);
      final f2 = File(p.join(tempDir.path, 'b.m4a'))..writeAsBytesSync([]);
      final miner = LocalCrateMiner(
        sqliteSource: () async => [
          {
            'id': 'a',
            'title': 'A',
            'filePath': f1.path,
            'durationSeconds': 100,
            'author': 'A',
          },
          {
            'id': 'b',
            'title': 'B',
            'filePath': f1.path,
            'durationSeconds': 100,
            'author': 'B',
          },
          {
            'id': 'c',
            'title': 'C',
            'filePath': f2.path,
            'durationSeconds': 100,
            'author': 'C',
          },
        ],
        hybridCache: _FakeHybridCache(const []),
      );
      final crate = await miner.mine(excludeIds: {'a', 'b'});
      expect(crate.map((t) => t.id).toSet(), {'c'});
    });

    test('returns empty list when no rows pass the file filter',
        () async {
      final miner = LocalCrateMiner(
        sqliteSource: () async => [
          {
            'id': 'gone1',
            'title': 'G1',
            'filePath': '/no/such/g1.m4a',
            'durationSeconds': 100,
            'author': 'G',
          },
          {
            'id': 'gone2',
            'title': 'G2',
            'filePath': '/no/such/g2.m4a',
            'durationSeconds': 100,
            'author': 'G',
          },
        ],
        hybridCache: _FakeHybridCache(const []),
      );
      expect(await miner.mine(), isEmpty);
    });

    test('gracefully degrades when sqlite source throws', () async {
      final miner = LocalCrateMiner(
        sqliteSource: () async => throw StateError('db locked'),
        hybridCache: _FakeHybridCache(const []),
      );
      // Should not throw — the catch in _mineFromSqlite swallows
      // and returns an empty pool.
      final crate = await miner.mine();
      expect(crate, isEmpty);
    });

    test('gracefully degrades when hive resolver throws', () async {
      final miner = LocalCrateMiner(
        sqliteSource: () async => const <Map<String, dynamic>>[],
        hybridCache: _FakeHybridCache(const ['t1']),
        fileExists: (path) async => true,
        hiveAudioPathResolver: (_) async =>
            throw StateError('resolver down'),
      );
      final crate = await miner.mine();
      expect(crate, isEmpty);
    });
  });
}

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class _FakeHybridCache extends HybridCacheService {
  final List<String> _ids;
  _FakeHybridCache(this._ids);

  @override
  List<String> getCachedTrackIds() => _ids;
}
