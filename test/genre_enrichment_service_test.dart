// Spec 2A Gate 5 — production write path integration test.
//
// This is not a pure unit test: it drives the real
// `GenreEnrichmentService.enqueueForEnrichment` path end-to-end
// with the only substitution being a stub `MusicBrainzDataSource`
// (the network edge). The DB layer is real, the normalization
// service is real, the spec's `cacheArtistGenres` signature is
// real. If the wiring is broken in any of the following ways,
// the test fails:
//   * `GenreNormalizationService` not actually injected →
//     normalizedGenres would be empty.
//   * `_enrichOne` skips `normalizeAll` for any reason →
//     normalizedGenres would be empty.
//   * `cacheArtistGenres` doesn't serialize
//     `normalized_genres_json` correctly → roundtrip would lose
//     the value.
//   * `getCachedArtistGenres` doesn't deserialize
//     `normalized_genres_json` correctly → roundtrip would
//     return empty.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zyp_music/core/services/genre_enrichment_service.dart';
import 'package:zyp_music/core/services/genre_normalization_service.dart';
import 'package:zyp_music/core/services/spotify_metadata_service.dart';
import 'package:zyp_music/data/datasources/local/playlist_database.dart';
import 'package:zyp_music/data/datasources/remote/musicbrainz_datasource.dart';
import 'package:zyp_music/domain/entities/video.dart';

/// Stub MusicBrainz data source that returns canned responses
/// for Black Sherif per the spec's Gate 5 example. The real
/// `_enqueue` throttle is bypassed because we override the
/// public methods the service calls.
class _StubMusicBrainzDataSource extends MusicBrainzDataSource {
  @override
  Future<MusicBrainzArtistMatch?> searchArtist(
    String name, {
    int minScore = 85,
  }) async {
    if (name.toLowerCase() != 'black sherif') return null;
    return const MusicBrainzArtistMatch(
      mbid: '00000000-0000-0000-0000-000000000001',
      name: 'Black Sherif',
      score: 100,
    );
  }

  @override
  Future<List<MusicBrainzGenreEntry>> getArtistGenres(String mbid) async {
    if (mbid != '00000000-0000-0000-0000-000000000001') return const [];
    // Returned in the order MusicBrainz typically serves them;
    // `_enrichOne` re-sorts by `count` descending before
    // normalizing. MUST be a mutable list — `_enrichOne` calls
    // `.sort()` in place. A const list would throw
    // "Cannot modify an unmodifiable list" exactly the same way
    // a frozen response from the real API never would.
    return <MusicBrainzGenreEntry>[
      const MusicBrainzGenreEntry(name: 'afro-fusion', count: 4),
      const MusicBrainzGenreEntry(name: 'Ghanaian hip hop', count: 3),
      const MusicBrainzGenreEntry(name: 'hip hop', count: 2),
      const MusicBrainzGenreEntry(name: 'rap', count: 1),
    ];
  }
}

Map<String, String> _loadNormalizationDict() {
  // Read the on-disk asset directly. This catches the
  // failure mode where the asset exists in the repo but is
  // not bundled in the APK (e.g., missing from pubspec.yaml).
  final f = File('assets/data/genre_normalization.json');
  if (!f.existsSync()) {
    throw StateError(
        'assets/data/genre_normalization.json must exist for the integration test');
  }
  final decoded = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  return decoded.map((k, v) => MapEntry(k, v as String));
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('GenreEnrichmentService (Spec 2A Gate 5)', () {
    late PlaylistDatabase db;
    late String dbPath;
    late GenreEnrichmentService svc;

    setUp(() async {
      dbPath = '/tmp/zyp_2a_gate5_${DateTime.now().microsecondsSinceEpoch}.db';
      await deleteDatabase(dbPath);
      db = PlaylistDatabase.forTesting(dbPath);
      await db.database;

      final normalization = GenreNormalizationService();
      normalization.loadDictionaryForTesting(_loadNormalizationDict());

      svc = GenreEnrichmentService(
        mb: _StubMusicBrainzDataSource(),
        spotify: SpotifyMetadataService(db: db),
        db: db,
        normalization: normalization,
      );
    });

    tearDown(() async {
      await db.close();
      await deleteDatabase(dbPath);
    });

    test(
      'Gate 5: enqueueForEnrichment populates normalized_genres_json',
      () async {
        const track = Track(
          id: 'yt-black-sherif-1',
          title: 'Kwaku The Traveller',
          author: 'Black Sherif',
        );

        svc.enqueueForEnrichment([track]);
        await svc.drain();

        final cached = await db.getCachedArtistGenres('black sherif');
        expect(cached, isNotNull,
            reason: 'Row must exist in artist_genres after enrichment');

        // The whole point of Gate 5: the matrix keys must be
        // populated. If the wiring is broken, this is empty.
        expect(cached!.normalizedGenres, isNotEmpty,
            reason:
                'normalized_genres_json must contain at least one matrix key. '
                'If this fails, the normalization service is not being called '
                'in the production write path.');

        // The raw MB tags must also be present (no regression
        // on the existing field).
        expect(cached.rawGenres, contains('afro-fusion'));
        expect(cached.rawGenres, contains('Ghanaian hip hop'));

        // Dedup must fire: 'afro-fusion', 'Ghanaian hip hop',
        // 'hip hop', 'rap' all canonicalize through the
        // dictionary to a smaller set of matrix keys.
        final expectedKeys = <String>{
          'Hip-Hop',
          'Afro-Fusion',
        };
        expect(cached.normalizedGenres.toSet(), expectedKeys,
            reason: 'normalizeAll must dedupe hip-hop variants to Hip-Hop');
      },
    );

    test('Gate 5: readNormalized returns the matrix keys after enrichment',
        () async {
      const track = Track(
        id: 'yt-black-sherif-1',
        title: 'Kwaku The Traveller',
        author: 'Black Sherif',
      );
      svc.enqueueForEnrichment([track]);
      await svc.drain();

      final normalized = await svc.readNormalized(track);
      expect(normalized, isNotEmpty);
      expect(normalized.toSet(), {'Hip-Hop', 'Afro-Fusion'});
    });

    test('Gate 5: cache miss returns empty list from readNormalized',
        () async {
      const track = Track(
        id: 'yt-unknown-1',
        title: 'Some Song',
        author: 'Unknown Artist Who Does Not Exist',
      );
      final normalized = await svc.readNormalized(track);
      expect(normalized, isEmpty);
    });
  });
}
