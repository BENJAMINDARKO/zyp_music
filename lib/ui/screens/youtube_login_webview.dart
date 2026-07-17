import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../service/auth_service.dart';

class YoutubeLoginWebview extends StatefulWidget {
  const YoutubeLoginWebview({super.key});

  @override
  State<YoutubeLoginWebview> createState() => _YoutubeLoginWebviewState();
}

class _YoutubeLoginWebviewState extends State<YoutubeLoginWebview> {
  InAppWebViewController? _controller;
  String? _statusText;
  bool _foundCookies = false;
  bool _showingFallback = false;
  bool _pageLoaded = false;
  Timer? _fallbackTimer;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _statusText = 'Opening Google sign-in...';
    _fallbackTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && !_pageLoaded) {
        setState(() {
          _showingFallback = true;
          _statusText = 'Google login may be blocked in embedded WebView.';
        });
      }
    });
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _saveCookies() async {
    final cookies = await _collectCookies();
    if (cookies.isEmpty) {
      setState(() => _statusText = 'No session cookies found yet.');
      return;
    }
    await AuthService().setCookiesFromWebView(cookies);
    _foundCookies = true;
    setState(() => _statusText = 'Validating session...');

    final valid = await AuthService().validateYoutubeCookies();
    if (!mounted) return;

    if (valid) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _statusText = 'Session saved but validation failed.');
    }
  }

  Future<List<Cookie>> _collectCookies() async {
    final cm = CookieManager.instance();
    final urls = [
      'https://www.youtube.com',
      'https://music.youtube.com',
      'https://accounts.google.com',
      'https://google.com',
    ];
    final all = <Cookie>[];
    for (final url in urls) {
      try {
        all.addAll(await cm.getCookies(url: WebUri(url)));
      } catch (_) {}
    }
    return all;
  }

  bool _hasRequiredCookies(List<Cookie> cookies) {
    final names = cookies.map((c) => c.name).toSet();
    return names.contains('SAPISID') ||
        names.contains('__Secure-3PAPISID') ||
        names.contains('LOGIN_INFO') ||
        names.contains('__Secure-1PSID') ||
        names.contains('__Secure-3PSID');
  }

  Future<void> _onPageLoad(String url) async {
    _pageLoaded = true;
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';

    if (!host.contains('youtube.com')) return;

    await Future.delayed(const Duration(seconds: 1));
    final cookies = await _collectCookies();

    if (!mounted) return;

    if (_hasRequiredCookies(cookies)) {
      setState(() => _statusText = 'YouTube session detected. Validating...');
      await _saveCookies();
    } else {
      setState(() {
        _showingFallback = true;
        _statusText = 'Signed in? Import session below.';
      });
    }
  }

  void _openCookieImportSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CookieImportSheet(
        onImported: (success) {
          if (success && mounted) Navigator.of(context).pop(true);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loginUrl =
        'https://accounts.google.com/ServiceLogin'
        '?service=youtube'
        '&continue=https://www.youtube.com/';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect YouTube'),
        actions: [
          TextButton(
            onPressed: () async {
              await _saveCookies();
              if (mounted) Navigator.of(context).pop(_foundCookies);
            },
            child: const Text('Use session',
                style: TextStyle(
                    color: Color(0xFF00E5FF), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Stack(
        children: [
          // WebView layer
          Positioned.fill(
            child: Opacity(
              opacity: _showingFallback ? 0.3 : 1.0,
              child: AbsorbPointer(
                absorbing: _showingFallback,
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(loginUrl)),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    domStorageEnabled: true,
                    thirdPartyCookiesEnabled: true,
                    sharedCookiesEnabled: true,
                    useShouldOverrideUrlLoading: true,
                    userAgent:
                        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                        '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
                  ),
                  onWebViewCreated: (c) => _controller = c,
                  onLoadStop: (c, url) async {
                    await _onPageLoad(url?.toString() ?? '');
                  },
                  onReceivedError: (c, req, err) {
                    _lastError = err.description;
                    if (mounted) setState(() {});
                  },
                  onLoadError: (c, url, code, msg) {
                    _lastError = 'HTTP $code: $msg';
                    if (mounted) setState(() {});
                  },
                  onConsoleMessage: (c, msg) {
                    // Log WebView console for debugging
                  },
                ),
              ),
            ),
          ),

          // Fallback overlay
          if (_showingFallback)
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.orangeAccent, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Login blocked',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Google may block sign-in inside embedded browsers.\n'
                      'Use "Import cookies" instead:',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildActionButton(
                    icon: PhosphorIconsRegular.fileText,
                    label: 'Import cookies',
                    onTap: _openCookieImportSheet,
                  ),
                  const SizedBox(height: 12),
                  _buildActionButton(
                    icon: PhosphorIconsRegular.arrowClockwise,
                    label: 'Retry WebView',
                    onTap: () {
                      setState(() {
                        _showingFallback = false;
                        _pageLoaded = false;
                        _statusText = 'Retrying...';
                      });
                      _controller?.reload();
                      _fallbackTimer?.cancel();
                      _fallbackTimer = Timer(const Duration(seconds: 10), () {
                        if (mounted && !_pageLoaded) {
                          setState(() {
                            _showingFallback = true;
                            _statusText = 'Still blocked. Try importing cookies.';
                          });
                        }
                      });
                    },
                  ),
                  if (_lastError != null) ...[
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'Error: $_lastError',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // Status bar at bottom
          if (_statusText != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Material(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _statusText!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: [Color(0xFF00E5FF), Color(0xFF76FF03)],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF080711), size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF080711),
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Cookie Import Bottom Sheet
// ──────────────────────────────────────────────────────────────

class _CookieImportSheet extends StatefulWidget {
  final void Function(bool success) onImported;
  const _CookieImportSheet({required this.onImported});

  @override
  State<_CookieImportSheet> createState() => _CookieImportSheetState();
}

class _CookieImportSheetState extends State<_CookieImportSheet> {
  final _controller = TextEditingController();
  bool _importing = false;
  String? _resultText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return;

    setState(() {
      _importing = true;
      _resultText = 'Validating...';
    });

    try {
      // Try JSON array format first
      if (raw.startsWith('[')) {
        await AuthService().setCookiesFromJson(raw);
      } else {
        await AuthService().setCookiesFromString(raw);
      }

      final valid = await AuthService().validateYoutubeCookies();
      if (!mounted) return;

      if (valid) {
        widget.onImported(true);
      } else {
        setState(() {
          _resultText = 'Cookies saved but YouTube rejected the session.\n'
              'Make sure you copied fresh cookies from a signed-in browser.';
        });
      }
    } catch (e) {
      setState(() => _resultText = 'Failed to parse cookies: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsRegular.cookie,
                  color: Color(0xFF00E5FF), size: 24),
              const SizedBox(width: 8),
              const Text('Import YouTube Cookies',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'On your desktop or phone, sign into YouTube in Chrome, '
            'then copy the cookies and paste them below.\n\n'
            'From Chrome DevTools → Application → Cookies → '
            'youtube.com → right-click any cookie → '
            '"Copy as cURL" or use a cookie-export extension.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            maxLines: 6,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Paste cookies here…\n'
                  'Format: name=value; name=value; …\n'
                  'Or paste JSON from a cookie exporter.',
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 11),
              filled: true,
              fillColor: const Color(0xFF2A2A3E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_resultText != null) ...[
            const SizedBox(height: 12),
            Text(
              _resultText!,
              style: TextStyle(
                color: _resultText!.contains('rejected') ||
                        _resultText!.contains('Failed')
                    ? Colors.redAccent
                    : Colors.greenAccent,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: _importing ? null : _import,
              child: Container(
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00E5FF), Color(0xFF76FF03)],
                  ),
                ),
                child: _importing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF080711)),
                      )
                    : const Text(
                        'Import & Validate',
                        style: TextStyle(
                          color: Color(0xFF080711),
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
