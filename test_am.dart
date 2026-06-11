import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;

void main() async {
  final res = await http.get(Uri.parse('https://music.apple.com/us/playlist/todays-hits/pl.f4d106fed2bd41149aaacabb233eb5eb'));
  final doc = parser.parse(res.body);
  final script = doc.querySelector('script#serialized-server-data');
  if (script != null) {
    final root = jsonDecode(script.innerHtml) as Map<String, dynamic>;
    final sections = root['data'][0]['data']['sections'] as List;
    final trackSection = sections.firstWhere((s) {
      if (s['items'] == null || (s['items'] as List).isEmpty) return false;
      final firstItem = s['items'][0];
      return firstItem['type'] == 'track' || firstItem['contentDescriptor']?['kind'] == 'song';
    }, orElse: () => {'items': []});
    
    final tracks = trackSection['items'] as List;
    if (tracks.isNotEmpty) {
      print(jsonEncode(tracks.first));
    }
  }
}
