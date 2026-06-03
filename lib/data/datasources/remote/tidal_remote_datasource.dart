import 'dart:convert';
import 'package:zyp_music/core/utils/app_logger.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../domain/entities/video.dart';

/// Tidal data source that uses the same community HiFi API proxy as the
/// Monochrome web app (tidal-api.geeked.wtf). This proxy holds Tidal
/// credentials server-side, so no user login is required.
///
/// Architecture mirrors functions/track/[id].js in the Monochrome repo:
/// - Client credentials token obtained from Tidal auth
/// - All api.tidal.com calls are routed through tidal-api.geeked.wtf/api
/// - Stream URLs for audio content come through the proxy
class TidalRemoteDataSource {
  // Public client credentials (same as Monochrome uses — these are for metadata access)
  static const String _clientId = 'txNoH4kkV41MfH25';
  static const String _clientSecret = 'dQjy0MinCEvxi1O4UmxvxWnDjt4cgHBPw8ll6nYBk98=';
  static const String _authUrl = 'https://auth.tidal.com/v1/oauth2/token';
  static const String _countryCode = 'US';

  String? _accessToken;
  DateTime? _tokenExpiry;

  final http.Client _client;

  TidalRemoteDataSource({http.Client? client}) : _client = client ?? http.Client();

  Future<List<String>> _getApiInstances() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getStringList('tidalApiInstances');
    if (custom != null && custom.isNotEmpty) return custom;
    return [
      'https://eu-central.monochrome.tf',
      'https://us-west.monochrome.tf',
      'https://api.monochrome.tf',
      'https://tidal.kinoplus.online'
    ];
  }

  Future<List<String>> _getStreamingInstances() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getStringList('tidalStreamingInstances');
    if (custom != null && custom.isNotEmpty) return custom;
    return [
      'https://arran.monochrome.tf',
      'https://triton.squid.wtf',
      'https://wolf.qqdl.site',
      'https://hund.qqdl.site'
    ];
  }

  Future<String> _getToken() async {
    if (_accessToken != null && _tokenExpiry != null && DateTime.now().isBefore(_tokenExpiry!)) {
      return _accessToken!;
    }

    final String basicAuth = 'Basic ${base64Encode(utf8.encode('$_clientId:$_clientSecret'))}';

    final response = await _client.post(
      Uri.parse(_authUrl),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Authorization': basicAuth,
      },
      body: {
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'grant_type': 'client_credentials',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Tidal auth failed: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _accessToken = data['access_token'] as String;
    final expiresIn = (data['expires_in'] as int?) ?? 3600;
    _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));

    return _accessToken!;
  }

  Map<String, String> _getHeaders(String token) {
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    };
  }

  /// Routes a Tidal API path through the community proxy, exactly as Monochrome does.
  Uri _proxyUri(String path, Map<String, String> queryParams, String proxyBase) {
    // Ensure proxyBase does not end with /api if it already includes it, or add it if necessary?
    // Actually, the instances in instances.json just look like https://api.monochrome.tf
    // The path starts with /, so we just append it. Wait, the original _proxyBase was https://tidal-api.geeked.wtf/api
    // Some instances might require /api, but looking at monochrome.tf's instances, they are standard.
    // We will assume proxyBase doesn't have /api at the end, but we append it because the community backend expects it.
    // Wait, the instances in JSON are root URLs. The paths passed in are like `/search` or `/tracks/...`.
    // The Tidal API paths should be prefixed with `/api` for these proxies.
    final base = proxyBase.endsWith('/') ? proxyBase.substring(0, proxyBase.length - 1) : proxyBase;
    final fullUrl = base.endsWith('/api') ? '$base$path' : '$base/api$path';
    return Uri.parse(fullUrl).replace(queryParameters: queryParams);
  }

  Future<dynamic> _fetchJson(String path, Map<String, String> params, {String? proxyBase}) async {
    final token = await _getToken();
    
    final List<String> instancesToTry = proxyBase != null ? [proxyBase] : await _getApiInstances();
    
    Exception? lastException;

    for (final instance in instancesToTry) {
      try {
        final uri = _proxyUri(path, params, instance);
        AppLogger.log('Tidal proxy request: $uri', name: 'TidalDataSource');

        final response = await _client.get(uri, headers: _getHeaders(token)).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          return jsonDecode(response.body);
        } else {
          AppLogger.log('Tidal proxy error ${response.statusCode}: ${response.body} at $instance', name: 'TidalDataSource');
          lastException = Exception('Tidal API error ${response.statusCode}: ${response.body}');
        }
      } catch (e) {
        AppLogger.log('Tidal proxy $instance failed: $e', name: 'TidalDataSource');
        lastException = Exception('Tidal API error: $e');
      }
    }

    throw lastException ?? Exception('All Tidal API proxies failed');
  }

  /// Gets the stream URL for a Tidal track using the HiFi proxy.
  /// This mirrors TidalAPI.getStreamUrl() in functions/track/[id].js.
  Future<String?> getTrackStreamUrl(String trackId, {String quality = 'LOW'}) async {
    // Map our quality strings to Tidal API quality tokens
    String apiQuality = _mapQuality(quality);

    final streamingInstances = await _getStreamingInstances();

    for (final proxyBase in streamingInstances) {
      try {
        final data = await _fetchJson(
          '/tracks/$trackId/playbackinfo',
          {
            'audioquality': apiQuality,
            'playbackmode': 'STREAM',
            'assetpresentation': 'FULL',
            'countryCode': _countryCode,
          },
          proxyBase: proxyBase,
        );

        // Extract stream URL from response (same as getStreamUrl in functions/track/[id].js)
        final url = _extractStreamUrl(data);
        if (url != null) {
          AppLogger.log('Got Tidal stream URL from $proxyBase: $url', name: 'TidalDataSource');
          return url;
        }
      } catch (e) {
        AppLogger.log('Tidal streaming proxy $proxyBase failed: $e — trying next', name: 'TidalDataSource');
        continue;
      }
    }

    AppLogger.log('All Tidal streaming proxies failed for track $trackId', name: 'TidalDataSource');
    return null;
  }

  String? _extractStreamUrl(dynamic data) {
    if (data == null) return null;

    // Direct URL field (returned by some proxy endpoints)
    if (data['url'] is String && (data['url'] as String).startsWith('http')) {
      return data['url'] as String;
    }
    if (data['streamUrl'] is String && (data['streamUrl'] as String).startsWith('http')) {
      return data['streamUrl'] as String;
    }

    // Manifest-based URL (standard Tidal playbackinfo response)
    final manifest = data['manifest'] as String?;
    if (manifest != null) {
      return _parseManifest(manifest, data['manifestMimeType'] as String?);
    }

    return null;
  }

  String? _parseManifest(String manifest, String? mimeType) {
    try {
      // BTS manifest (base64-encoded JSON with URLs array)
      if (mimeType == 'application/vnd.tidal.bts' || _isBase64(manifest)) {
        final decoded = utf8.decode(base64Decode(manifest));
        final json = jsonDecode(decoded) as Map<String, dynamic>;
        final urls = json['urls'] as List<dynamic>?;
        if (urls != null && urls.isNotEmpty) {
          return urls.first.toString();
        }
      }
    } catch (e) {
      AppLogger.log('Manifest parse error: $e', name: 'TidalDataSource');
    }
    return null;
  }

  bool _isBase64(String s) {
    try {
      base64Decode(s);
      return true;
    } catch (_) {
      return false;
    }
  }

  String _mapQuality(String quality) {
    switch (quality.toLowerCase()) {
      case 'tidalhi_res':
      case 'tidalhi res':
      case 'hires':
      case 'hi_res_lossless':
        return 'HI_RES_LOSSLESS';
      case 'tidallossless':
      case 'lossless':
        return 'LOSSLESS';
      case 'tidalhigh':
      case 'high':
        return 'HIGH';
      case 'tidaladaptive':
      case 'adaptive':
      case 'low':
      default:
        return 'LOW'; // Start with LOW for best proxy compatibility
    }
  }

  Future<List<Track>> search(String query) async {
    try {
      final data = await _fetchJson(
        '/search',
        {
          'query': query,
          'limit': '25',
          'types': 'TRACKS',
          'countryCode': _countryCode,
        },
      );

      final tracksData = data['tracks']?['items'] as List<dynamic>? ?? [];
      return tracksData.map((item) => _parseTrackItem(item as Map<String, dynamic>)).toList();
    } catch (e) {
      AppLogger.log('Tidal search error: $e', name: 'TidalDataSource');
      return [];
    }
  }

  Future<List<Track>> getEditorsPicks() async {
    // Tidal's hot tracks via search — mirrors the approach in monochrome
    return search('top hits 2025');
  }

  Track _parseTrackItem(Map<String, dynamic> item) {
    final title = item['title'] as String? ?? 'Unknown Title';
    final version = item['version'] as String?;
    final displayTitle = version != null ? '$title ($version)' : title;

    // Artist — prioritise artists array (same as getTrackArtists in functions/track/[id].js)
    String artist = 'Unknown Artist';
    final artistsList = item['artists'] as List<dynamic>?;
    if (artistsList != null && artistsList.isNotEmpty) {
      artist = artistsList.map((a) => a['name'] as String? ?? '').where((n) => n.isNotEmpty).join(', ');
    } else {
      artist = item['artist']?['name'] as String? ?? 'Unknown Artist';
    }

    final albumData = item['album'] as Map<String, dynamic>?;
    final albumName = albumData?['title'] as String?;
    final albumCoverId = albumData?['cover'] as String?;
    final releaseDate = albumData?['releaseDate'] as String?;
    final year = releaseDate != null ? int.tryParse(releaseDate.split('-').first) : null;
    final duration = item['duration'] as int? ?? 0;
    final id = item['id'].toString();

    String? thumbnailUrl;
    if (albumCoverId != null && albumCoverId.isNotEmpty) {
      final parsedCoverId = albumCoverId.replaceAll('-', '/');
      thumbnailUrl = 'https://resources.tidal.com/images/$parsedCoverId/640x640.jpg';
    }

    return Track(
      id: id,
      title: displayTitle,
      author: artist,
      album: albumName,
      year: year,
      thumbnailUrl: thumbnailUrl,
      duration: Duration(seconds: duration),
      source: TrackSource.tidal,
    );
  }

  Future<String?> getLyrics(String trackId) async {
    try {
      final data = await _fetchJson(
        '/tracks/$trackId/lyrics',
        {'countryCode': _countryCode},
      );
      return data['lyrics'] as String?;
    } catch (e) {
      AppLogger.log('Tidal lyrics error: $e', name: 'TidalDataSource');
      return null;
    }
  }
}
