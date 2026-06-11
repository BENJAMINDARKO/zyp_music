import 'dart:io';
import 'package:html/parser.dart' as parser;
import 'dart:convert';

void main() async {
  final html = File('spotify_embed.html').readAsStringSync();
  final doc = parser.parse(html);
  
  final script = doc.querySelector('script#resource');
  if (script != null) {
    print('Found script#resource');
    try {
      final text = script.innerHtml;
      // It's probably URI encoded json inside
      final decoded = Uri.decodeFull(text);
      final json = jsonDecode(decoded);
      
      // Look for tracks
      final tracks = json['tracks']['items'] as List;
      print('Found \${tracks.length} tracks!');
      for(var i=0; i<3; i++) {
        print(tracks[i]['track']['name']);
      }
    } catch(e) {
      print('Failed to parse: $e');
    }
  } else {
    // try to find script with initial-state
    final scripts = doc.querySelectorAll('script');
    for (var s in scripts) {
      if (s.id == 'initial-state') {
        print('Found initial-state: \${s.innerHtml.substring(0, 100)}');
        final base64String = s.innerHtml;
        final decoded = utf8.decode(base64Decode(base64String));
        print(decoded.substring(0, 200));
        
        final json = jsonDecode(decoded);
        final data = json['data']['entity'];
        final tracks = data['trackList'] as List;
        print('Found \${tracks.length} tracks in initial-state');
        for (var t in tracks.take(3)) {
          print(t['title']);
        }
      }
    }
  }
}
