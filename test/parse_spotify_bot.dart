import 'dart:io';
import 'package:html/parser.dart' as parser;
import 'dart:convert';

void main() async {
  final html = File('spotify_bot.html').readAsStringSync();
  final doc = parser.parse(html);
  
  final jsonLdScripts = doc.querySelectorAll('script[type="application/ld+json"]');
  for (var s in jsonLdScripts) {
    try {
      final json = jsonDecode(s.innerHtml);
      if (json['@type'] == 'MusicPlaylist') {
        final tracks = json['track']['itemListElement'] as List;
        print('Found \${tracks.length} tracks!');
        for(var i=0; i<3; i++) {
          final t = tracks[i]['item'];
          final name = t['name'];
          final byArtist = t['byArtist'] as List;
          final artistNames = byArtist.map((a) => a['name']).join(', ');
          print('\$name - \$artistNames');
        }
      }
    } catch(e) {
      print('Error parsing JSON-LD: $e');
    }
  }
}
