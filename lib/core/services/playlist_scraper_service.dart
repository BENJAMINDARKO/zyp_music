import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'dart:convert';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_explode;
import '../utils/normalise.dart';
import '../utils/thumbnail_url.dart';

class PlaylistScraperService {

  static Future<Map<String, dynamic>> scrapePlaylist(String url) async {
    if (url.contains('music.apple.com')) {
      return _scrapeAppleMusic(url);
    } else if (url.contains('spotify.com')) {
      return _scrapeSpotify(url);
    } else if (url.contains('youtube.com') || url.contains('youtu.be')) {
      return _scrapeYoutube(url);
    }
    throw Exception('Unsupported playlist URL');
  }

  static Future<Map<String, dynamic>> _scrapeAppleMusic(String url) async {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw Exception('Failed to load Apple Music playlist');
    
    final doc = parser.parse(res.body);
    final script = doc.querySelector('script#serialized-server-data');
    if (script != null) {
      try {
        final root = jsonDecode(script.innerHtml) as Map<String, dynamic>;
        final sections = root['data'][0]['data']['sections'] as List;
        var playlistName = doc.querySelector('meta[property="og:title"]')?.attributes['content'];
        if (playlistName == null || playlistName.isEmpty) {
          playlistName = root['data'][0]['data']['seoData']?['pageTitle']?.toString().split(' -')[0];
        }
        if (playlistName == null || playlistName.isEmpty) {
          final titleText = doc.querySelector('title')?.text ?? '';
          playlistName = titleText.split(' - ')[0].replaceAll(RegExp(r'^\u200E'), '').trim();
        }
        if (playlistName.isEmpty) playlistName = 'Apple Music Playlist';
        final trackSection = sections.firstWhere(
          (s) {
            if (s['items'] == null || (s['items'] as List).isEmpty) return false;
            final firstItem = s['items'][0];
            return firstItem['type'] == 'track' || firstItem['contentDescriptor']?['kind'] == 'song';
          },
          orElse: () => {'items': []},
        );
        final tracks = trackSection['items'] as List;
        
        final mappedTracks = tracks.map((track) {
          final title = track['title']?.toString() ?? '';
          final artist = track['artistName']?.toString() ?? '';
          final artworkUrl = track['artwork']?['dictionary']?['url']?.toString() ?? track['artwork']?['url']?.toString() ?? '';
          var resolvedArt = artworkUrl;
          if (resolvedArt.contains('{w}') && resolvedArt.contains('{h}')) {
            resolvedArt = resolvedArt.replaceAll('{w}', '1200').replaceAll('{h}', '1200');
          }
          return {
            'id': 'importstub_${title.hashCode}_${artist.hashCode}',
            'title': title,
            'artist': artist,
            'albumArt': resolvedArt,
          };
        }).toList();
        
        return {'title': playlistName, 'tracks': mappedTracks};
      } catch (e) {
        throw Exception('Failed to parse Apple Music data: $e');
      }
    }
    throw Exception('Apple Music script tag not found');
  }

  static Future<Map<String, dynamic>> _scrapeSpotify(String url) async {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments;
    
    // Support open.spotify.com/playlist/<ID>
    String? playlistId;
    if (segments.length >= 2 && segments[0] == 'playlist') {
      playlistId = segments[1];
    } else {
      throw Exception('Could not extract playlist ID from Spotify URL');
    }

    final embedUrl = 'https://open.spotify.com/embed/playlist/$playlistId';
    final res = await http.get(Uri.parse(embedUrl), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    }).timeout(const Duration(seconds: 15));
    
    if (res.statusCode != 200) throw Exception('Failed to load Spotify embed page');
    
    final doc = parser.parse(res.body);
    final script = doc.querySelector('script#__NEXT_DATA__');
    if (script == null) {
      throw Exception('Could not find Spotify track data (__NEXT_DATA__)');
    }
    
    try {
      final json = jsonDecode(script.innerHtml) as Map<String, dynamic>;
      final entity = json['props']?['pageProps']?['state']?['data']?['entity'];
      if (entity == null) throw Exception('Spotify JSON structure changed');
      
      final playlistName = entity['name']?.toString() ?? 'Spotify Playlist';
      final trackList = entity['trackList'] as List?;
      if (trackList == null) throw Exception('No tracks found in Spotify playlist');
      
      final mappedTracks = trackList.take(50).map((t) {
        final title = t['title']?.toString() ?? '';
        final subtitle = t['subtitle']?.toString() ?? '';
        
        return {
          'id': 'importstub_${title.hashCode}_${subtitle.hashCode}',
          'title': title,
          'artist': subtitle,
          'albumArt': '', // Leaving it empty string if not found so ytmusic resolver will handle it
        };
      }).toList();
      
      return {'title': playlistName, 'tracks': mappedTracks};
    } catch (e) {
      throw Exception('Failed to parse Spotify data: $e');
    }
  }

  static Future<Map<String, dynamic>> _scrapeYoutube(String url) async {
    try {
      final uri = Uri.parse(url);
      final listId = uri.queryParameters['list'];
      if (listId == null) throw Exception('No list parameter found in YouTube URL');
      
      final yt = yt_explode.YoutubeExplode();
      try {
        final playlist = await yt.playlists.get(listId);
        final videos = await yt.playlists.getVideos(listId).take(100).toList();
        
        if (videos.isEmpty) throw Exception('YouTube Playlist is empty or private');
        
        final mappedTracks = videos.map((track) {
          return {
            'id': track.id.value,
            'title': track.title,
            'artist': cleanArtistName(track.author),
            'albumArt': rewriteThumbnailSize(track.thumbnails.highResUrl.toString(), 1200),
          };
        }).toList();
        
        return {'title': playlist.title, 'tracks': mappedTracks};
      } finally {
        yt.close();
      }
    } catch (e) {
      throw Exception('Failed to fetch YouTube playlist: $e');
    }
  }
}
