import 'package:http/http.dart' as http;

class AuthenticatedClient extends http.BaseClient {
  final http.Client _inner;
  final String? _cookies;

  AuthenticatedClient({http.Client? inner, this._cookies})
      : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (_cookies != null && _cookies.isNotEmpty) {
      request.headers['Cookie'] = _cookies;
    }
    request.headers['User-Agent'] =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
