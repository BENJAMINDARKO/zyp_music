import 'package:dart_ytmusic_api/dart_ytmusic_api.dart' as ytm;
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  await Hive.initFlutter();
  final box = await Hive.openBox('authBox');
  final cookies = box.get('cookies');
  print('Cookies: ${cookies?.substring(0, 50)}');

  final videoId = 'yUDrOesyhPc';
  final api = ytm.YTMusic();
  try {
    await api.initialize(cookies: cookies);
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
