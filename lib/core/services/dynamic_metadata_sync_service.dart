import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/metadata_sync_config.dart';

class DynamicMetadataSyncService {
  static const String _lastSyncKey = 'metadata_last_sync_timestamp';
  static const int _syncIntervalDays = 7;

  Future<void> syncIfRequired() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getInt(_lastSyncKey) ?? 0;
    final currentTimestamp = DateTime.now().millisecondsSinceEpoch;

    if (currentTimestamp - lastSync <
        _syncIntervalDays * 24 * 60 * 60 * 1000) {
      return;
    }

    try {
      await _syncFile(MetadataSyncConfig.proximityMatrixCdnUrl,
          MetadataSyncConfig.proximityFilename);
      await _syncFile(MetadataSyncConfig.normalizationCdnUrl,
          MetadataSyncConfig.normalizationFilename);
      await _syncFile(MetadataSyncConfig.countryRegionCdnUrl,
          MetadataSyncConfig.countryRegionFilename);

      await prefs.setInt(_lastSyncKey, currentTimestamp);
    } catch (e) {
      // Silent fail — next sync attempt will retry
    }
  }

  Future<void> _syncFile(String url, String localTargetFilename) async {
    final response =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}');
    }

    final docDir = await getApplicationDocumentsDirectory();
    final tempFile = File('${docDir.path}/$localTargetFilename.tmp');
    final targetFile = File('${docDir.path}/$localTargetFilename');

    await tempFile.writeAsString(response.body);

    try {
      final parsed = jsonDecode(response.body);
      if (parsed is! Map) {
        throw const FormatException('Root must be a Map');
      }
    } catch (e) {
      if (await tempFile.exists()) await tempFile.delete();
      rethrow;
    }

    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    await tempFile.rename(targetFile.path);
  }
}
