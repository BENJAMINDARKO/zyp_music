import 'dart:convert';
import 'package:zyp_music/core/utils/app_logger.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioCacheService {
  static const int _maxCachedItems = 200;
  static const String _prefsKey = 'audio_cache_lru';

  /// Returns the local file URI if the track is cached, otherwise null.
  Future<String?> getCachedUri(String trackId) async {
    try {
      final cacheDir = await _getCacheDir();
      final file = File('${cacheDir.path}/$trackId.mp3');
      if (await file.exists()) {
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
      final file = File('${cacheDir.path}/$trackId.mp3');
      
      if (await file.exists() && await file.length() > 0) {
        await _updateAccessTime(trackId);
        return;
      }

      // Download file to temp location first
      final tmpFile = File('${cacheDir.path}/$trackId.tmp');
      final response = await http.get(Uri.parse(streamUrl));
      if (response.statusCode == 200) {
        await tmpFile.writeAsBytes(response.bodyBytes);
        await tmpFile.rename(file.path);
        await _updateAccessTime(trackId);
        await _enforceCacheLimit();
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
        final file = File('${cacheDir.path}/$oldestTrackId.mp3');
        if (await file.exists()) {
          await file.delete();
        }
        lru.removeAt(0);
      }
      
      await prefs.setString(_prefsKey, jsonEncode(lru));
    }
  }
}
