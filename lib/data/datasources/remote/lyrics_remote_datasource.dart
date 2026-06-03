import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:zyp_music/core/utils/app_logger.dart';

class LyricsRemoteDataSource {
  static const String _baseUrl = 'https://lrclib.net/api/search';

  Future<String?> getSyncedLyrics(String trackName, String artistName) async {
    try {
      final queryParameters = {
        'track_name': trackName,
        'artist_name': artistName,
      };

      final uri = Uri.parse(_baseUrl).replace(queryParameters: queryParameters);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          // Find the first result that has syncedLyrics
          final syncedResult = data.firstWhere(
            (item) => item['syncedLyrics'] != null && item['syncedLyrics'].toString().trim().isNotEmpty,
            orElse: () => null,
          );

          if (syncedResult != null) {
            return syncedResult['syncedLyrics'];
          }
          
          // Fallback to plain lyrics if synced are not available
          final plainResult = data.firstWhere(
            (item) => item['plainLyrics'] != null && item['plainLyrics'].toString().trim().isNotEmpty,
            orElse: () => null,
          );
          
          if (plainResult != null) {
            return plainResult['plainLyrics'];
          }
        }
      } else {
        AppLogger.log('Failed to fetch lyrics. Status code: \${response.statusCode}', name: 'LyricsRemoteDataSource');
      }
    } catch (e) {
      AppLogger.log('Error fetching lyrics from LrcLib: \$e', name: 'LyricsRemoteDataSource');
    }
    return null;
  }
}
