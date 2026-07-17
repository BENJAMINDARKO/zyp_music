import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../domain/entities/video.dart';
import '../config/metadata_sync_config.dart';

class GenreFeedbackService {
  static const String _table = 'pending_metadata_suggestions';

  Future<bool> submitGenreSuggestion({
    required Track track,
    required List<String> genres,
    String? country,
    String? notes,
  }) async {
    final endpoint =
        Uri.parse('${MetadataSyncConfig.supabaseUrl}/rest/v1/$_table');

    try {
      final response = await http
          .post(
            endpoint,
            headers: {
              'apikey': MetadataSyncConfig.supabaseAnonKey,
              'Authorization': 'Bearer ${MetadataSyncConfig.supabaseAnonKey}',
              'Content-Type': 'application/json',
              'Prefer': 'return=minimal',
            },
            body: jsonEncode({
              'track_id': track.id,
              'title': track.title,
              'artist_name': track.author ?? 'Unknown Artist',
              'suggested_genres': genres,
              'suggested_country': country,
              'user_notes': notes,
            }),
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }
}
