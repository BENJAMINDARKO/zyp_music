import 'package:dart_ytmusic_api/dart_ytmusic_api.dart' as ytm;

void main() async {
  final videoId = 'yUDrOesyhPc';
  final api = ytm.YTMusic();
  try {
    await api.initialize();
    final song = await api.getSong(videoId);
    print('Adaptive formats: ${song.adaptiveFormats?.length}');
    for (var f in song.adaptiveFormats ?? []) {
      if (f['mimeType']?.contains('audio/') == true) {
        print('Audio format url: ${f['url']?.substring(0, 100)}...');
      }
    }
  } catch (e) {
    print('Error: $e');
  }
}
