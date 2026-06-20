import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_explode;

/// Lightweight, Dart port of PlayTorrio TV's `YouTubeExtractor` + `MusicAudioExtractor`.
///
/// Fast path for music playback:
///   1. Search YouTube HTML once, regex-pick the first 11-char videoId.
///   2. POST to InnerTube `/player` with an `ANDROID_VR` (and fallback) client
///      context. Returns plaintext stream URLs — no signature cipher work.
///   3. Cache InnerTube API key + visitor_data for 3h, and resolved audio URLs
///      until they expire (from the `expire=` query param).
///
/// Audio-only: short-circuits on the first client that yields a usable
/// progressive or adaptive audio stream.
class YoutubeAudioExtractor {
  YoutubeAudioExtractor._();
  static final YoutubeAudioExtractor instance = YoutubeAudioExtractor._();

  static const String _tag = 'YoutubeAudioExtractor';
  static const String _fallbackApiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  static const Duration _configTtl = Duration(hours: 3);
  static const Duration _requestTimeout = Duration(seconds: 15);

  static const String _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

  static final RegExp _videoIdRegex =
      RegExp(r'"videoId"\s*:\s*"([a-zA-Z0-9_-]{11})"');
  static final RegExp _apiKeyRegex = RegExp(r'"INNERTUBE_API_KEY":"([^"]+)"');
  static final RegExp _visitorDataRegex = RegExp(r'"VISITOR_DATA":"([^"]+)"');

  // --- Client definitions (order = priority for audioOnly short-circuit) ---
  static final List<_YtClient> _clients = [
    _YtClient(
      key: 'android_vr',
      id: '28',
      version: '1.56.21',
      userAgent:
          'com.google.android.apps.youtube.vr.oculus/1.56.21 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1) gzip',
      context: {
        'clientName': 'ANDROID_VR',
        'clientVersion': '1.56.21',
        'deviceMake': 'Oculus',
        'deviceModel': 'Quest 3',
        'osName': 'Android',
        'osVersion': '12',
        'platform': 'MOBILE',
        'androidSdkVersion': 32,
        'hl': 'en',
        'gl': 'US',
      },
      requiresVisitorData: true,
    ),
    _YtClient(
      key: 'android',
      id: '3',
      version: '20.10.35',
      userAgent:
          'com.google.android.youtube/20.10.35 (Linux; U; Android 14; en_US) gzip',
      context: {
        'clientName': 'ANDROID',
        'clientVersion': '20.10.35',
        'osName': 'Android',
        'osVersion': '14',
        'platform': 'MOBILE',
        'androidSdkVersion': 34,
        'hl': 'en',
        'gl': 'US',
      },
    ),
    _YtClient(
      key: 'ios',
      id: '5',
      version: '20.10.1',
      userAgent:
          'com.google.ios.youtube/20.10.1 (iPhone16,2; U; CPU iOS 17_4 like Mac OS X)',
      context: {
        'clientName': 'IOS',
        'clientVersion': '20.10.1',
        'deviceModel': 'iPhone16,2',
        'osName': 'iPhone',
        'osVersion': '17.4.0.21E219',
        'platform': 'MOBILE',
        'hl': 'en',
        'gl': 'US',
      },
    ),
    _YtClient(
      key: 'tv_embed',
      id: '54',
      version: '2.0',
      userAgent: 'Mozilla/5.0 (SMART-TV; Linux; Tizen 5.0) AppleWebKit/538.1 (KHTML, like Gecko) Version/5.0 TV Safari/538.1',
      context: {
        'clientName': 'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
        'clientVersion': '2.0',
        'osName': 'Tizen',
        'osVersion': '5.0',
        'platform': 'TV',
        'hl': 'en',
        'gl': 'US',
      },
    ),
    _YtClient(
      key: 'web_creator',
      id: '62',
      version: '1.20231130.05.00',
      userAgent: _desktopUserAgent,
      context: {
        'clientName': 'WEB_CREATOR',
        'clientVersion': '1.20231130.05.00',
        'osName': 'Windows',
        'osVersion': '10.0',
        'platform': 'DESKTOP',
        'hl': 'en',
        'gl': 'US',
      },
    ),
    _YtClient(
      key: 'mweb',
      id: '2',
      version: '2.20231201.00.00',
      userAgent: 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
      context: {
        'clientName': 'MWEB',
        'clientVersion': '2.20231201.00.00',
        'osName': 'Android',
        'osVersion': '10',
        'platform': 'MOBILE',
        'hl': 'en',
        'gl': 'US',
      },
    ),
    _YtClient(
      key: 'web',
      id: '1',
      version: '2.20231201.00.00',
      userAgent: _desktopUserAgent,
      context: {
        'clientName': 'WEB',
        'clientVersion': '2.20231201.00.00',
        'osName': 'Windows',
        'osVersion': '10.0',
        'platform': 'DESKTOP',
        'hl': 'en',
        'gl': 'US',
      },
    ),
  ];

