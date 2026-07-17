import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'auth/stored_cookie.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const _keyYoutubeCookies = 'youtube_cookies';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  List<StoredCookie>? _cache;

  Future<void> setCookiesFromWebView(List<Cookie> cookies) async {
    final stored = cookies
        .where((c) => c.name.isNotEmpty && c.value.isNotEmpty)
        .map((c) => StoredCookie(
              name: c.name,
              value: c.value,
              domain: c.domain ?? '',
              path: c.path ?? '/',
            ))
        .toList();
    await _persistCookies(stored);
  }

  /// Parse a cookie header string (e.g. from "Copy as cURL" or document.cookie)
  /// and persist securely. Supports:
  ///   name=value; name=value; ...
  Future<void> setCookiesFromString(String raw) async {
    final stored = <StoredCookie>[];
    for (final part in raw.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      final name = trimmed.substring(0, eq).trim();
      final value = trimmed.substring(eq + 1).trim();
      if (name.isEmpty || value.isEmpty) continue;
      stored.add(StoredCookie(
        name: name,
        value: value,
        domain: '.youtube.com',
        path: '/',
      ));
    }
    await _persistCookies(stored);
  }

  /// Parse a JSON array of cookie objects from browser extensions:
  ///   [{"name":"...","value":"...","domain":"...","path":"/"}, ...]
  Future<void> setCookiesFromJson(String jsonStr) async {
    final decoded = jsonDecode(jsonStr);
    if (decoded is! List) return;
    final stored = decoded
        .map((e) => e is Map ? StoredCookie.fromJson(e.cast<String, dynamic>()) : null)
        .whereType<StoredCookie>()
        .toList();
    await _persistCookies(stored);
  }

  Future<void> _persistCookies(List<StoredCookie> stored) async {
    if (stored.isEmpty) return;
    _cache = stored;
    await _storage.write(
      key: _keyYoutubeCookies,
      value: jsonEncode(stored.map((c) => c.toJson()).toList()),
    );
  }

  Future<List<StoredCookie>> getStoredCookies() async {
    if (_cache != null) return _cache!;

    final raw = await _storage.read(key: _keyYoutubeCookies);
    if (raw == null || raw.isEmpty) return [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    _cache = decoded
        .map((e) => StoredCookie.fromJson(e as Map<String, dynamic>))
        .toList();
    return _cache!;
  }

  Future<String?> getCookieHeader() async {
    final cookies = await getStoredCookies();
    if (cookies.isEmpty) return null;
    return cookies
        .where((c) => c.value.isNotEmpty)
        .map((c) => '${c.name}=${c.value}')
        .join('; ');
  }

  Future<bool> hasRequiredYoutubeCookies() async {
    final cookies = await getStoredCookies();
    final names = cookies.map((c) => c.name).toSet();
    return names.contains('SAPISID') ||
        names.contains('__Secure-3PAPISID') ||
        names.contains('LOGIN_INFO') ||
        names.contains('__Secure-1PSID') ||
        names.contains('__Secure-3PSID');
  }

  Future<bool> validateYoutubeCookies() async {
    final cookieHeader = await getCookieHeader();
    if (cookieHeader == null || cookieHeader.isEmpty) return false;

    final response = await http.get(
      Uri.parse('https://www.youtube.com/feed/library'),
      headers: {
        'Cookie': cookieHeader,
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
      },
    );

    if (response.statusCode != 200) return false;

    final body = response.body.toLowerCase();
    final looksSignedOut =
        body.contains('sign in') && body.contains('accounts.google.com');
    return !looksSignedOut;
  }

  Future<void> clearCookies() async {
    _cache = null;
    await _storage.delete(key: _keyYoutubeCookies);
    await CookieManager.instance().deleteAllCookies();
  }

  // Legacy compat — returns cookie header string (replaces raw string getCookies)
  Future<String?> getCookies() => getCookieHeader();
}
