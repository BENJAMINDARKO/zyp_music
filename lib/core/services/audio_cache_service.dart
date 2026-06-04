import 'dart:convert';
import 'package:zyp_music/core/utils/app_logger.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioCacheService {
  static const int _maxCachedItems = 200;
  static const String _prefsKey = 'audio_cache_lru';

  /// Optional notifier fired after a stream write completes successfully.
  /// Receives the `(trackId, finalFilePath)` so the caller can register the
  /// new cache entry in its own index (e.g. a Hive box) without coupling
  /// this service to that index.
  ///
  /// Errors raised inside the callback are swallowed; the file is already
  /// on disk and the next reconcile pass can pick it up if the index update
  /// did not land.
  Future<void> Function(String trackId, String filePath)? onCacheSuccess;

  /// Returns the local file URI if the track is cached, otherwise null.
  Future<String?> getCachedUri(String trackId) async {
    try {
      final cacheDir = await _getCacheDir();
      if (!await cacheDir.exists()) return null;

      final files = cacheDir.listSync().whereType<File>().where((file) {
        final name = file.path.split('/').last;
        return name.startsWith('$trackId.');
      }).toList();

      if (files.isNotEmpty) {
        final file = files.first;
        if (await file.length() > 0) {
          await _updateAccessTime(trackId);
          return file.uri.toString();
        } else {
          // Clean up empty files
          await file.delete();
        }
      }
    } catch (e) {
      AppLogger.log('Error reading cache: $e', name: 'AudioCacheService');
    }
    return null;
  }

  /// Downloads the stream in the background and saves it to the cache.
  Future<void> cacheStream(String trackId, String streamUrl) async {
    try {
      final cacheDir = await _getCacheDir();
      
      // Determine file extension based on streamUrl
      String ext = 'mp3';
      final lowerUrl = streamUrl.toLowerCase();
      if (lowerUrl.contains('.flac')) {
        ext = 'flac';
      } else if (lowerUrl.contains('.webm')) {
        ext = 'webm';
      } else if (lowerUrl.contains('.mp4') || lowerUrl.contains('.m4a') || lowerUrl.contains('.aac')) {
        ext = 'm4a';
      }

      final file = File('${cacheDir.path}/$trackId.$ext');
      
      final existingUri = await getCachedUri(trackId);
      if (existingUri != null) {
        return;
      }

      // Download file to temp location first
      final tmpFile = File('${cacheDir.path}/$trackId.tmp');
      final response = await http.get(
        Uri.parse(streamUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
        },
      );
      if (response.statusCode == 200) {
        await tmpFile.writeAsBytes(response.bodyBytes);
        await tmpFile.rename(file.path);
        await _updateAccessTime(trackId);
        await _enforceCacheLimit();
        final hook = onCacheSuccess;
        if (hook != null) {
          try {
            await hook(trackId, file.path);
          } catch (e) {
            AppLogger.log('onCacheSuccess hook failed for $trackId: $e',
                name: 'AudioCacheService');
          }
        }
      }
    } catch (e) {
      AppLogger.log('Error caching stream: $e', name: 'AudioCacheService');
    }
  }

  Future<void> clearCache() async {
    try {
      final cacheDir = await _getCacheDir();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (e) {
      AppLogger.log('Error clearing cache: $e', name: 'AudioCacheService');
    }
  }

  Future<Directory> _getCacheDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${docs.path}/audio_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  Future<void> _updateAccessTime(String trackId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? lruString = prefs.getString(_prefsKey);
    List<String> lru = lruString != null ? List<String>.from(jsonDecode(lruString)) : [];

    lru.remove(trackId);
    lru.add(trackId); // Add to end (most recently used)

    await prefs.setString(_prefsKey, jsonEncode(lru));
  }

  Future<void> _enforceCacheLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final String? lruString = prefs.getString(_prefsKey);
    if (lruString == null) return;

    List<String> lru = List<String>.from(jsonDecode(lruString));
    
    if (lru.length > _maxCachedItems) {
      final cacheDir = await _getCacheDir();
      int itemsToRemove = lru.length - _maxCachedItems;
      
      for (int i = 0; i < itemsToRemove; i++) {
        final oldestTrackId = lru[0];
        final files = cacheDir.listSync().whereType<File>().where((file) {
          final name = file.path.split('/').last;
          return name.startsWith('$oldestTrackId.');
        }).toList();

        for (final file in files) {
          if (await file.exists()) {
            await file.delete();
          }
        }
        lru.removeAt(0);
      }
      
      await prefs.setString(_prefsKey, jsonEncode(lru));
    }
  }
}
