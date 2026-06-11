import 'package:http/http.dart' as http;
import 'dart:convert';

void main() async {
  try {
    final tokenRes = await http.get(Uri.parse('https://open.spotify.com/get_access_token?reason=transport&productType=web_player'), headers: {
      'User-Agent': 'Mozilla/5.0'
    });
    final tokenJson = jsonDecode(tokenRes.body);
    final accessToken = tokenJson['accessToken'];
    print('Token: $accessToken');
    
    final pRes = await http.get(Uri.parse('https://api.spotify.com/v1/playlists/37i9dQZF1DXcBWIGoYBM5M'), headers: {
      'Authorization': 'Bearer $accessToken'
    });
    print('Status: \${pRes.statusCode}');
    final pJson = jsonDecode(pRes.body);
    final tracks = pJson['tracks']['items'] as List;
    print('Found \${tracks.length} tracks!');
    for(int i=0; i<3; i++) {
      final t = tracks[i]['track'];
      final title = t['name'];
      final artist = t['artists'][0]['name'];
      print('$title - $artist');
    }
  } catch(e) {
    print('Error: $e');
  }
}
