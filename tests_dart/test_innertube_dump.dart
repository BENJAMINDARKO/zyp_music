import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  final url = Uri.parse('https://music.youtube.com/youtubei/v1/browse?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8');
  final body = {
    "context": {
      "client": {
        "clientName": "WEB_REMIX",
        "clientVersion": "1.20230502.01.00",
        "hl": "en"
      }
    },
    "browseId": "VLOLAK5uy_I13RAEFxk5KvJs_E8JIqcyXaQ9FDIHiwY"
  };

  final res = await http.post(url, body: jsonEncode(body), headers: {
    'Content-Type': 'application/json',
    'Origin': 'https://music.youtube.com',
  });

  if (res.statusCode == 200) {
    File('innertube_dump.json').writeAsStringSync(res.body);
    print('Dumped to innertube_dump.json');
  } else {
    print('Failed: ${res.statusCode}');
  }
}
