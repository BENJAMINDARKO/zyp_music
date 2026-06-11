import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;

void main() async {
  final res = await http.get(Uri.parse('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M')); // Today's Top Hits
  final doc = parser.parse(res.body);
  
  // Find all scripts that might contain initial state
  final scripts = doc.querySelectorAll('script');
  for (var s in scripts) {
    if (s.innerHtml.contains('Spotify.Entity')) {
      print('Found Entity script!');
    }
    if (s.innerHtml.contains('initialState')) {
      print('Found initialState script!');
    }
  }

  // Also check meta tags
  final metaTags = doc.querySelectorAll('meta');
  for (var m in metaTags) {
    if (m.attributes['property']?.startsWith('music:song') ?? false) {
      print(m.outerHtml);
    }
  }
}
