import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final url = 'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M'; // Today's Top Hits
  final response = await http.get(Uri.parse(url));
  print(response.statusCode);
  if (response.statusCode == 200) {
    // Look for initial data in a <script> tag
    final html = response.body;
    // Spotify usually puts state in a script tag with "initial-state" or just embedded JSON.
    print(html.substring(0, 1000)); // check start
    if (html.contains('Spotify.Entity')) {
      print('Found entity');
    }
  }
}
