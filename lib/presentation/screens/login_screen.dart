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
        '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36')
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          if (!mounted) return;
          setState(() => _loading = true);
        },
        onPageFinished: (url) async {
          if (!mounted) return;
          setState(() => _loading = false);
          if ((url.startsWith('https://www.youtube.com') || url.startsWith('https://m.youtube.com')) && !url.contains('ServiceLogin')) {
            await _extractCookies();
          }
        },
      ))
      ..loadRequest(
        Uri.parse('https://accounts.google.com/ServiceLogin?'
            'service=youtube&continue=https://www.youtube.com&hl=en'),
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
          final cookieStr =
              cookies.map((c) => '${c.name}=${c.value}').join('; ');
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login with Google'),
        backgroundColor: const Color(0xFF121212),
      ),
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(
                child: CircularProgressIndicator(color: Color(0xFF1DB954))),
        ],
      ),
    );
  }
}
