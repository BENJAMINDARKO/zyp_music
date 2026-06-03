import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import '../../../domain/entities/album.dart';
import '../../models/playlist_model.dart';
import '../../models/video_model.dart';
import 'youtube_remote_datasource.dart';
import '../../../core/utils/app_logger.dart';

class ChartsRemoteDataSource {
  final YoutubeRemoteDataSource youtubeDataSource;

  ChartsRemoteDataSource({required this.youtubeDataSource});

  Future<List<TrackModel>> getGhanaTopSongs() async {
    final List<TrackModel> mappedTracks = [];
    try {
      final response = await http.get(Uri.parse('https://music.apple.com/gh/playlist/top-100-ghana/pl.78f1974e882d4952b26ebfb8e017c933'));
      if (response.statusCode == 200) {
        final document = parser.parse(response.body);
        final script = document.querySelector('script#serialized-server-data');
        if (script != null) {
          final root = jsonDecode(script.innerHtml) as Map<String, dynamic>;
          final sections = root['data'][0]['data']['sections'] as List;
          final tracksList = sections.firstWhere((s) => s['items'] != null && (s['items'] as List).length > 20)['items'] as List;
          
          List<String> queries = [];
          for (var t in tracksList) {
            final title = t['title'];
            final artist = t['artistName'] ?? '';
            if (title != null) {
              queries.add('$title $artist');
            }
          }

          // Process in chunks to resolve YouTube IDs fast
          const chunkSize = 10;
          for (var i = 0; i < queries.length; i += chunkSize) {
            final chunk = queries.sublist(i, i + chunkSize > queries.length ? queries.length : i + chunkSize);
            final futures = chunk.map((query) async {
              try {
                final searchResults = await youtubeDataSource.searchTracks(query);
                if (searchResults.isNotEmpty) {
                  return searchResults.first;
                }
              } catch (searchError) {
                AppLogger.log('Error searching for song $query: $searchError', name: 'ChartsRemoteDataSource');
              }
              return null;
            });
            
            final results = await Future.wait(futures);
            for (var track in results) {
              if (track != null) {
                mappedTracks.add(track);
              }
            }
          }
        }
      }
    } catch (e) {
      AppLogger.log('Failed to fetch Ghana Top Songs from Apple Music: $e', name: 'ChartsRemoteDataSource');
    }
    return mappedTracks;
  }

  Future<List<TrackModel>> getGlobalTopSongs() async {
    final List<TrackModel> mappedTracks = [];
    try {
      final response = await http.get(Uri.parse('https://music.apple.com/us/playlist/top-100-global/pl.d25f5d1181894928af76c85c967f8f31'));
      if (response.statusCode == 200) {
        final document = parser.parse(response.body);
        final script = document.querySelector('script#serialized-server-data');
        if (script != null) {
          final root = jsonDecode(script.innerHtml) as Map<String, dynamic>;
          final sections = root['data'][0]['data']['sections'] as List;
          final tracksList = sections.firstWhere((s) => s['items'] != null && (s['items'] as List).length > 20)['items'] as List;
          
          List<String> queries = [];
          for (var t in tracksList) {
            final title = t['title'];
            final artist = t['artistName'] ?? '';
            if (title != null) {
              queries.add('$title $artist');
            }
          }

          const chunkSize = 10;
          for (var i = 0; i < queries.length; i += chunkSize) {
            final chunk = queries.sublist(i, i + chunkSize > queries.length ? queries.length : i + chunkSize);
            final futures = chunk.map((query) async {
              try {
                final searchResults = await youtubeDataSource.searchTracks(query);
                if (searchResults.isNotEmpty) {
                  return searchResults.first;
                }
              } catch (searchError) {
                AppLogger.log('Error searching for song $query: $searchError', name: 'ChartsRemoteDataSource');
              }
              return null;
            });
            
            final results = await Future.wait(futures);
            for (var track in results) {
              if (track != null) {
                mappedTracks.add(track);
              }
            }
          }
        }
      }
    } catch (e) {
      AppLogger.log('Failed to fetch Global Top Songs from Apple Music: $e', name: 'ChartsRemoteDataSource');
    }
    return mappedTracks;
  }

  Future<List<Album>> getBillboard200() async {
    final List<Album> albums = [];
    try {
      final response = await http.get(Uri.parse('https://www.billboard.com/charts/billboard-200/'), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
      });

      if (response.statusCode == 200) {
        final document = parser.parse(response.body);
        
        final rows = document.querySelectorAll('.o-chart-results-list-row-container');
        
        // Fetch up to 150 items
        final limit = rows.length > 150 ? 150 : rows.length;
        
        // Prepare list of queries
        List<String> queries = [];
        for (var i = 0; i < limit; i++) {
          final row = rows[i];
          final titleElement = row.querySelector('h3.c-title');
          final artistElement = titleElement?.nextElementSibling;
          
          if (titleElement != null && artistElement != null) {
            final title = titleElement.text.trim();
            final artist = artistElement.text.trim();
            if (title.isNotEmpty && artist.isNotEmpty) {
              queries.add('$title $artist');
            }
          }
        }
        
        // Process in chunks of 5 to avoid overwhelming the network
        const chunkSize = 5;
        for (var i = 0; i < queries.length; i += chunkSize) {
          final chunk = queries.sublist(i, i + chunkSize > queries.length ? queries.length : i + chunkSize);
          final futures = chunk.map((query) async {
            try {
              final searchResults = await youtubeDataSource.searchAlbums(query);
              if (searchResults.isNotEmpty) {
                return searchResults.first;
              }
            } catch (searchError) {
              AppLogger.log('Error searching for album $query: $searchError', name: 'ChartsRemoteDataSource');
            }
            return null;
          });
          
          final results = await Future.wait(futures);
          for (var album in results) {
            if (album != null) {
              albums.add(album);
            }
          }
        }
      } else {
        AppLogger.log('Billboard HTTP error: ${response.statusCode}', name: 'ChartsRemoteDataSource');
      }
    } catch (e) {
      AppLogger.log('Failed to fetch Billboard 200: $e', name: 'ChartsRemoteDataSource');
    }
    return albums;
  }
}
