/// YouTube Music thumbnail URL rewriting.
///
/// YouTube Music serves artwork at a fixed set of resolutions
/// via the `=w<width>-h<height>-l<low>-rj` URL fragment
/// appended to a `lh3.googleusercontent.com` path. The
/// mobile client picks a single resolution per surface —
/// list rows use 120×120, card grids use 544×544, the
/// full-screen player uses 1200×1200 — and never re-asks
/// the network for a higher resolution once the page is
/// rendered. The default of 544 is the YouTube Music
/// "large thumbnail" used in albums, playlists, and search
/// cards; the renderer can override per surface via
/// [rewriteThumbnailSize].
///
/// Implemented as a top-level function (not an extension
/// method) so callers can pass a nullable `String?` directly
/// without an explicit null-assert, and the rewrite logic is
/// unambiguous in the analyzer regardless of which file is
/// importing it. The function returns an empty string for
/// `null` / empty input so call sites that pass the result
/// straight into `imageUrl:` (which expects a non-null
/// `String`) do not need a fallback.
String rewriteThumbnailSize(String? url, [int size = 544]) {
  if (url == null || url.isEmpty) return '';
  if (!url.contains('lh3.googleusercontent.com')) return url;
  final pattern = RegExp(r'=[^=]*$');
  final replacement = '=w$size-h$size-l90-rj';
  if (pattern.hasMatch(url)) {
    return url.replaceFirst(pattern, replacement);
  }
  return '$url$replacement';
}
