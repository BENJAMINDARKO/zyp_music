import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:developer' as dev;

class AuthService {
  static const _cookiesKey = 'youtube_cookies';
  final FlutterSecureStorage _storage;

  static AuthService? _instance;
  AuthService._() : _storage = const FlutterSecureStorage();
  factory AuthService() => _instance ??= AuthService._();

  Future<String?> getCookies() async {
    try {
      final raw = await _storage.read(key: _cookiesKey);
      return raw?.isEmpty == true ? null : raw;
    } catch (e) {
      dev.log('Failed to read cookies: $e', name: 'AuthService');
      return null;
    }
  }

  Future<void> setCookies(String cookies) async {
    try {
      await _storage.write(key: _cookiesKey, value: cookies);
    } catch (e) {
      dev.log('Failed to save cookies: $e', name: 'AuthService');
    }
  }

  Future<void> clearCookies() async {
    try {
      await _storage.delete(key: _cookiesKey);
    } catch (e) {
      dev.log('Failed to clear cookies: $e', name: 'AuthService');
    }
  }

  Future<bool> hasCookies() async {
    final cookies = await getCookies();
    return cookies != null && cookies.isNotEmpty;
  }
}
