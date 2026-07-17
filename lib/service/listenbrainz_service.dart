import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ListenBrainzService {
  static const _tokenKey = 'listenbrainz_token';
  final FlutterSecureStorage _storage;

  static ListenBrainzService? _instance;
  ListenBrainzService._() : _storage = const FlutterSecureStorage();
  factory ListenBrainzService() => _instance ??= ListenBrainzService._();

  Future<String?> getToken() => _storage.read(key: _tokenKey);

  Future<void> setToken(String token) =>
      _storage.write(key: _tokenKey, value: token.trim());

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<bool> verifyToken(String token) async {
    try {
      final res = await http.get(
        Uri.parse('https://api.listenbrainz.org/1/validate-token'),
        headers: {'Authorization': 'Token ${token.trim()}'},
      );
      if (res.statusCode != 200) return false;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['valid'] == true || body['code'] == 200;
    } catch (_) {
      return false;
    }
  }
}
