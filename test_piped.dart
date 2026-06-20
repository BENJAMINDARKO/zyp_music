import 'package:http/http.dart' as http;
import 'dart:convert';

void main() async {
  final videoId = 'yUDrOesyhPc';
  final instances = [
    'https://pipedapi.syncpundit.io',
    'https://pipedapi.lunar.icu',
    'https://pipedapi.ducks.party',
    'https://piped-api.garudalinux.org',
    'https://api.piped.privacydev.net',
  ];
  for (final base in instances) {
    try {
      final resp = await http.get(Uri.parse('$base/streams/$videoId')).timeout(Duration(seconds: 5));
      print('Piped $base: ${resp.statusCode}');
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        print(' - audioStreams length: ${json['audioStreams']?.length}');
      }
    } catch (e) {
      print('Piped $base failed: $e');
    }
  }
}
