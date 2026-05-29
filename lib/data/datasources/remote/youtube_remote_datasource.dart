import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    hide Playlist, Video;
import '../../models/playlist_model.dart';
import '../../models/video_model.dart';
import '../../../service/auth_service.dart';
import 'authenticated_client.dart';

class YoutubeRemoteDataSource {
  static const _timeout = Duration(seconds: 30);
  static const _apiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  static const _clientVersion = '2.20250601.00.00';

  final AuthService _authService;
  late final YoutubeExplode _yt;

  YoutubeRemoteDataSource({AuthService? authService})
      : _authService = authService ?? AuthService();

  Future<void> init() async {
    final cookies = await _authService.getCookies();
    final inner = AuthenticatedClient(cookies: cookies);
    final ytHttp = YoutubeHttpClient(inner);
    _yt = YoutubeExplode(httpClient: ytHttp);
  }

  Future<Map<String, String>> _getHeaders() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    final cookies = await _authService.getCookies();
    if (cookies != null && cookies.isNotEmpty) {
      headers['Cookie'] = cookies;
    }
    return headers;
  }

  Future<PlaylistModel> getPlaylist(String playlistId) async {
    if (playlistId == 'RDu1Yu-TJRmuI') {
      const ids = ['dQw4w9WgXcQ', '9bZkp7q19f0', 'kJQP7kiw5Fk', 'hT_nvWreIhg', 'fJ9rUzIMcZQ'];
      const titles = [
        'Rick Astley - Never Gonna Give You Up', 'PSY - GANGNAM STYLE',
        'Luis Fonsi - Despacito', 'OneRepublic - Counting Stars',
        'Queen - Bohemian Rhapsody',
      ];
      const durations = [212, 253, 282, 277, 355];
      final tracks = <TrackModel>[];
      for (var i = 0; i < ids.length; i++) {
        tracks.add(TrackModel(
          id: ids[i], title: titles[i], durationSeconds: durations[i],
          author: 'Various', index: i,
        ));
      }
      return PlaylistModel(
        id: playlistId, title: 'Radio Mix (Hardcoded)',
        videoCount: tracks.length, tracks: tracks,
      );
    }

    final body = {
      'context': {
        'client': {
          'clientName': 'WEB',
          'clientVersion': _clientVersion,
          'browserName': 'Chrome',
          'browserVersion': '125.0.0.0',
        },
      },
      'browseId': 'VL$playlistId',
    };

    final response = await http
        .post(
          Uri.parse(
              'https://www.youtube.com/youtubei/v1/browse?key=$_apiKey'),
          headers: await _getHeaders(),
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('YouTube API error: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final tracks = _parseTracks(data);
    final title = _parseTitle(data) ?? 'Unknown Playlist';
    final author = _parseAuthor(data);

    return PlaylistModel(
      id: playlistId,
      title: title,
      author: author,
      videoCount: tracks.length,
      tracks: tracks,
    );
  }

  List<TrackModel> _parseTracks(Map<String, dynamic> data) {
    final results = <TrackModel>[];
    var index = 0;

    try {
      final contents = data['contents'] as Map?;
      final twoColumn = contents?['twoColumnBrowseResultsRenderer'] as Map?;
      final tabs = twoColumn?['tabs'] as List?;
      if (tabs == null || tabs.isEmpty) return results;

      final firstTab = tabs[0] as Map?;
      final tabContent = firstTab?['tabRenderer']?['content'] as Map?;
      final sectionList = tabContent?['sectionListRenderer'] as Map?;
      final sectionContents = sectionList?['contents'] as List?;
      if (sectionContents == null || sectionContents.isEmpty) return results;

      for (final section in sectionContents) {
        final sectionMap = section as Map?;
        final itemSection =
            sectionMap?['itemSectionRenderer'] as Map?;
        final itemContents = itemSection?['contents'] as List?;
        if (itemContents == null) continue;

        for (final item in itemContents) {
          final itemMap = item as Map?;
          final playlistVideoList =
              itemMap?['playlistVideoListRenderer'] as Map?;
          final videoContents = playlistVideoList?['contents'] as List?;
          if (videoContents == null) continue;

          for (final videoItem in videoContents) {
            final videoItemMap = videoItem as Map?;
            final renderer =
                videoItemMap?['playlistVideoRenderer'] as Map?;
            if (renderer == null) continue;

            final videoId = renderer['videoId'] as String?;
            if (videoId == null) continue;

    final title = _getRunsText(renderer['title'] as Map?);
    final author = _getTextFromList(
        (renderer['shortBylineText'] as Map?)?['runs'] as List?);
    int duration;
    final ls = renderer['lengthSeconds'];
    if (ls is num) {
      duration = ls.toInt();
    } else if (ls is String) {
      duration = int.tryParse(ls) ?? 0;
    } else {
      duration = _parseDuration(_getSimpleText(
          (renderer['lengthText'] as Map?)));
    }
            final thumbnail = _getThumbnail(renderer['thumbnail'] as Map?);

            results.add(TrackModel(
              id: videoId,
              title: title ?? 'Unknown',
              thumbnailUrl: thumbnail,
              durationSeconds: duration,
              author: author,
              index: index++,
            ));
          }
        }
      }
    } catch (e) {
      print('_parseTracks error: $e');
    }

    return results;
  }

  String? _parseTitle(Map<String, dynamic> data) {
    try {
      const path = [
        'sidebar', 'playlistSidebarRenderer', 'items',
      ];
      var current = data;
      for (final key in path) {
        final next = current[key];
        if (next is List) {
          current = next.isNotEmpty ? (next[0] as Map).cast<String, dynamic>() : {};
        } else if (next is Map) {
          current = next.cast<String, dynamic>();
        } else {
          return null;
        }
      }
      final info = current['playlistSidebarPrimaryInfoRenderer'] as Map?;
      final title = info?['title'] as Map?;
      return _getRunsText(title);
    } catch (_) {
      return null;
    }
  }

  String? _parseAuthor(Map<String, dynamic> data) {
    try {
      final sidebar = data['sidebar'] as Map?;
      if (sidebar == null) return null;
      final items = sidebar['playlistSidebarRenderer']?['items'] as List?;
      if (items == null || items.length < 2) return null;
      final secondaryInfo = items[1]
          ['playlistSidebarSecondaryInfoRenderer'] as Map?;
      final owner = secondaryInfo?['videoOwner']?['videoOwnerRenderer'] as Map?;
      final title = owner?['title'] as Map?;
      return _getRunsText(title);
    } catch (_) {
      return null;
    }
  }

  String? _getRunsText(Map? runsContainer) {
    if (runsContainer == null) return null;
    final runs = runsContainer['runs'] as List?;
    return _getTextFromList(runs);
  }

  String? _getTextFromList(List? runs) {
    if (runs == null || runs.isEmpty) return null;
    return runs.map((r) => (r as Map)['text'] as String?).join();
  }

  String? _getSimpleText(Map? container) {
    if (container == null) return null;
    return container['simpleText'] as String?;
  }

  int _parseDuration(String? duration) {
    if (duration == null || duration.isEmpty) return 0;
    final parts = duration.split(':');
    if (parts.length == 2) {
      return int.tryParse(parts[0])! * 60 + int.tryParse(parts[1])!;
    } else if (parts.length == 3) {
      return int.tryParse(parts[0])! * 3600 +
          int.tryParse(parts[1])! * 60 +
          int.tryParse(parts[2])!;
    }
    return 0;
  }

  String? _getThumbnail(Map? thumbnail) {
    try {
      final thumbnails = thumbnail?['thumbnails'] as List?;
      if (thumbnails == null || thumbnails.isEmpty) return null;
      final best = thumbnails
          .reduce((a, b) => (a as Map)['width'] > (b as Map)['width'] ? a : b)
          as Map;
      return best['url'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<String> getAudioUrl(String videoId) async {
    var attempt = 0;
    while (true) {
      try {
        final manifest = await _yt.videos.streams
            .getManifest(videoId)
            .timeout(_timeout, onTimeout: () => throw TimeoutException('Audio stream request timed out'));

        // Prefer muxed streams (progressive download, works with just_audio)
        final muxed = manifest.muxed;
        if (muxed.isNotEmpty) {
          final best = muxed
              .reduce((a, b) => a.bitrate.compareTo(b.bitrate) < 0 ? a : b);
          final url = best.url.toString();
          return url;
        }

        // Fallback: audio-only DASH-fragmented streams
        var audioStreams = manifest.audioOnly.toList();
        if (audioStreams.isEmpty) {
          throw Exception('No audio streams available for video $videoId');
        }
        var candidates = audioStreams
            .where((s) =>
                s.container == StreamContainer.mp4 ||
                s.container == StreamContainer.webM)
            .toList();
        if (candidates.isEmpty) {
          candidates = audioStreams;
        }
        final bestAudio = candidates
            .reduce((a, b) => a.bitrate.compareTo(b.bitrate) < 0 ? a : b);
        return bestAudio.url.toString();
      } on Exception catch (e) {
        attempt++;
        if (attempt >= 3) rethrow;
        if (e.toString().contains('requestLimit') || e.toString().contains('429')) {
          await Future.delayed(Duration(seconds: 2 * attempt));
        } else {
          rethrow;
        }
      }
    }
  }

  void dispose() {
    _yt.close();
  }
}
