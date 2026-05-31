import 'package:http/http.dart' as http;

class NetworkUtils {
  static Future<String> resolveRedirects(
    http.Client client,
    String url, {
    Map<String, String>? headers,
  }) async {
    var current = url;
    for (var i = 0; i < 10; i++) {
      final req = http.Request('GET', Uri.parse(current));
      if (headers != null) req.headers.addAll(headers);
      req.followRedirects = false;
      final resp = await client.send(req);
      final status = resp.statusCode;
      await resp.stream.drain();
      if (status >= 300 && status < 400) {
        final location = resp.headers['location'];
        if (location == null) break;
        current = Uri.parse(location).isAbsolute
            ? location
            : Uri.parse(current).resolve(location).toString();
      } else {
        return current;
      }
    }
    return current;
  }
}
