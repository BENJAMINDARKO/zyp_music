void main() {
  List<Map<String, String>> mappedTracks = [
    {'id': '1', 'title': 'song'}
  ];
  List<dynamic> scrapedTracks = mappedTracks;
  try {
    var res = scrapedTracks.cast<Map<String, dynamic>>();
    print('Cast success: $res');
    
    // BUT what if we try to access it? cast is lazy!
    print(res.first);
  } catch (e) {
    print('Cast failed: $e');
  }
}
