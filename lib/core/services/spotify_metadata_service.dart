import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';
import '../../domain/entities/video.dart';
import '../../data/datasources/local/playlist_database.dart';

class SpotifyMetadataService {
  final PlaylistDatabase _db;
  
  String? _accessToken;
  DateTime? _tokenExpiry;

  SpotifyMetadataService({required PlaylistDatabase db}) : _db = db;

  Future<String?> _getToken() async {
    if (_accessToken != null && _tokenExpiry != null && DateTime.now().isBefore(_tokenExpiry!)) {
      return _accessToken;
    }

    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getString('spotifyClientId')?.trim();
    final clientSecret = prefs.getString('spotifyClientSecret')?.trim();

    if (clientId == null || clientId.isEmpty || clientSecret == null || clientSecret.isEmpty) {
      return null;
    }

    try {
      final bytes = utf8.encode('$clientId:$clientSecret');
      final base64Str = base64.encode(bytes);

      final response = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {
          'Authorization': 'Basic $base64Str',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'grant_type': 'client_credentials'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access_token'];
        final expiresIn = data['expires_in'] as int;
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60)); // 1 min buffer
        return _accessToken;
      } else {
        AppLogger.log('Spotify Auth Failed: ${response.statusCode} - ${response.body}', name: 'SpotifyMetadataService');
        return null;
      }
    } catch (e) {
      AppLogger.log('Spotify Auth Exception: $e', name: 'SpotifyMetadataService');
      return null;
    }
  }

  /// Fetches BPM and Energy for a track and saves it to the local database
  Future<void> fetchAudioFeaturesAndGenres(Track track) async {
    // Check if we already have BPM to avoid unnecessary API calls
    final existingBpm = await _db.getTrackBpm(track.id);
    if (existingBpm != null) return;

    final token = await _getToken();
    if (token == null) return;

    try {
      final title = track.title.replaceAll(RegExp(r'[^\w\s]'), '');
      final author = track.author?.replaceAll(RegExp(r'[^\w\s]'), '') ?? '';
      final query = Uri.encodeComponent('track:$title artist:$author');
      
      final searchRes = await http.get(
        Uri.parse('https://api.spotify.com/v1/search?q=$query&type=track&limit=1'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (searchRes.statusCode != 200) return;
      final searchData = jsonDecode(searchRes.body);
      final tracks = searchData['tracks']?['items'] as List?;
      if (tracks == null || tracks.isEmpty) return;

      final trackObj = tracks.first;
      final spotifyTrackId = trackObj['id'];

      // Fetch Audio Features
      if (spotifyTrackId != null) {
        final afRes = await http.get(
          Uri.parse('https://api.spotify.com/v1/audio-features/$spotifyTrackId'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (afRes.statusCode == 200) {
          final afData = jsonDecode(afRes.body);
          final bpm = (afData['tempo'] as num?)?.toDouble();
          final energy = (afData['energy'] as num?)?.toDouble();

          if (bpm != null && bpm > 0) {
            await _db.setTrackBpm(track.id, bpm);
          }
          if (energy != null && energy > 0) {
            await _db.setTrackEnergy(track.id, energy);
          }
        }
      }
    } catch (e) {
      AppLogger.log('Spotify Metadata Fetch Exception: $e', name: 'SpotifyMetadataService');
    }
  }

  /// Fetches primary genres for an artist
  Future<List<String>> getArtistGenres(String artistName) async {
    final token = await _getToken();
    if (token == null) return [];

    try {
      final query = Uri.encodeComponent('artist:$artistName');
      final searchRes = await http.get(
        Uri.parse('https://api.spotify.com/v1/search?q=$query&type=artist&limit=1'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (searchRes.statusCode != 200) return [];
      final searchData = jsonDecode(searchRes.body);
      final artists = searchData['artists']?['items'] as List?;
      if (artists == null || artists.isEmpty) return [];

      final genresList = artists.first['genres'] as List?;
      if (genresList == null || genresList.isEmpty) return [];

      return genresList.map((e) => e.toString()).toList();
    } catch (e) {
      AppLogger.log('Spotify Genre Fetch Exception: $e', name: 'SpotifyMetadataService');
      return [];
    }
  }
}