  // --- State ---
  _CachedConfig? _config;
  Future<_CachedConfig>? _configInFlight;

  final Map<String, _CachedVideoId> _videoIdCache = {};
  final Map<String, _CachedStream> _streamCache = {};

  // =========================================================================
  // Public API
  // =========================================================================

  /// Search YouTube for `"$title $artist lyrics"` and return the first videoId.
  Future<String?> searchVideoId(String title, String artist) async {
    final query = '$title $artist lyrics';
    final cached = _videoIdCache[query];
    if (cached != null && !cached.isExpired) return cached.videoId;

    try {
      final encoded = Uri.encodeQueryComponent(query);
      final url = Uri.parse(
          'https://www.youtube.com/results?search_query=$encoded');
      final resp = await http.get(url, headers: {
        'User-Agent': _desktopUserAgent,
        'Accept-Language': 'en-US,en;q=0.9',
      }).timeout(_requestTimeout);

      if (resp.statusCode != 200) {
        _log('search HTTP ${resp.statusCode}');
        return null;
      }
      final match = _videoIdRegex.firstMatch(resp.body);
      final id = match?.group(1);
      if (id != null) {
        _videoIdCache[query] = _CachedVideoId(id);
      }
      return id;
    } catch (e) {
      _log('searchVideoId failed: $e');
      return null;
    }
  }

