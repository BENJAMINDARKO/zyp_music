import 'package:flutter_test/flutter_test.dart';
import 'package:ytmusix/core/utils/format_duration.dart';

void main() {
  group('formatDuration', () {
    test('formats zero', () {
      expect(formatDuration(Duration.zero), '00:00');
    });

    test('formats seconds only', () {
      expect(formatDuration(const Duration(seconds: 5)), '00:05');
    });

    test('formats minutes and seconds', () {
      expect(formatDuration(const Duration(seconds: 125)), '02:05');
    });

    test('formats hours', () {
      expect(formatDuration(const Duration(seconds: 3661)), '1:01:01');
    });

    test('formats hours with leading zero', () {
      expect(formatDuration(const Duration(seconds: 7200)), '2:00:00');
    });

    test('formats edge case 59:59', () {
      expect(formatDuration(const Duration(seconds: 3599)), '59:59');
    });

    test('formats edge case 1 second', () {
      expect(formatDuration(const Duration(seconds: 1)), '00:01');
    });
  });
}
