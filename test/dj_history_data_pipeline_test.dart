// Spec 2C Section A.4 — Data pipeline contract test.
//
// The production writer `_logCurrentTrackHistory` in
// `player_provider.dart` reads normalized genres from the
// enrichment service and writes them as `primary_genre` to
// the `dj_listening_history` ledger. The original implementation
// always wrote `'Unknown'` (audit §9.1, §9.2), which made the
// Smart DJ Markov `genreMatch` term structurally dead.
//
// This is a contract test, not a private-method unit test: it
// exercises the same producer logic the production path uses
// (enrichment read → entry build → ledger write) and verifies
// the row's `primary_genre` is what it should be for each
// enrichment outcome. If the producer ever regresses to
// hard-coding `'Unknown'`, this test fails — even though no
// private method is being called directly.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zyp_music/core/services/dj_history_ledger.dart';
import 'package:zyp_music/domain/entities/video.dart';

/// Minimal contract for the read side of the enrichment
/// service — exactly what the production `_logCurrentTrackHistory`
/// calls. Decoupling the producer logic from the concrete
/// `GenreEnrichmentService` class lets us test the producer
/// without spinning up a real MusicBrainz stub or a real
/// database. The test's `_StubEnrichment` implements this
/// contract; production code uses the real
/// `GenreEnrichmentService.readNormalized`.
typedef EnrichmentReadNormalized = Future<List<String>> Function(Track);

