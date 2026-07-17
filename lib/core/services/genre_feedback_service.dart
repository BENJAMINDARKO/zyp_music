import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/metadata_sync_config.dart';
import '../../domain/entities/video.dart';

class GenreFeedbackService {
  static const String _table = 'pending_metadata_suggestions';

  Future<bool> submitTrackSuggestion({
    required Track track,
    required List<String> genres,
    String? country,
  }) async {
    return _sendToSupabase({
      'target_type': 'track',
      'track_id': track.id,
      'title': track.title,
      'artist_name': track.author ?? 'Unknown Artist',
      'suggested_genres': genres,
      'suggested_country': country,
    });
  }

  Future<bool> submitArtistSuggestion({
    required String artistName,
    required List<String> genres,
    String? country,
  }) async {
    return _sendToSupabase({
      'target_type': 'artist',
      'artist_name': artistName,
      'suggested_genres': genres,
      'suggested_country': country,
      'track_id': null,
      'title': null,
    });
  }

  Future<bool> _sendToSupabase(Map<String, dynamic> body) async {
    final endpoint =
        Uri.parse('${MetadataSyncConfig.supabaseUrl}/rest/v1/$_table');
    try {
      final response = await http
          .post(
            endpoint,
            headers: {
              'apikey': MetadataSyncConfig.supabaseAnonKey,
              'Authorization':
                  'Bearer ${MetadataSyncConfig.supabaseAnonKey}',
              'Content-Type': 'application/json',
              'Prefer': 'return=minimal',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }
}
