import 'package:flutter_test/flutter_test.dart';
import 'package:pi_crust/domain/update/semver.dart';

void main() {
  group('SemVer parser and comparator', () {
    test('parses standard semver strings', () {
      final v1 = SemVer.parse('1.3.0');
      expect(v1.major, 1);
      expect(v1.minor, 3);
      expect(v1.patch, 0);
      expect(v1.preRelease, isNull);

      final v2 = SemVer.parse('v2.10.5');
      expect(v2.major, 2);
      expect(v2.minor, 10);
      expect(v2.patch, 5);

      final v3 = SemVer.parse('1.0.0-alpha.1');
      expect(v3.major, 1);
      expect(v3.minor, 0);
      expect(v3.patch, 0);
      expect(v3.preRelease, 'alpha.1');
    });

    test('returns null for invalid semver strings', () {
      expect(SemVer.tryParse('invalid'), isNull);
      expect(SemVer.tryParse('1'), isNull);
      expect(SemVer.tryParse('1.2'), isNull);
      expect(SemVer.tryParse(''), isNull);
      expect(SemVer.tryParse(null), isNull);
    });

    test('compares versions correctly', () {
      final v1_2_9 = SemVer.parse('1.2.9');
      final v1_3_0 = SemVer.parse('1.3.0');
      final v1_3_1 = SemVer.parse('1.3.1');
      final v1_4_0 = SemVer.parse('1.4.0');
      final v2_0_0 = SemVer.parse('2.0.0');

      expect(v1_3_0 > v1_2_9, isTrue);
      expect(v1_3_0 < v1_3_1, isTrue);
      expect(v1_4_0 > v1_3_1, isTrue);
      expect(v2_0_0 > v1_4_0, isTrue);

      expect(v1_3_0 >= SemVer.parse('v1.3.0'), isTrue);
      expect(v1_3_0 <= SemVer.parse('1.3.0'), isTrue);
      expect(v1_3_0 == SemVer.parse('v1.3.0'), isTrue);
    });

    test('handles pre-release precedence', () {
      final v130Pre = SemVer.parse('1.3.0-rc.1');
      final v130 = SemVer.parse('1.3.0');

      // A version with pre-release has lower precedence than without
      expect(v130 > v130Pre, isTrue);
      expect(v130Pre < v130, isTrue);

      final rc1 = SemVer.parse('1.3.0-rc.1');
      final rc2 = SemVer.parse('1.3.0-rc.2');
      expect(rc2 > rc1, isTrue);
    });
  });
}
