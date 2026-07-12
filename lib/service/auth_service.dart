import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zyp_music/core/utils/app_logger.dart';

class AuthService {
  static const _cookiesKey = 'youtube_cookies';
  final FlutterSecureStorage _storage;

  static AuthService? _instance;
  AuthService._() : _storage = const FlutterSecureStorage();
  factory AuthService() => _instance ??= AuthService._();

  String? _cachedCookies;
  bool _isCookiesCached = false;

  Future<String?> getCookies() async {
    if (_isCookiesCached) {
      return _cachedCookies;
    }
    try {
      final raw = await _storage.read(key: _cookiesKey);
      _cachedCookies = raw?.isEmpty == true ? null : raw;
      _isCookiesCached = true;
      return _cachedCookies;
    } catch (e) {
      AppLogger.log('Failed to read cookies: $e', name: 'AuthService');
      return null;
    }
  }

  Future<void> setCookies(String cookies) async {
    try {
      await _storage.write(key: _cookiesKey, value: cookies);
      _cachedCookies = cookies.isEmpty ? null : cookies;
      _isCookiesCached = true;
    } catch (e) {
      AppLogger.log('Failed to save cookies: $e', name: 'AuthService');
    }
  }

  Future<void> clearCookies() async {
    try {
      await _storage.delete(key: _cookiesKey);
      _cachedCookies = null;
      _isCookiesCached = true;
    } catch (e) {
      AppLogger.log('Failed to clear cookies: $e', name: 'AuthService');
    }
  }

  Future<bool> hasCookies() async {
    final cookies = await getCookies();
    return cookies != null && cookies.isNotEmpty;
  }
}
