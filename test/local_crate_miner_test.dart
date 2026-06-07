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
import 'package:zyp_music/data/models/cache_tracker_model.dart';

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

  // ---------------------------------------------------------------------
  // C3 — null duration propagation regression coverage
  //
  // The synthesis paths in [LocalCrateMiner._mineFromSqlite] /
  // [LocalCrateMiner._mineFromHive] / [LocalCrateMiner._mineFromHive]
  // (Hive tier + stub fallback) must propagate `null` for the
  // "unknown" sentinel rather than coercing to `Duration.zero`
  // (which would render as `0:00` in the UI and contradict the
  // C1 honest-nulls invariant). The Hive tracker record has no
  // duration field at all, so any branch that synthesises a Track
  // from Hive alone must report `duration: null`.
  // ---------------------------------------------------------------------
  group('LocalCrateMiner C3 null-duration propagation', () {
    test('SQLite row with null durationSeconds yields Track(duration: null)',
        () async {
      final realFile = File(p.join(tempDir.path, 'live.m4a'))
        ..writeAsBytesSync([]);
      final miner = LocalCrateMiner(
        sqliteSource: () async => [
          {
            'id': 'live',
            'title': 'Live Stream',
            'filePath': realFile.path,
            // SQLite column is nullable (Phase 2/C1). Live streams
            // and unlisted videos have no API-supplied duration.
            'durationSeconds': null,
            'author': 'YouTube',
          },
        ],
        hybridCache: _FakeHybridCache(const []),
      );
      final crate = await miner.mine();
      expect(crate, hasLength(1));
      expect(crate.first.duration, isNull);
    });

    test('SQLite row with finite duration propagates Duration(seconds: x)',
        () async {
      final realFile = File(p.join(tempDir.path, 'normal.m4a'))
        ..writeAsBytesSync([]);
      final miner = LocalCrateMiner(
        sqliteSource: () async => [
          {
            'id': 'normal',
            'title': 'Normal',
            'filePath': realFile.path,
            'durationSeconds': 213,
            'author': 'A',
          },
        ],
        hybridCache: _FakeHybridCache(const []),
      );
      final crate = await miner.mine();
      expect(crate.first.duration, const Duration(seconds: 213));
    });

    test('Hive-tier synthesis reports duration: null (no Duration.zero leak)',
        () async {
      // A Hive tracker entry has title/author/thumbnailUrl but
      // no duration field — so the synthesised Track's duration
      // must be `null`. Pre-C3 this was `Duration.zero`, which
      // would have rendered as `0:00` and broken the C1
      // "unknown = `—:—`" UI contract.
      final fakeFile = File(p.join(tempDir.path, 'cached.m4a'))
        ..writeAsBytesSync([]);
      final hiveEntry = CacheTrackerModel(
        trackId: 'hive-only',
        cachedAt: 0,
        title: 'Hive-only Track',
        author: 'Hive Author',
        thumbnailUrl: 'http://example.com/t.jpg',
      );
      final miner = LocalCrateMiner(
        sqliteSource: () async => const <Map<String, dynamic>>[],
        hybridCache: _FakeHybridCache.withEntries({'hive-only': hiveEntry}),
        fileExists: (path) async => path == fakeFile.path,
        hiveAudioPathResolver: (_) async => fakeFile.path,
      );
      final crate = await miner.mine();
      expect(crate, hasLength(1));
      expect(crate.first.title, 'Hive-only Track');
      expect(crate.first.duration, isNull,
          reason: 'Hive branch must not leak Duration.zero');
    });

    test('stub fallback (no SQLite, no Hive metadata) reports duration: null',
        () async {
      // The final fallback synthesises a `'Cached Track'` stub
      // when neither the SQLite mirror nor the Hive tracker
      // have a populated title. Pre-C3 the stub's duration was
      // `Duration.zero`; post-C3 it is `null` (C1 "unknown").
      final fakeFile = File(p.join(tempDir.path, 'stub.m4a'))
        ..writeAsBytesSync([]);
      final miner = LocalCrateMiner(
        sqliteSource: () async => const <Map<String, dynamic>>[],
        hybridCache: _FakeHybridCache(const ['stub-id']),
        // Hive tracker entry is present but `title` is null —
        // falls through to the stub branch.
        fileExists: (path) async => path == fakeFile.path,
        hiveAudioPathResolver: (_) async => fakeFile.path,
      );
      final crate = await miner.mine();
      expect(crate, hasLength(1));
      expect(crate.first.title, 'Cached Track');
      expect(crate.first.duration, isNull,
          reason: 'Stub fallback must not leak Duration.zero');
    });
  });
}

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class _FakeHybridCache extends HybridCacheService {
  final List<String> _ids;
  final Map<String, CacheTrackerModel> _entries;
  _FakeHybridCache(this._ids) : _entries = const {};

  /// Construct a fake that also satisfies `getTrackerEntry`
  /// lookups for the Hive-tier synthesis tests.
  _FakeHybridCache.withEntries(Map<String, CacheTrackerModel> entries)
      : _ids = entries.keys.toList(),
        _entries = entries;

  @override
  List<String> getCachedTrackIds() => _ids;

  @override
  CacheTrackerModel? getTrackerEntry(String trackId) => _entries[trackId];
}
