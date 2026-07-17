import 'package:url_launcher/url_launcher.dart';

class OAuthService {
  // Replace with actual credentials later
  static const String _youtubeClientId =
      'YOUR_YOUTUBE_CLIENT_ID.apps.googleusercontent.com';

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

  Future<void> _launchUrl(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $uri');
    }
  }
}
