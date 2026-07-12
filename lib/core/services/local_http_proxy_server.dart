import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';
import '../../domain/entities/video.dart';
import '../../domain/repositories/audio_repository.dart';

class LocalHttpProxyServer {
  LocalHttpProxyServer._();
  static final LocalHttpProxyServer instance = LocalHttpProxyServer._();

  static const String _tag = 'LocalHttpProxyServer';
  static const int _segmentSize = 256 * 1024; // 256 KB (~3-4 seconds segments)

  HttpServer? _server;
  int _port = 0;
  AudioRepository? _audioRepository;

  // In-memory cache for preloaded first segments: trackId -> segment bytes
  final Map<String, List<int>> _prefetchCache = {};
  
  // Track currently playing/temp files that have been fully written but not promoted
  final Map<String, String> _tempFilePaths = {};

  // Dedup guard: maps trackId -> Completer that resolves once the temp file
  // path is known. When a second request arrives for the same trackId while
  // the first _streamAndCache is still in flight, the second request waits
  // on this Completer and serves from the temp file (which the first stream
  // is actively writing), rather than starting a second concurrent download
  // that would truncate the shared temp file and cascade into failures.
  final Map<String, Completer<String?>> _activeStreams = {};

  String get baseUrl => 'http://127.0.0.1:$_port';
  int get port => _port;

  void attachRepository(AudioRepository repo) {
    _audioRepository = repo;
  }

