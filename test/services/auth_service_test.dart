import 'package:flutter_test/flutter_test.dart';
import 'package:ytmusix/service/auth_service.dart';

void main() {
  group('AuthService', () {
    test('returns same instance via factory constructor', () {
      final a = AuthService();
      final b = AuthService();
      expect(identical(a, b), true);
    });
  });
}
