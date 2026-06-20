import 'package:http/http.dart' as http;
import 'dart:convert';

void main() async {
  final videoId = 'yUDrOesyhPc';
  final instances = [
    'https://inv.nadeko.net',
    'https://invidious.nerdvpn.de',
    'https://invidious.jing.rocks',
    'https://yt.artemislena.eu',
    'https://invidious.flokinet.to',
  ];
  for (final base in instances) {
    try {
      final resp = await http.get(Uri.parse('$base/api/v1/videos/$videoId'));
      print('Invidious $base: ${resp.statusCode}');
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        final adaptive = json['adaptiveFormats'] as List?;
        if (adaptive != null) {
          int count = 0;
          for (var f in adaptive) {
            if (f['type']?.contains('audio/') == true) {
              count++;
            }
          }
          print('Found $count audio formats.');
        }
      }
    } catch (e) {
      print('Invidious $base failed: $e');
    }
  }
}
