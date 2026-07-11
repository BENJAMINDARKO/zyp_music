import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_explode;

Future<bool> verifyUrl(String url) async {
  try {
    final client = http.Client();
    final req = http.Request('GET', Uri.parse(url));
    req.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';
    req.headers['Range'] = 'bytes=0-1'; // Request minimal data
    
    final resp = await client.send(req);
    await resp.stream.drain();
    client.close();
    
    print('Verify status: ${resp.statusCode}');
    if (resp.statusCode >= 200 && resp.statusCode < 400) {
      return true;
    }
    return false;
  } catch (e) {
    print('Verify threw: $e');
    return false;
  }
}

void main() async {
  final videoId = 'yUDrOesyhPc';
  final yt = yt_explode.YoutubeExplode();
  final manifest = await yt.videos.streamsClient.getManifest(videoId);
  final mp4Streams = manifest.audioOnly.where((s) => s.container.name == 'mp4');
  final audioInfo = mp4Streams.isNotEmpty 
      ? mp4Streams.withHighestBitrate() 
      : manifest.audioOnly.withHighestBitrate();
  final url = audioInfo.url.toString();
  print('Explode returned URL length: ${url.length}');
  
  final verified = await verifyUrl(url);
  print('Verified: $verified');
}
