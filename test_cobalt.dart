import 'package:http/http.dart' as http;
import 'dart:convert';

void main() async {
  final videoId = 'yUDrOesyhPc';
  final url = 'https://www.youtube.com/watch?v=$videoId';
  
  try {
    final resp = await http.post(
      Uri.parse('https://api.cobalt.tools/api/json'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'url': url,
        'vCodec': 'h264',
        'vQuality': '720',
        'aFormat': 'best',
        'isAudioOnly': true
      }),
    );
    print('Cobalt status: ${resp.statusCode}');
    print('Cobalt response: ${resp.body}');
  } catch (e) {
    print('Cobalt failed: $e');
  }
}
