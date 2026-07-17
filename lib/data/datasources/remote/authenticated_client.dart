import 'package:http/http.dart' as http;

class AuthenticatedClient extends http.BaseClient {
  final http.Client _inner;
  final String? _cookieHeader;

  AuthenticatedClient({http.Client? inner, String? cookieHeader})
      : _cookieHeader = cookieHeader,
        _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_cookieHeader != null && _cookieHeader!.isNotEmpty) {
      request.headers['Cookie'] = _cookieHeader;
    }
    request.headers['User-Agent'] =
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
