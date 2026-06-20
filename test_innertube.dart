import 'dart:convert';
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
    final data = jsonDecode(res.body);
    print('Success! Keys: ${data.keys}');
    // Let's see if we can find musicResponsiveListItemRenderer
    final contents = data['contents']?['twoColumnBrowseResultsRenderer']?['secondaryContents']?['sectionListRenderer']?['contents']?[0]?['musicPlaylistShelfRenderer']?['contents'];
    if (contents != null) {
      print('Found ${contents.length} tracks!');
      for (var c in contents.take(2)) {
        final r = c['musicResponsiveListItemRenderer'];
        final title = r['flexColumns']?[0]?['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']?[0]?['text'];
        print('Track: $title');
      }
    } else {
      print('Could not find track list in standard location. Trying singleColumnBrowseResultsRenderer...');
      final contents2 = data['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents']?[0]?['musicPlaylistShelfRenderer']?['contents'];
      if (contents2 != null) {
        print('Found ${contents2.length} tracks in single column!');
      } else {
        print('Could not find tracks.');
      }
    }
  } else {
    print('Failed: ${res.statusCode}');
  }
}
