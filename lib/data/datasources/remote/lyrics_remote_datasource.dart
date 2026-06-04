import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:zyp_music/core/utils/app_logger.dart';

class LyricsRemoteDataSource {
  static const String _baseUrl = 'https://lrclib.net/api/search';

  LyricsRemoteDataSource();

  /// Signals that the upstream network is back and the next
  /// [getSyncedLyrics] call should be allowed to hit the engines again.
  ///
  /// Called by [ConnectivityService] on an `offline -> online` transition.
  /// The data source itself is intentionally stateless — every call
  /// constructs a fresh `http.Client` — so there is no socket to
  /// reconnect. This method exists as the explicit contract for the
  /// connectivity listener and as a log hook for observability.
  void retryPendingConnections() {
    AppLogger.log(
      'Retrying pending lyrics connections after connectivity restoration',
      name: 'LyricsRemoteDataSource',
    );
  }

  /// Fetches synced (LRC) lyrics for the given track from LrcLib.
  Future<String?> getSyncedLyrics(String trackName, String artistName) async {
    return _fetchFromLrcLib(trackName, artistName);
  }

  Future<String?> _fetchFromLrcLib(String trackName, String artistName) async {
    try {
      AppLogger.log(
        'Attempting LrcLib fetch for "$trackName" by "$artistName"',
        name: 'LyricsRemoteDataSource',
      );
      final queryParameters = {
        'track_name': trackName,
        'artist_name': artistName,
      };

      final uri = Uri.parse(_baseUrl).replace(queryParameters: queryParameters);
      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        AppLogger.log(
          'LrcLib response: 200. Found ${data.length} results.',
          name: 'LyricsRemoteDataSource',
        );
        if (data.isNotEmpty) {
          // Find the first result that has syncedLyrics
          final syncedResult = data.firstWhere(
            (item) => item['syncedLyrics'] != null && item['syncedLyrics'].toString().trim().isNotEmpty,
            orElse: () => null,
          );

          if (syncedResult != null) {
            AppLogger.log(
              'LrcLib: Found synced lyrics in results.',
              name: 'LyricsRemoteDataSource',
            );
            return syncedResult['syncedLyrics'];
          }

          // Fallback to plain lyrics if synced are not available
          final plainResult = data.firstWhere(
            (item) => item['plainLyrics'] != null && item['plainLyrics'].toString().trim().isNotEmpty,
            orElse: () => null,
          );

          if (plainResult != null) {
            AppLogger.log(
              'LrcLib: Synced lyrics not found. Falling back to plain lyrics.',
              name: 'LyricsRemoteDataSource',
            );
            return plainResult['plainLyrics'];
          }
        }
      } else {
        AppLogger.log(
          'Failed to fetch lyrics from LrcLib. Status code: ${response.statusCode}',
          name: 'LyricsRemoteDataSource',
        );
      }
    } catch (e) {
      AppLogger.log(
        'Error fetching lyrics from LrcLib: $e',
        name: 'LyricsRemoteDataSource',
      );
    }
    return null;
  }
}
