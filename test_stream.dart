import 'package:youtube_explode_dart/youtube_explode_dart.dart';
void main() async {
  final yt = YoutubeExplode();
  try {
    final manifest = await yt.videos.streamsClient.getManifest('O7Q4vYvaBdc');
    print(manifest.audioOnly.withHighestBitrate().url);
  } catch (e) {
    print("Error: $e");
  } finally {
    yt.close();
  }
}
