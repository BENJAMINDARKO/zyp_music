import 'package:http/http.dart' as http;
import 'dart:io';

void main() async {
  final url = 'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M';
  final res = await http.get(Uri.parse(url), headers: {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36'
  });
  
  if (res.statusCode == 200) {
    File('spotify_test.html').writeAsStringSync(res.body);
    print('Spotify HTML dumped successfully. Length: \${res.body.length}');
  } else {
    print('Failed with status code: \${res.statusCode}');
  }
}
