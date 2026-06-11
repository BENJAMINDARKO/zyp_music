void main() {
  String rewriteThumbnailSize(String? url, [int size = 544]) {
    if (url == null || url.isEmpty) return '';
    if (url.contains('lh3.googleusercontent.com')) {
      final pattern = RegExp(r'=[^=]*$');
      final replacement = '=w$size-h$size-l90-rj';
      if (pattern.hasMatch(url)) {
        return url.replaceFirst(pattern, replacement);
      }
      return '$url$replacement';
    } else if (url.contains('i.ytimg.com')) {
      final uri = Uri.tryParse(url);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        final last = uri.pathSegments.last;
        if (last.endsWith('.jpg')) {
          final newLast = size > 500 ? 'maxresdefault.jpg' : 'hqdefault.jpg';
          return url.replaceFirst(last, newLast);
        }
      }
    }
    return url;
  }

  print(rewriteThumbnailSize('https://lh3.googleusercontent.com/abc=w120-h120-l90-rj', 1200));
  print(rewriteThumbnailSize('https://lh3.googleusercontent.com/abc', 1200));
}