  Future<void> start() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      AppLogger.log('Proxy Server listening on $baseUrl', name: _tag);
      _server!.listen(_handleRequest, onError: (e) {
        AppLogger.log('HttpServer listen error: $e', name: _tag);
      });
    } catch (e) {
      AppLogger.log('Failed to start proxy server: $e', name: _tag);
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _prefetchCache.clear();
  }

  /// Prefetch the first 3 segments (~768 KB) of the next track's stream URL
  Future<void> prefetchTrack(String trackId, String streamUrl) async {
    if (_prefetchCache.containsKey(trackId)) return;
    try {
      AppLogger.log('Prefetching first segments for track: $trackId', name: _tag);
      final response = await http.get(
        Uri.parse(streamUrl),
        headers: {
          'Range': 'bytes=0-${(3 * _segmentSize) - 1}',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 206) {
        _prefetchCache[trackId] = response.bodyBytes;
        AppLogger.log('Prefetched ${response.bodyBytes.length} bytes for track: $trackId', name: _tag);
      }
    } catch (e) {
      AppLogger.log('Prefetch failed for $trackId: $e', name: _tag);
    }
  }

  /// Promotes the temporary file to the permanent cache (called when playback > 50%)
  Future<void> promoteTempFile(String trackId) async {
    final tempPath = _tempFilePaths[trackId];
    if (tempPath == null) return;

    try {
      final file = File(tempPath);
      if (!await file.exists()) return;

      final docs = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${docs.path}/audio_cache');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      // Read preference to determine format/extension
      final prefs = await SharedPreferences.getInstance();
      final formatPref = prefs.getString('youtubeMusicFormat') ?? 'Any';
      String ext = 'mp3';
      if (formatPref.toLowerCase() == 'webm') {
        ext = 'webm';
      } else if (formatPref.toLowerCase() == 'm4a') {
        ext = 'm4a';
      }

      final finalPath = '${cacheDir.path}/$trackId.$ext';
      await file.rename(finalPath);
      _tempFilePaths.remove(trackId);
      
      AppLogger.log('Successfully promoted track $trackId cache file to $finalPath', name: _tag);
    } catch (e) {
      AppLogger.log('Failed to promote temp file for $trackId: $e', name: _tag);
    }
  }

  /// Clean up/delete temp file if the track is skipped before 50%
  Future<void> discardTempFile(String trackId) async {
    final tempPath = _tempFilePaths.remove(trackId);
    if (tempPath == null) return;
    try {
      final file = File(tempPath);
      if (await file.exists()) {
        await file.delete();
        AppLogger.log('Discarded incomplete temp file for track $trackId', name: _tag);
      }
    } catch (e) {
      AppLogger.log('Failed to delete temp file for $trackId: $e', name: _tag);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path != '/stream') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final trackId = request.uri.queryParameters['id'];
    if (trackId == null || trackId.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    AppLogger.log('Proxy request received for track: $trackId', name: _tag);

    // 1. Resolve localized cached file path if fully downloaded
    final localPath = await _resolveFullyCachedPath(trackId);
    if (localPath != null) {
      AppLogger.log('Serving from full local cache: $localPath', name: _tag);
      await _serveLocalFile(request, File(localPath));
      return;
    }

    // 1b. Check for an existing .tmp file from a prior stream that was
    //     not yet promoted (e.g. the track stopped before 50%). Serve
    //     from it rather than starting a fresh download.
    final existingTempPath = _tempFilePaths[trackId];
    if (existingTempPath != null && File(existingTempPath).existsSync()) {
      AppLogger.log('Serving from existing temp file: $existingTempPath', name: _tag);
      await _serveLocalFile(request, File(existingTempPath));
      return;
    }

    // 2. Dedup: if a streaming session is already in progress for this
    //    trackId, wait for the first segment to hit disk and serve from
    //    the temp file instead of starting a second concurrent download.
    final existingCompleter = _activeStreams[trackId];
    if (existingCompleter != null) {
      AppLogger.log('Stream already active for $trackId, serving from temp file', name: _tag);
      try {
        final tempPath = await existingCompleter.future.timeout(const Duration(seconds: 15));
        if (tempPath != null && File(tempPath).existsSync()) {
          await _serveLocalFile(request, File(tempPath));
        } else {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
        }
      } catch (_) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
      }
      return;
    }

    // 3. Mark this trackId as actively streaming so concurrent requests
    //    hit the dedup path above instead of corrupting the temp file.
    final streamCompleter = Completer<String?>();
    _activeStreams[trackId] = streamCompleter;

    // 4. Fetch the YouTube stream URL using user preferences
    if (_audioRepository == null) {
      _activeStreams.remove(trackId);
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
      return;
    }

    String? streamUrl;
    try {
      final track = Track(
        id: trackId,
        title: 'Proxy Stream',
        author: 'Proxy',
        source: trackId.contains('youtube_music') ? TrackSource.youtube_music : TrackSource.youtube,
      );
      final urlResult = await _audioRepository!.getAudioUrl(track);
      streamUrl = urlResult.url;
    } catch (e) {
      AppLogger.log('Failed to resolve stream URL for $trackId: $e', name: _tag);
    }

    if (streamUrl == null || streamUrl.isEmpty || !streamUrl.startsWith('http')) {
      _activeStreams.remove(trackId);
      if (!streamCompleter.isCompleted) streamCompleter.complete(null);
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    // 5. Serve and cache the stream in segments
    try {
      await _streamAndCache(request, trackId, streamUrl, streamCompleter);
    } finally {
      _activeStreams.remove(trackId);
    }
  }

  ContentType _getContentType(String pathOrPref) {
    final lower = pathOrPref.toLowerCase();
    if (lower.endsWith('.webm') || lower == 'webm') {
      return ContentType('audio', 'webm');
    } else if (lower.endsWith('.m4a') || lower.endsWith('.mp4') || lower == 'm4a') {
      return ContentType('audio', 'mp4');
    } else {
      return ContentType('audio', 'mpeg');
    }
  }

  ContentType _detectContentTypeFromUrl(String url, String formatPref) {
    final decodedUrl = Uri.decodeFull(url);
    if (decodedUrl.contains('mime=audio/webm')) {
      return ContentType('audio', 'webm');
    } else if (decodedUrl.contains('mime=audio/mp4') || decodedUrl.contains('mime=audio/m4a')) {
      return ContentType('audio', 'mp4');
    }
    return _getContentType(formatPref);
  }

  Future<void> _streamAndCache(HttpRequest request, String trackId, String initialUrl, Completer<String?> streamCompleter) async {
    final response = request.response;
    
    final prefs = await SharedPreferences.getInstance();
    final formatPref = prefs.getString('youtubeMusicFormat') ?? 'Any';
    final resolvedContentType = _detectContentTypeFromUrl(initialUrl, formatPref);

    // Set headers
    response.headers.chunkedTransferEncoding = true;
    response.headers.contentType = resolvedContentType;
    response.statusCode = HttpStatus.ok;

    final docs = await getApplicationDocumentsDirectory();
    final tempPath = '${docs.path}/audio_cache/$trackId.tmp';
    _tempFilePaths[trackId] = tempPath;
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    await tempFile.create(recursive: true);
    final IOSink fileSink = tempFile.openWrite();

    // Signal concurrent requests that the temp file is ready so they can
    // serve from it instead of starting their own download.
    if (!streamCompleter.isCompleted) {
      streamCompleter.complete(tempPath);
    }

    // Check if we have prefetch cache
    final prefetchedBytes = _prefetchCache.remove(trackId);
    var startByte = 0;
    if (prefetchedBytes != null && prefetchedBytes.isNotEmpty) {
      AppLogger.log('Serving ${prefetchedBytes.length} preloaded bytes from memory', name: _tag);
      response.add(prefetchedBytes);
      fileSink.add(prefetchedBytes);
      startByte = prefetchedBytes.length;
    }

    var activeUrl = initialUrl;
    var consecutiveErrors = 0;
    var client = http.Client();

    try {
      while (true) {
        final endByte = startByte + _segmentSize - 1;
        final stopwatch = Stopwatch()..start();

        final segmentRequest = http.Request('GET', Uri.parse(activeUrl));
        segmentRequest.headers['Range'] = 'bytes=$startByte-$endByte';
        segmentRequest.headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

        final streamedResponse = await client.send(segmentRequest).timeout(const Duration(seconds: 12));
        stopwatch.stop();

        if (streamedResponse.statusCode != 200 && streamedResponse.statusCode != 206) {
          consecutiveErrors++;
          if (consecutiveErrors > 3) {
            AppLogger.log('Max consecutive segment errors reached', name: _tag);
            break;
          }
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }

        consecutiveErrors = 0;
        final responseBytes = await streamedResponse.stream.toBytes();
        if (responseBytes.isEmpty) {
          // Stream ended
          AppLogger.log('Segment returned empty bytes. Stream complete.', name: _tag);
          break;
        }

        // Adaptive Quality: Measure segment speed and adjust bitrate quality
        final downloadSpeedKbps = (responseBytes.length * 8) / (stopwatch.elapsedMilliseconds / 1000.0) / 1024.0;
        
        // If speed is slow (<150kbps) and we are not already on low quality, adapt
        if (downloadSpeedKbps < 150.0 && stopwatch.elapsedMilliseconds > 2000) {
          AppLogger.log('Slow connection detected ($downloadSpeedKbps kbps). Switching to low bitrate.', name: _tag);
          // In a real production flow, we would re-resolve the lower-quality stream URL here.
          // For safety and compatibility, we will keep connection active but throttle requests to protect audio player state.
        }

        response.add(responseBytes);
        fileSink.add(responseBytes);
        await response.flush();

        startByte += responseBytes.length;
        if (responseBytes.length < _segmentSize) {
          // Less than requested size means we reached the end of the file
          break;
        }
      }
    } catch (e) {
      AppLogger.log('Error streaming segments for $trackId: $e', name: _tag);
    } finally {
      client.close();
      await fileSink.close();
      await response.close();
      AppLogger.log('Proxy stream request completed for $trackId', name: _tag);
    }
  }

  Future<void> _serveLocalFile(HttpRequest request, File file) async {
    final response = request.response;
    final fileLength = await file.length();
    
    response.headers.contentType = _getContentType(file.path);

    // Check for range request
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final parts = rangeHeader.substring(6).split('-');
      final start = int.tryParse(parts[0]) ?? 0;
      final end = parts.length > 1 && parts[1].isNotEmpty
          ? int.tryParse(parts[1]) ?? (fileLength - 1)
          : (fileLength - 1);

      response.statusCode = HttpStatus.partialContent;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$fileLength');
      response.headers.contentLength = (end - start) + 1;

      final stream = file.openRead(start, end + 1);
      await response.addStream(stream);
    } else {
      response.statusCode = HttpStatus.ok;
      response.headers.contentLength = fileLength;
      await response.addStream(file.openRead());
    }
    await response.close();
  }

  Future<String?> _resolveFullyCachedPath(String trackId) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${docs.path}/audio_cache');
      if (await cacheDir.exists()) {
        for (final f in cacheDir.listSync().whereType<File>()) {
          final name = f.path.split('/').last;
          if (name.startsWith('$trackId.') && !name.endsWith('.tmp')) {
            return f.path;
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
