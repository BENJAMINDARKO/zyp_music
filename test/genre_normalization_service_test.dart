// Spec 2A — Genre Normalization Service
// Validation gate coverage:
//   * Gate 2: case-insensitivity + canonicalization (whitespace
//     trim + collapse; lowercased; dictionary lookup).
//   * Gate 3: normalizeAll dedupes the result set when several
//     raw tags map to the same canonical key.
//
// Note: `flutter test` does not initialize the asset bundle by
// default — rootBundle.loadString throws "Binding has not yet
// been initialized". We patch the service's dictionary via a
// test-only hook so the tests can exercise the real
// canonicalize/lookup logic without going through the bundle
// path. The hook is the `dictionary` setter below; production
// code never touches it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyp_music/core/services/genre_normalization_service.dart';

void main() {
  late GenreNormalizationService svc;
  late Map<String, String> realDictionary;

  setUpAll(() {
    // Load the on-disk dictionary once for all tests. Failing
    // here means a typo or missing entry in the asset — the
    // build must surface that, not a stale in-test copy.
    final f = File('assets/data/genre_normalization.json');
    expect(f.existsSync(), isTrue,
        reason: 'assets/data/genre_normalization.json must exist for tests');
    final decoded = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    realDictionary = decoded.map((k, v) => MapEntry(k, v as String));
  });

  setUp(() {
    svc = GenreNormalizationService();
    svc.loadDictionaryForTesting(realDictionary);
  });

  group('GenreNormalizationService.canonicalization', () {
    test('Gate 2: lowercase + trim + whitespace collapse', () {
      // Internal canonicalization is exposed indirectly via
      // normalize(): "  HIP HOP  " must hit the same dictionary
      // entry as "hip hop".
      expect(svc.normalize('hip hop'), 'Hip-Hop');
      expect(svc.normalize('  HIP HOP  '), 'Hip-Hop');
      expect(svc.normalize('Hip   Hop'), 'Hip-Hop');
    });

    test('Gate 2: hyphenated / multi-word tags', () {
      expect(svc.normalize('afro-fusion'), 'Afrobeats');
      expect(svc.normalize('uk drill'), 'Drill');
    });

    test('Gate 2: empty / null inputs', () {
      expect(svc.normalize(null), isNull);
      expect(svc.normalize(''), isNull);
      expect(svc.normalize('   '), isNull);
    });

    test('Gate 2: unmapped tags return null and are recorded', () {
      final beforeCount = svc.unmappedTagsThisSession.length;
      expect(svc.normalize('nonexistent fake genre'), isNull);
      expect(svc.unmappedTagsThisSession.length, beforeCount + 1);
    });
  });

  group('GenreNormalizationService.normalizeAll', () {
    test('Gate 3: dedupes when several raw tags map to same key', () {
      final input = ['hip hop', 'rap', 'Hip-Hop', 'ghanaian rap'];
      final out = svc.normalizeAll(input);
      // 'rap' and 'hip hop' both canonicalize → dictionary → 'Hip-Hop';
      // 'ghanaian rap' → 'Hip-Hop' via the spec's lowercase
      // canonicalization. All four must collapse to a single entry.
      expect(out, ['Hip-Hop']);
    });

    test('Gate 3: preserves distinct canonical keys', () {
      final input = ['hip hop', 'r&b', 'trap'];
      final out = svc.normalizeAll(input);
      expect(out.toSet(), {'Hip-Hop', 'R&B', 'Trap'});
    });

    test('Gate 3: drops unmapped tags silently', () {
      final out = svc.normalizeAll(['hip hop', 'asdfqwer', 'trap']);
      expect(out.toSet(), {'Hip-Hop', 'Trap'});
    });

    test('Gate 3: empty input returns empty list', () {
      expect(svc.normalizeAll(const []), isEmpty);
    });
  });
}
