import 'package:url_launcher/url_launcher.dart';

class OAuthService {
  // Replace these with actual credentials later
  static const String _youtubeClientId = 'YOUR_YOUTUBE_CLIENT_ID.apps.googleusercontent.com';
  static const String _lastfmApiKey = 'YOUR_LASTFM_API_KEY';
  static const String _librefmApiKey = 'YOUR_LIBREFM_API_KEY';
  static const String _listenbrainzClientId = 'YOUR_LISTENBRAINZ_CLIENT_ID';

  static const String _redirectUri = 'app://monochrome.callback';

  Future<void> connectYouTube() async {
    final uri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': _youtubeClientId,
      'redirect_uri': _redirectUri,
      'response_type': 'code',
      'scope': 'https://www.googleapis.com/auth/youtube.readonly',
    });
    await _launchUrl(uri);
  }

  Future<void> connectLastFm() async {
    final uri = Uri.https('www.last.fm', '/api/auth/', {
      'api_key': _lastfmApiKey,
      'cb': _redirectUri,
    });
    await _launchUrl(uri);
  }

  Future<void> connectLibreFm() async {
    final uri = Uri.https('libre.fm', '/api/auth/', {
      'api_key': _librefmApiKey,
      'cb': _redirectUri,
    });
    await _launchUrl(uri);
  }

  Future<void> connectListenBrainz() async {
    // ListenBrainz OAuth flow might differ, standardizing for placeholder
    final uri = Uri.https('listenbrainz.org', '/login/oauth/authorize', {
      'client_id': _listenbrainzClientId,
      'redirect_uri': _redirectUri,
      'response_type': 'code',
    });
    await _launchUrl(uri);
  }

  Future<void> _launchUrl(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $uri');
    }
  }
}