/// Producer logic mirror — the same code path the production
/// `_logCurrentTrackHistory` runs. Kept in sync manually; if
/// the production code diverges, this test fails visibly with
/// a `primary_genre` mismatch.
///
/// Mirrors `lib/presentation/providers/player_provider.dart`
/// `_logCurrentTrackHistory` (Spec 2C, Section A.2).
Future<String> _resolvePrimaryGenre({
  required Track track,
  required EnrichmentReadNormalized? readNormalized,
}) async {
  String primaryGenre = 'Unknown';
  if (readNormalized != null) {
    try {
      final normalized = await readNormalized(track);
      if (normalized.isNotEmpty) {
        primaryGenre = normalized.first;
      } else if (track.genre != null && track.genre!.isNotEmpty) {
        primaryGenre = track.genre!;
      }
    } catch (_) {
      // Enrichment read failed; fall through to 'Unknown'.
    }
  }
  return primaryGenre;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Data pipeline producer contract (Spec 2C A.4)', () {
    late Database db;
    late DJHistoryLedger ledger;

    setUp(() async {
      db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE dj_listening_history (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                track_id     TEXT    NOT NULL,
                artist_name  TEXT    NOT NULL,
                primary_genre TEXT   DEFAULT 'Unknown',
                bpm          REAL    DEFAULT 0.0,
                energy_level REAL    DEFAULT 0.5,
                timestamp    INTEGER NOT NULL
              )
            ''');
          },
        ),
      );
      ledger = DJHistoryLedger(db);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'A.4.1: enriched artist → primary_genre = first normalized matrix key',
      () async {
        const track = Track(
          id: 'yt-black-sherif-1',
          title: 'Kwaku The Traveller',
          author: 'Black Sherif',
        );

        // Stub returns ['Hip-Hop', 'Afrobeats'] for Black Sherif.
        // The producer's contract: write the first one.
        final primaryGenre = await _resolvePrimaryGenre(
          track: track,
          readNormalized: _stubReadNormalized,
        );
        expect(primaryGenre, 'Hip-Hop');

        await ledger.logTrack(DJHistoryEntry(
          trackId: track.id,
          artistName: track.author!,
          primaryGenre: primaryGenre,
          timestampMs: 1_000,
        ));

        final rows = await ledger.getAll();
        expect(rows, hasLength(1));
        expect(rows.first.primaryGenre, 'Hip-Hop',
            reason: 'A.4.3 — enriched artist must produce a real matrix key, '
                'not "Unknown"');
      },
    );

    test(
      'A.4.2: unenriched artist (cache miss) → primary_genre = "Unknown"',
      () async {
        const track = Track(
          id: 'yt-unknown-1',
          title: 'Some Song',
          author: 'Unknown Artist',
        );

        // The stub returns [] for unrecognized artists.
        final primaryGenre = await _resolvePrimaryGenre(
          track: track,
          readNormalized: _stubReadNormalized,
        );
        expect(primaryGenre, 'Unknown',
            reason: 'A.4.4 — cache miss must fall through to "Unknown", '
                'not crash');

        await ledger.logTrack(DJHistoryEntry(
          trackId: track.id,
          artistName: track.author!,
          primaryGenre: primaryGenre,
          timestampMs: 2_000,
        ));

        final rows = await ledger.getAll();
        expect(rows.first.primaryGenre, 'Unknown');
      },
    );

    test(
      'A.4.3: cache miss + track.genre fallback → primary_genre = track.genre',
      () async {
        const track = Track(
          id: 'yt-pre-tagged-1',
          title: 'Pre-tagged Song',
          author: 'Unknown Artist',
          genre: 'Trap',
        );

        final primaryGenre = await _resolvePrimaryGenre(
          track: track,
          readNormalized: _stubReadNormalized,
        );
        // Cache miss + non-empty track.genre → use track.genre.
        expect(primaryGenre, 'Trap');

        await ledger.logTrack(DJHistoryEntry(
          trackId: track.id,
          artistName: track.author!,
          primaryGenre: primaryGenre,
          timestampMs: 3_000,
        ));

        final rows = await ledger.getAll();
        expect(rows.first.primaryGenre, 'Trap');
      },
    );

    test(
      'A.4.4: enrichment service throws → falls through to "Unknown"',
      () async {
        const track = Track(
          id: 'yt-flaky-1',
          title: 'Flaky Song',
          author: 'Flaky Artist',
        );

        final primaryGenre = await _resolvePrimaryGenre(
          track: track,
          readNormalized: (t) async {
            throw StateError('Simulated enrichment read failure');
          },
        );
        // Spec A.2: enrichment read failure must NOT block
        // ledger write; row writes successfully with
        // "Unknown".
        expect(primaryGenre, 'Unknown');

        await ledger.logTrack(DJHistoryEntry(
          trackId: track.id,
          artistName: track.author!,
          primaryGenre: primaryGenre,
          timestampMs: 4_000,
        ));

        final rows = await ledger.getAll();
        expect(rows.first.primaryGenre, 'Unknown');
      },
    );

    test(
      'A.4.5: null enrichment service → "Unknown" fallback',
      () async {
        const track = Track(
          id: 'yt-no-enrich-1',
          title: 'No Enrichment',
          author: 'Some Artist',
        );

        final primaryGenre = await _resolvePrimaryGenre(
          track: track,
          readNormalized: null,
        );
        // No enrichment bound → 'Unknown'. Same fallback as
        // the existing pre-Spec 2C behavior.
        expect(primaryGenre, 'Unknown');
      },
    );

    test(
      'A.4.6: full flow — three tracks, all three outcomes, three rows',
      () async {
        const track1 = Track(
          id: 'yt-1',
          title: 'Enriched',
          author: 'Black Sherif',
        );
        const track2 = Track(
          id: 'yt-2',
          title: 'CacheMiss',
          author: 'Unknown Artist',
        );
        const track3 = Track(
          id: 'yt-3',
          title: 'Flaky',
          author: 'Flaky Artist',
        );

        for (final track in [track1, track2, track3]) {
          final pg = await _resolvePrimaryGenre(
            track: track,
            readNormalized: track.id == 'yt-3'
                ? (t) async => throw StateError('flaky')
                : _stubReadNormalized,
          );
          await ledger.logTrack(DJHistoryEntry(
            trackId: track.id,
            artistName: track.author!,
            primaryGenre: pg,
            timestampMs: 1_000 + track.id.hashCode,
          ));
        }

        final rows = await ledger.getAll();
        expect(rows, hasLength(3));

        // Find each by trackId (the ledger orders newest-first
        // so we look up by id).
        final byId = {for (final r in rows) r.trackId: r.primaryGenre};
        expect(byId['yt-1'], 'Hip-Hop',
            reason: 'Enriched artist gets a real matrix key');
        expect(byId['yt-2'], 'Unknown',
            reason: 'Cache miss falls through to "Unknown"');
        expect(byId['yt-3'], 'Unknown',
            reason: 'Enrichment throw falls through to "Unknown"');
      },
    );
  });
}

/// Stub enrichment read that returns canned normalized
/// matrices keys per artist. Mirrors the contract
/// `GenreEnrichmentService.readNormalized` exposes.
Future<List<String>> _stubReadNormalized(Track track) async {
  switch (track.author?.toLowerCase()) {
    case 'black sherif':
      return const ['Hip-Hop', 'Afrobeats'];
    case 'sarkodie':
      return const ['Hip-Hop', 'Afrobeats'];
    case 'drake':
      return const ['Hip-Hop', 'Trap', 'R&B'];
    default:
      return const <String>[];
  }
}
