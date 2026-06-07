// Spec 2E — Country Bonus Service unit tests.
//
// Coverage:
//   * Same country → 1.0
//   * Same region → 0.85
//   * Different region → 0.7
//   * Either side null/empty → 1.0 (neutral)
//   * Unknown country code (not in region map) → 1.0 (neutral)
//   * Case-insensitivity on input codes
//   * regionFor reverse lookup
//   * isReady flag flips on loadMapForTesting
//
// Tests use `loadMapForTesting` to avoid the asset bundle
// (the production asset is exercised in the build's analyze
// step; the test seam mirrors the normalization-service
// pattern in spec 2A).

import 'package:flutter_test/flutter_test.dart';
import 'package:zyp_music/core/services/country_bonus_service.dart';

void main() {
  group('CountryBonusService', () {
    late CountryBonusService svc;

    setUp(() {
      svc = CountryBonusService();
      svc.loadMapForTesting(<String, String>{
        'GH': 'West Africa',
        'NG': 'West Africa',
        'KE': 'Sub-Saharan Africa',
        'US': 'North America',
        'GB': 'Europe',
        'DE': 'Europe',
        'JP': 'East Asia',
        'BR': 'South America',
      });
    });

    test('isReady flips true after loadMapForTesting', () {
      expect(svc.isReady, isTrue);
    });

    test('same country → 1.0', () {
      expect(svc.scoreFor('GH', 'GH'), 1.0);
      expect(svc.scoreFor('US', 'US'), 1.0);
    });

    test('same region (West Africa) → 0.85', () {
      expect(svc.scoreFor('GH', 'NG'), 0.85);
      expect(svc.scoreFor('NG', 'GH'), 0.85);
    });

    test('same region (Europe) → 0.85', () {
      expect(svc.scoreFor('GB', 'DE'), 0.85);
    });

    test('different region → 0.7', () {
      expect(svc.scoreFor('GH', 'US'), 0.7);
      expect(svc.scoreFor('US', 'DE'), 0.7);
      expect(svc.scoreFor('GH', 'JP'), 0.7);
    });

    test('seed null → 1.0 (unknown neutral)', () {
      expect(svc.scoreFor(null, 'GH'), 1.0);
      expect(svc.scoreFor(null, 'US'), 1.0);
    });

    test('candidate null → 1.0 (unknown neutral)', () {
      expect(svc.scoreFor('GH', null), 1.0);
      expect(svc.scoreFor('US', null), 1.0);
    });

    test('both null → 1.0 (unknown neutral)', () {
      expect(svc.scoreFor(null, null), 1.0);
    });

    test('empty string treated as null → 1.0', () {
      expect(svc.scoreFor('', 'GH'), 1.0);
      expect(svc.scoreFor('GH', ''), 1.0);
      expect(svc.scoreFor('', ''), 1.0);
      expect(svc.scoreFor('   ', '  '), 1.0);
    });

    test('whitespace trimmed', () {
      expect(svc.scoreFor('  GH  ', 'NG'), 0.85);
    });

    test('case-insensitive (lowercase input matches)', () {
      expect(svc.scoreFor('gh', 'ng'), 0.85);
      expect(svc.scoreFor('Gh', 'nG'), 0.85);
      expect(svc.scoreFor('GH', 'ng'), 0.85);
    });

    test('unknown country code → 1.0 (region map miss)', () {
      expect(svc.scoreFor('ZZ', 'GH'), 1.0);
      expect(svc.scoreFor('GH', 'ZZ'), 1.0);
      expect(svc.scoreFor('ZZ', 'XX'), 1.0);
    });

    test('seed known, candidate known, different country, different region → 0.7',
        () {
      expect(svc.scoreFor('GH', 'US'), 0.7);
    });

    test('seed known, candidate known, different country, same region → 0.85',
        () {
      expect(svc.scoreFor('GH', 'NG'), 0.85);
    });

    test('regionFor returns the region for a known code', () {
      expect(svc.regionFor('GH'), 'West Africa');
      expect(svc.regionFor('US'), 'North America');
    });

    test('regionFor returns null for unknown code', () {
      expect(svc.regionFor('ZZ'), isNull);
    });

    test('regionFor returns null for null/empty', () {
      expect(svc.regionFor(null), isNull);
      expect(svc.regionFor(''), isNull);
      expect(svc.regionFor('  '), isNull);
    });

    test('regionFor is case-insensitive', () {
      expect(svc.regionFor('gh'), 'West Africa');
      expect(svc.regionFor('us'), 'North America');
    });

    test('loadMapForTesting is idempotent (re-call resets map)', () {
      svc.loadMapForTesting(<String, String>{'US': 'North America'});
      expect(svc.scoreFor('US', 'US'), 1.0);
      expect(svc.scoreFor('GH', 'NG'), 1.0, reason: 'GH/NG no longer in map');
    });

    test('multiplicative composition is monotonic: '
        'same-country > same-region > different-region', () {
      final sameCountry = svc.scoreFor('US', 'US');
      final sameRegion = svc.scoreFor('GB', 'DE');
      final diffRegion = svc.scoreFor('US', 'JP');
      expect(sameCountry, greaterThan(sameRegion));
      expect(sameRegion, greaterThan(diffRegion));
    });
  });
}
