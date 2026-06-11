String normalise(String str) {
  // Strip punctuation
  var result = str.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '');
  // Strip extra whitespace
  result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
  // Strip feat. suffix and everything after it
  result = result.replaceAll(RegExp(r'\b(feat|ft|featuring|with|vs|&)\b.*$'), '').trim();
  return result;
}

String cleanArtistName(String? name) {
  if (name == null) return '';
  var cleaned = name.trim();
  cleaned = cleaned.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '');
  return cleaned.trim();
}
