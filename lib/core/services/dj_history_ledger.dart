import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/datasources/local/playlist_database.dart';
import '../utils/app_logger.dart';

/// Single row in the `dj_listening_history` ledger. Mirrors the
/// SQLite schema 1:1 so the field names read as raw DB columns when
/// debugging. Defaults follow the SQL DEFAULT clauses so a row
/// constructed in Dart and one read back from SQLite always agree.
class DJHistoryEntry {
  final int? id;
  final String trackId;
  final String artistName;
  final String primaryGenre;
  final double bpm;
  final double energyLevel;
  final int timestampMs;

  const DJHistoryEntry({
    this.id,
    required this.trackId,
    required this.artistName,
    this.primaryGenre = 'Unknown',
    this.bpm = 0.0,
    this.energyLevel = 0.5,
    required this.timestampMs,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'track_id': trackId,
        'artist_name': artistName,
        'primary_genre': primaryGenre,
        'bpm': bpm,
        'energy_level': energyLevel,
        'timestamp': timestampMs,
      };

  factory DJHistoryEntry.fromMap(Map<String, Object?> m) => DJHistoryEntry(
        id: m['id'] as int?,
        trackId: m['track_id'] as String,
        artistName: m['artist_name'] as String,
        primaryGenre: (m['primary_genre'] as String?) ?? 'Unknown',
        bpm: (m['bpm'] as num?)?.toDouble() ?? 0.0,
        energyLevel: (m['energy_level'] as num?)?.toDouble() ?? 0.5,
        timestampMs: m['timestamp'] as int,
      );
}

/// Thin wrapper over the `dj_listening_history` SQLite table. Owns:
///
/// * 80% playback logging (non-blocking, de-duplicated per session)
/// * 300-row ledger trim (delete oldest 10 once the cap is exceeded)
/// * Cold-start fallback (rows < 3 → genre match → random)
/// * Markov-engine corpus query (all rows, ordered by timestamp DESC)
///
/// All write paths funnel through [logTrack] so the trim invariant
/// is enforced exactly once per insert, atomically with the insert
/// itself, in a single SQLite transaction. Tests that exercise this
/// class construct it with a fresh in-memory [Database] via
/// `sqflite_common_ffi`; production code wires it to the shared
/// singleton [PlaylistDatabase].
class DJHistoryLedger {
  static const String _logTag = 'DJHistoryLedger';
  static const int _ledgerCap = 300;
  static const int _trimBatch = 10;
  static const int _minRowsForMarkov = 3;

  /// In-memory set of track IDs already logged during the current
  /// process lifetime. The 80% rule fires once per (session, track)
  /// pair — a re-play of the same track on a future day would land
  /// a fresh row.
  final Set<String> _loggedThisSession = <String>{};

  /// Optional RNG for the cold-start random fallback. Injected via
  /// the constructor so unit tests can use a [Random(0)] for
  /// deterministic assertions.
  final Random _rng;

  /// The minimum number of rows required before the Markov engine
  /// can compute valid transition probabilities. Exposed for tests
  /// and for Phase 2 callers that need to gate the engine on data
  /// availability.
  static int get minRowsForMarkov => _minRowsForMarkov;

  /// Public so the validation-gate tests can assert on the cap.
  static int get ledgerCap => _ledgerCap;
  static int get trimBatch => _trimBatch;

  DJHistoryLedger(this._db, {Random? rng}) : _rng = rng ?? Random();

  /// Returns a fully-initialised ledger bound to the shared
  /// [PlaylistDatabase]. Use this in production code (e.g. from
  /// `main.dart` / `MultiProvider`).
  static Future<DJHistoryLedger> create() async {
    final db = await PlaylistDatabase().database;
    return DJHistoryLedger(db);
  }

  final Database _db;

  /// True iff [trackId] has already been logged this process. Public
  /// so [PlayerProvider] can implement the "fire once per session"
  /// guard without poking at the private set.
  bool hasBeenLoggedThisSession(String trackId) =>
      _loggedThisSession.contains(trackId);

  /// Clears the in-session dedupe set. Tests call this between
  /// cases; production code never needs to.
  @visibleForTesting
  void clearSessionCache() => _loggedThisSession.clear();

  /// Inserts [entry] into the ledger and runs the trim invariant
  /// in the same transaction. Returns the auto-generated row id.
  ///
  /// The trim is intentionally bounded: the cap is [_ledgerCap]
  /// (300) and the over-shoot is always exactly [_trimBatch] (10)
  /// rows, mirroring the
  /// `DELETE ... WHERE id IN (SELECT ... ORDER BY timestamp ASC LIMIT 10)`
  /// query in the spec. Exposed publicly so the unit tests can
  /// drive it without going through the position monitor.
  Future<int> logTrack(DJHistoryEntry entry) async {
    return _db.transaction<int>((txn) async {
      final id = await txn.insert(
        'dj_listening_history',
        entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final count = Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM dj_listening_history'),
          ) ??
          0;
      if (count > _ledgerCap) {
        await txn.rawDelete(
          'DELETE FROM dj_listening_history '
          'WHERE id IN ('
          'SELECT id FROM dj_listening_history '
          'ORDER BY timestamp ASC LIMIT ?'
          ')',
          [_trimBatch],
        );
      }
      _loggedThisSession.add(entry.trackId);
      return id;
    });
  }

