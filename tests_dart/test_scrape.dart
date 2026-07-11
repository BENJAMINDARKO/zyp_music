import 'package:http/http.dart' as http;

void main() async {
  final url = Uri.parse('https://music.youtube.com/playlist?list=OLAK5uy_I13RAEFxk5KvJs_E8JIqcyXaQ9FDIHiwY');
  final res = await http.get(url, headers: {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36'
  });
  final text = res.body;
  final count = '"videoId":"'.allMatches(text).length;
  print('Found $count videoIds!');
  // Let's print the first 5
  var matches = RegExp(r'"videoId":"([^"]+)"').allMatches(text);
  for (var m in matches.take(5)) {
    print('ID: ${m.group(1)}');
  }
}
