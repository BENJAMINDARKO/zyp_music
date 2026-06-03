import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'dart:convert';

void main() async {
  final res = await http.get(Uri.parse('https://music.apple.com/gh/playlist/top-100-ghana/pl.78f1974e882d4952b26ebfb8e017c933'));
  final doc = parser.parse(res.body);
  
  final script = doc.querySelector('script#serialized-server-data');
  if (script != null) {
    final root = jsonDecode(script.innerHtml) as Map<String, dynamic>;
    final sections = root['data'][0]['data']['sections'] as List;
    final tracks = sections.firstWhere((s) => s['items'] != null && s['items'].length > 50)['items'];
    final track = tracks.first;
    print('Artwork: ${track['artwork']}');
  }
}
