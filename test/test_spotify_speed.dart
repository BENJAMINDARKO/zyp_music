import 'package:http/http.dart' as http;

void main() async {
  final watch = Stopwatch()..start();
  print('Fetching spotify...');
  try {
    final res = await http.get(Uri.parse('https://open.spotify.com/embed/playlist/37i9dQZF1DXcBWIGoYBM5M'), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    }).timeout(Duration(seconds: 10));
    print('Status: ${res.statusCode}');
    print('Length: ${res.body.length}');
  } catch(e) {
    print('Error: $e');
  }
  print('Time: ${watch.elapsedMilliseconds}ms');
}
