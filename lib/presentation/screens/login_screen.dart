import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../service/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final WebViewController _controller;
  final _authService = AuthService();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() => _loading = true);
          },
          onPageFinished: (url) async {
            if (!mounted) return;
            setState(() => _loading = false);
            if ((url.startsWith('https://www.youtube.com') ||
                    url.startsWith('https://m.youtube.com')) &&
                !url.contains('ServiceLogin')) {
              await _extractCookies();
            }
          },
        ),
      )
      ..loadRequest(
        Uri.parse(
          'https://accounts.google.com/ServiceLogin?'
          'service=youtube&continue=https://www.youtube.com&hl=en',
        ),
      );
  }

  Future<void> _extractCookies() async {
    try {
      final mgr = WebViewCookieManager();
      final platform = mgr.platform;
      if (platform is AndroidWebViewCookieManager) {
        final cookies = await platform.getCookies(
          Uri.parse('https://www.youtube.com'),
        );
        if (cookies.isNotEmpty) {
          final cookieStr = cookies
              .map((c) => '${c.name}=${c.value}')
              .join('; ');
          await _authService.setCookies(cookieStr);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Login successful! Cookies saved.'),
                backgroundColor: Color(0xFF1DB954),
              ),
            );
            Navigator.pop(context, true);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xDD191919),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xDD191919),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'Login with Google',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF1DB954)),
            ),
        ],
      ),
    );
  }
}
