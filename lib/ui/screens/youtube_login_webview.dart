import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../service/auth_service.dart';

class YoutubeLoginWebview extends StatefulWidget {
  const YoutubeLoginWebview({super.key});

  @override
  State<YoutubeLoginWebview> createState() => _YoutubeLoginWebviewState();
}

class _YoutubeLoginWebviewState extends State<YoutubeLoginWebview> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) async {
            setState(() {
              _isLoading = false;
            });
            await _checkCookies();
          },
          onUrlChange: (UrlChange change) async {
            await _checkCookies();
          },
        ),
      )
      ..loadRequest(Uri.parse('https://accounts.google.com/ServiceLogin?service=youtube&continue=https://www.youtube.com'));
  }

  Future<void> _checkCookies() async {
    try {
      final String cookies = await _controller.runJavaScriptReturningResult('document.cookie') as String;
      // The result from runJavaScriptReturningResult is typically a JSON string, so remove quotes
      final cleanedCookies = cookies.replaceAll('"', '');

      // Check if we have standard YouTube auth cookies
      if (cleanedCookies.contains('SAPISID') || cleanedCookies.contains('LOGIN_INFO')) {
        await AuthService().setCookies(cleanedCookies);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Successfully logged into YouTube!')),
          );
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      // Ignored
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log into Youtube'),
        backgroundColor: const Color(0xFF141414),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFFEAB308)),
            ),
        ],
      ),
    );
  }
}