  /// Reads every row in the ledger, newest first. Cheap on an
  /// indexed 300-row table; the Markov engine consumes the full
  /// list when it computes transition probabilities.
  Future<List<DJHistoryEntry>> getAll() async {
    final rows = await _db.query(
      'dj_listening_history',
      orderBy: 'timestamp DESC',
    );
    return rows.map(DJHistoryEntry.fromMap).toList();
  }

  /// Returns the most recent N entries. Convenience wrapper for
  /// the Markov engine's "sliding window" usage.
  Future<List<DJHistoryEntry>> getRecent({int limit = 50}) async {
    final rows = await _db.query(
      'dj_listening_history',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(DJHistoryEntry.fromMap).toList();
  }

  /// Returns the current row count. Used by the cold-start fallback
  /// to decide whether to consult the Markov engine or fall through
  /// to genre match / random.
  Future<int> rowCount() async {
    final result = await _db
        .rawQuery('SELECT COUNT(*) FROM dj_listening_history');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Wipes the ledger. Test-only — production code should never
  /// need to nuke history.
  @visibleForTesting
  Future<void> clearAll() async {
    await _db.delete('dj_listening_history');
    _loggedThisSession.clear();
  }

  /// Cold-start fallback. The Markov engine needs at least
  /// [minRowsForMarkov] rows of history before its transition
  /// probabilities are well-defined. On a fresh install the table
  /// is empty and the engine would throw. The fallback chain is:
  ///
  ///   1. If the table already has ≥ [minRowsForMarkov] rows, the
  ///      engine can run; return [ColdStartOutcome.markovReady].
  ///   2. Otherwise, ask the [localLibrary] for a track whose
  ///      `primaryGenre` matches [seedGenre]. If one is available
  ///      return it via [ColdStartOutcome.genreMatch].
  ///   3. If no genre match exists, return a random track from
  ///      the local library via [ColdStartOutcome.randomFallback].
  ///   4. If the local library is itself empty, return
  ///      [ColdStartOutcome.empty].
  ///
  /// The [localLibrary] parameter is intentionally a closure so
  /// this class stays decoupled from the rest of the app — the
  /// host wires it to whatever local-library source the project
  /// already has (the cache manifest, the playlists table, or the
  /// downloaded-tracks table). The returned `TrackCandidate` is
  /// whatever the resolver hands back; this layer does not
  /// interpret it.
  Future<ColdStartOutcome> resolveColdStart({
    required String? seedGenre,
    required List<TrackCandidate> Function(String? genre)
        localLibrary,
  }) async {
    final count = await rowCount();
    if (count >= _minRowsForMarkov) {
      AppLogger.log(
        'Cold-start: Markov ready (rows=$count)',
        name: _logTag,
      );
      return ColdStartOutcome.markovReady(rowCount: count);
    }
    final matches = localLibrary(seedGenre);
    if (matches.isNotEmpty) {
      final pick = matches.first;
      AppLogger.log(
        'Cold-start: genre match (\'${pick.primaryGenre}\') → ${pick.trackId}',
        name: _logTag,
      );
      return ColdStartOutcome.genreMatch(pick);
    }
    // No genre match — fall back to a random track from the same
    // resolver, minus the same-genre filter so the random pool is
    // the entire local library.
    final pool = localLibrary(null);
    if (pool.isEmpty) {
      AppLogger.log('Cold-start: empty library', name: _logTag);
      return ColdStartOutcome.empty();
    }
    final pick = pool[_rng.nextInt(pool.length)];
    AppLogger.log(
      'Cold-start: random fallback → ${pick.trackId}',
      name: _logTag,
    );
    return ColdStartOutcome.randomFallback(pick);
  }
}

/// Lightweight, engine-agnostic description of a track the cold-start
/// fallback can hand to the host. Avoids a hard dependency on the
/// [Track] entity so the ledger stays unit-testable in isolation.
class TrackCandidate {
  final String trackId;
  final String artistName;
  final String primaryGenre;

  const TrackCandidate({
    required this.trackId,
    required this.artistName,
    this.primaryGenre = 'Unknown',
  });
}

/// Sealed-ish result type for [DJHistoryLedger.resolveColdStart].
/// Discriminated by the [kind] field so the host can `switch` on it.
class ColdStartOutcome {
  final ColdStartKind kind;
  final TrackCandidate? pick;
  final int rowCount;

  const ColdStartOutcome._(this.kind, this.pick, this.rowCount);

  factory ColdStartOutcome.markovReady({required int rowCount}) =>
      ColdStartOutcome._(ColdStartKind.markovReady, null, rowCount);
  factory ColdStartOutcome.genreMatch(TrackCandidate pick) =>
      ColdStartOutcome._(ColdStartKind.genreMatch, pick, 0);
  factory ColdStartOutcome.randomFallback(TrackCandidate pick) =>
      ColdStartOutcome._(ColdStartKind.randomFallback, pick, 0);
  factory ColdStartOutcome.empty() =>
      const ColdStartOutcome._(ColdStartKind.empty, null, 0);
}

enum ColdStartKind { markovReady, genreMatch, randomFallback, empty }
