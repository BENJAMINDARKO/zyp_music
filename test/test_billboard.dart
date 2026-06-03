import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;

void main() async {
  final response = await http.get(Uri.parse('https://www.billboard.com/charts/billboard-200/'), headers: {
    'User-Agent': 'Mozilla/5.0',
    'Accept': 'text/html',
  });
  final document = parser.parse(response.body);
  final rows = document.querySelectorAll('.o-chart-results-list-row-container');
  print('Found ${rows.length} rows');
  int count = 0;
  for (var row in rows) {
    if (count > 2) break;
    final titleElement = row.querySelector('h3.c-title');
    final artistElement = titleElement?.nextElementSibling;
    final img = row.querySelector('img.c-lazy-image__img');
    final imgSrc = img?.attributes['data-lazy-src'] ?? img?.attributes['src'];
    print('Title: ${titleElement?.text.trim()} Artist: ${artistElement?.text.trim()} Img: $imgSrc');
    count++;
  }
}
