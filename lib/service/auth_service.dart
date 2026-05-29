import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const _cookiesKey = 'youtube_cookies';

  static AuthService? _instance;
  AuthService._();
  factory AuthService() => _instance ??= AuthService._();

  Future<String?> getCookies() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cookiesKey);
    return raw?.isEmpty == true ? null : raw;
  }

  Future<void> setCookies(String cookies) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cookiesKey, cookies);
  }

  Future<void> clearCookies() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cookiesKey);
  }

  Future<bool> hasCookies() async {
    final cookies = await getCookies();
    return cookies != null && cookies.isNotEmpty;
  }
}