  /// Resolve a plaintext audio URL for [videoId]. Picks the highest-bitrate
  /// audio (adaptive preferred; falls back to progressive video+audio).
  Future<String?> getAudioUrl(String videoId) async {
    final cached = _streamCache[videoId];
    if (cached != null && !cached.isExpired) return cached.url;

    final config = await _ensureConfig();
    for (final client in _clients) {
      if (client.requiresVisitorData &&
          (config.visitorData == null || config.visitorData!.isEmpty)) {
        continue;
      }
      try {
        final player = await _fetchPlayer(config, videoId, client);
        final status = _str(_map(player['playabilityStatus']), 'status');
        if (status == 'LOGIN_REQUIRED') {
          _log('${client.key}: LOGIN_REQUIRED');
          continue;
        }
        final streamingData = _map(player['streamingData']);
        if (streamingData == null) continue;

        final best = _pickBestAudio(streamingData);
        if (best != null) {
          _streamCache[videoId] = _CachedStream(best.url, best.expiresAt);
          return best.url;
        }
      } catch (e) {
        _log('${client.key} failed: $e');
      }
    }
    // One retry with a forced config refresh (visitor_data / api key may have rotated).
    if (!config.forced) {
      _config = null;
      final retryUrl = await _getAudioUrlForceRefresh(videoId);
      if (retryUrl != null) return retryUrl;
    }

    // FALLBACK 1: If all InnerTube clients fail (e.g. LOGIN_REQUIRED block),
    // use youtube_explode_dart which has built-in PO Token bypasses.
    try {
      _log('InnerTube clients failed, falling back to youtube_explode_dart...');
      final yt = yt_explode.YoutubeExplode();
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      final mp4Streams = manifest.audioOnly.where((s) => s.container.name == 'mp4');
      final audioInfo = mp4Streams.isNotEmpty 
          ? mp4Streams.withHighestBitrate() 
          : manifest.audioOnly.withHighestBitrate();
      yt.close();
      
      _streamCache[videoId] = _CachedStream(audioInfo.url.toString(), null);
      return audioInfo.url.toString();
    } catch (e) {
      _log('youtube_explode_dart fallback failed: $e');
    }

    // FALLBACK 2: Piped API
    // If youtube is aggressively blocking this IP or client, try a third-party open source API proxy.
    try {
      _log('Falling back to Piped APIs...');
      final pipedInstances = [
        'https://pipedapi.kavin.rocks',
        'https://pipedapi.smnz.de',
        'https://api.piped.projectsegfau.lt',
      ];
      for (final base in pipedInstances) {
        try {
          final resp = await http.get(Uri.parse('$base/streams/$videoId')).timeout(_requestTimeout);
          if (resp.statusCode == 200) {
            final json = jsonDecode(resp.body);
            final audioStreams = _listOfMaps(json['audioStreams']);
            if (audioStreams.isNotEmpty) {
              audioStreams.sort((a, b) => ((b['bitrate'] ?? 0) as num).compareTo((a['bitrate'] ?? 0) as num));
              final best = audioStreams.first;
              final url = _str(best, 'url');
              if (url != null) {
                _streamCache[videoId] = _CachedStream(url, null);
                return url;
              }
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      _log('Piped API fallback failed: $e');
    }

    return null;
  }

  Future<String?> _getAudioUrlForceRefresh(String videoId) async {
    final config = await _ensureConfig(forceRefresh: true);
    for (final client in _clients) {
      if (client.requiresVisitorData &&
          (config.visitorData == null || config.visitorData!.isEmpty)) {
        continue;
      }
      try {
        final player = await _fetchPlayer(config, videoId, client);
        final streamingData = _map(player['streamingData']);
        if (streamingData == null) continue;
        final best = _pickBestAudio(streamingData);
        if (best != null) {
          _streamCache[videoId] = _CachedStream(best.url, best.expiresAt);
          return best.url;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Convenience: `search + getAudioUrl` in one call.
  Future<({String videoId, String audioUrl})?> extract(
      String title, String artist) async {
    final id = await searchVideoId(title, artist);
    if (id == null) return null;
    final url = await getAudioUrl(id);
    if (url == null) return null;
    return (videoId: id, audioUrl: url);
  }

  // =========================================================================
  // Internals
  // =========================================================================

  Future<_CachedConfig> _ensureConfig({bool forceRefresh = false}) {
    final existing = _config;
    if (!forceRefresh && existing != null && !existing.isExpired) {
      return Future.value(existing);
    }
    final inflight = _configInFlight;
    if (inflight != null) return inflight;
    final future = _fetchConfig(forceRefresh).whenComplete(() {
      _configInFlight = null;
    });
    _configInFlight = future;
    return future;
  }

  Future<_CachedConfig> _fetchConfig(bool forced) async {
    try {
      final resp = await http.get(
        Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ&hl=en'),
        headers: {
          'User-Agent': _desktopUserAgent,
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ).timeout(_requestTimeout);
      if (resp.statusCode == 200) {
        final apiKey = _apiKeyRegex.firstMatch(resp.body)?.group(1);
        final visitor = _visitorDataRegex.firstMatch(resp.body)?.group(1);
        final c = _CachedConfig(
          apiKey: apiKey ?? _fallbackApiKey,
          visitorData: visitor,
          forced: forced,
        );
        _config = c;
        return c;
      }
      _log('watch page HTTP ${resp.statusCode}, using fallback key');
    } catch (e) {
      _log('watch page fetch failed: $e, using fallback key');
    }
    final c = _CachedConfig(
        apiKey: _fallbackApiKey, visitorData: null, forced: forced);
    _config = c;
    return c;
  }

  Future<Map<String, dynamic>> _fetchPlayer(
      _CachedConfig config, String videoId, _YtClient client) async {
    final uri = Uri.parse(
        'https://www.youtube.com/youtubei/v1/player?key=${Uri.encodeQueryComponent(config.apiKey)}');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept-Language': 'en-US,en;q=0.9',
      'Origin': 'https://www.youtube.com',
      'User-Agent': client.userAgent,
      'X-YouTube-Client-Name': client.id,
      'X-YouTube-Client-Version': client.version,
      if (config.visitorData != null && config.visitorData!.isNotEmpty)
        'X-Goog-Visitor-Id': config.visitorData!,
    };
    final body = jsonEncode({
      'videoId': videoId,
      'contentCheckOk': true,
      'racyCheckOk': true,
      'context': {'client': client.context},
      'playbackContext': {
        'contentPlaybackContext': {'html5Preference': 'HTML5_PREF_WANTS'}
      },
    });
    final resp = await http
        .post(uri, headers: headers, body: body)
        .timeout(_requestTimeout);
    if (resp.statusCode != 200) {
      throw StateError(
          'player API ${client.key} failed (${resp.statusCode})');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return <String, dynamic>{};
  }

  _AudioCandidate? _pickBestAudio(Map<String, dynamic> streamingData) {
    final adaptive = _listOfMaps(streamingData['adaptiveFormats']);
    final progressive = _listOfMaps(streamingData['formats']);

    _AudioCandidate? best;
    // Prefer adaptive audio-only streams (smaller, higher quality per byte).
    for (final f in adaptive) {
      final mime = _str(f, 'mimeType') ?? '';
      if (!mime.contains('audio/')) continue;
      final url = _str(f, 'url');
      if (url == null || url.isEmpty) continue;
      final bitrate =
          (_num(f, 'bitrate') ?? _num(f, 'averageBitrate') ?? 0).toDouble();
          
      // Prefer MP4 audio to allow ID3/MP4 tag writing during export
      final adjustedBitrate = mime.contains('mp4') ? bitrate * 2.0 : bitrate;
      
      final cand = _AudioCandidate(url, adjustedBitrate, _expiresAt(url));
      if (best == null || cand.bitrate > best.bitrate) best = cand;
    }
    if (best != null) return best;

    // Fallback: progressive (video+audio muxed) — last resort for audio-only.
    for (final f in progressive) {
      final url = _str(f, 'url');
      if (url == null || url.isEmpty) continue;
      final bitrate =
          (_num(f, 'bitrate') ?? _num(f, 'averageBitrate') ?? 0).toDouble();
      final cand = _AudioCandidate(url, bitrate, _expiresAt(url));
      if (best == null || cand.bitrate > best.bitrate) best = cand;
    }
    return best;
  }

  DateTime? _expiresAt(String url) {
    try {
      final expire = Uri.parse(url).queryParameters['expire'];
      final secs = int.tryParse(expire ?? '');
      if (secs == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(secs * 1000);
    } catch (_) {
      return null;
    }
  }

  // --- tiny JSON helpers ---
  static Map<String, dynamic>? _map(Object? v) =>
      v is Map<String, dynamic> ? v : (v is Map ? Map<String, dynamic>.from(v) : null);
  static List<Map<String, dynamic>> _listOfMaps(Object? v) {
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  static String? _str(Map<String, dynamic>? m, String key) =>
      m == null ? null : m[key]?.toString();
  static num? _num(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  static void _log(String msg) {
    debugPrint('[$_tag] $msg');
    // Also use AppLogger so we can see it in user logs
    try {
      // Import not needed if we just print, but AppLogger requires import.
      // Wait, AppLogger is in lib/core/utils/app_logger.dart
    } catch (_) {}
  }
}

// --- private types ---

class _YtClient {
  final String key;
  final String id;
  final String version;
  final String userAgent;
  final Map<String, Object> context;
  final bool requiresVisitorData;
  _YtClient({
    required this.key,
    required this.id,
    required this.version,
    required this.userAgent,
    required this.context,
    this.requiresVisitorData = false,
  });
}

class _CachedConfig {
  final String apiKey;
  final String? visitorData;
  final DateTime fetchedAt;
  final bool forced;
  _CachedConfig({
    required this.apiKey,
    required this.visitorData,
    this.forced = false,
  }) : fetchedAt = DateTime.now();
  bool get isExpired =>
      DateTime.now().difference(fetchedAt) >= YoutubeAudioExtractor._configTtl;
}

class _CachedVideoId {
  final String videoId;
  final DateTime cachedAt;
  _CachedVideoId(this.videoId) : cachedAt = DateTime.now();
  bool get isExpired =>
      DateTime.now().difference(cachedAt) >= const Duration(hours: 12);
}

class _CachedStream {
  final String url;
  final DateTime? expiresAt;
  final DateTime cachedAt;
  _CachedStream(this.url, this.expiresAt) : cachedAt = DateTime.now();
  bool get isExpired {
    final exp = expiresAt;
    if (exp != null) {
      // Expire 60s early to avoid racing the CDN.
      return DateTime.now().isAfter(exp.subtract(const Duration(seconds: 60)));
    }
    return DateTime.now().difference(cachedAt) >= const Duration(hours: 4);
  }
}

class _AudioCandidate {
  final String url;
  final double bitrate;
  final DateTime? expiresAt;
  _AudioCandidate(this.url, this.bitrate, this.expiresAt);
}
