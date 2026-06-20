import 'package:http/http.dart' as http;
import 'dart:convert';

void main() async {
  final videoId = 'yUDrOesyhPc';
  try {
    final resp = await http.get(Uri.parse('https://yt.lemnoslife.com/noKey/youtubei/v1/player?videoId=$videoId'));
    print('Lemnos status: ${resp.statusCode}');
    if (resp.statusCode == 200) {
      final json = jsonDecode(resp.body);
      final streamingData = json['streamingData'];
      if (streamingData != null) {
        final adaptive = streamingData['adaptiveFormats'] as List?;
        print('Found ${adaptive?.length} adaptive formats');
      } else {
        print('No streaming data: ${json['playabilityStatus']}');
      }
    }
  } catch (e) {
    print('Lemnos failed: $e');
  }
}
