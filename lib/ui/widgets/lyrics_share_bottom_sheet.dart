import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_theme.dart';
import 'lyrics_share_card.dart';

class LyricsShareBottomSheet extends StatefulWidget {
  final List<String> selectedLines;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final Color dominantColor;

  const LyricsShareBottomSheet({
    key,
    required this.selectedLines,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    required this.dominantColor,
  }) : super(key: key);

  static Future<void> show(
    BuildContext context, {
    required List<String> selectedLines,
    required String title,
    required String artist,
    String? thumbnailUrl,
    required Color dominantColor,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LyricsShareBottomSheet(
        selectedLines: selectedLines,
        title: title,
        artist: artist,
        thumbnailUrl: thumbnailUrl,
        dominantColor: dominantColor,
      ),
    );
  }

  @override
  State<LyricsShareBottomSheet> createState() => _LyricsShareBottomSheetState();
}

class _LyricsShareBottomSheetState extends State<LyricsShareBottomSheet> {
  final _repaintKey = GlobalKey();
  String _selectedTheme = 'aurora'; // 'aurora', 'obsidian', 'emerald', 'lavender', 'sunrise'
  LyricCardStyle _selectedStyle = LyricCardStyle.defaultGlass;
  bool _isSharing = false;

  Future<void> _share(String targetPlatform) async {
    if (widget.selectedLines.length > 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can select a maximum of 6 lines.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() => _isSharing = true);
    try {
      // Give Flutter one frame to settle the repaint boundary at full size
      await Future.delayed(const Duration(milliseconds: 100));
      final bytes = await LyricsShareCard.capture(_repaintKey);
      if (bytes == null || !mounted) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/zyp_lyrics_share.png');
      await file.writeAsBytes(bytes);

      // Show toast or share
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sharing via $targetPlatform...'),
          backgroundColor: ZypAuroraColors.ink2,
          duration: const Duration(seconds: 1),
        ),
      );

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: '${widget.title} — ${widget.artist}\n\n'
              '"${widget.selectedLines.join('\n')}"\n\nvia Zyp Music',
        ),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: true,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12, top: 20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              decoration: BoxDecoration(
                color: ZypAuroraColors.glass,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: ZypAuroraColors.stroke, width: 1),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    const Text(
                      'Lyric Share Studio',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Style Tabs Selector
                    _buildStyleSelector(),
                    const SizedBox(height: 12),

                    // Card Preview
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 240),
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                                  CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                                ),
                                child: child,
                              ),
                            );
                          },
                          child: LyricsShareCard(
                            key: ValueKey(_selectedStyle),
                            repaintKey: _repaintKey,
                            selectedLines: widget.selectedLines,
                            title: widget.title,
                            artist: widget.artist,
                            thumbnailUrl: widget.thumbnailUrl,
                            themeName: _selectedTheme,
                            selectedStyle: _selectedStyle,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Theme selector row (only visible/expanded for Default style)
                    AnimatedCrossFade(
                      firstChild: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildThemeRow(),
                          const SizedBox(height: 20),
                        ],
                      ),
                      secondChild: const SizedBox.shrink(),
                      crossFadeState: _selectedStyle == LyricCardStyle.defaultGlass
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                      duration: const Duration(milliseconds: 200),
                    ),

                    // Share button
                    _buildShareButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStyleSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            Expanded(child: _buildStyleTab(LyricCardStyle.defaultGlass, 'Default')),
            Expanded(child: _buildStyleTab(LyricCardStyle.glassPoem, 'Glass Poem')),
            Expanded(child: _buildStyleTab(LyricCardStyle.minimal, 'Minimal')),
          ],
        ),
      ),
    );
  }

  Widget _buildStyleTab(LyricCardStyle style, String label) {
    final isSelected = _selectedStyle == style;
    return GestureDetector(
      onTap: () => setState(() => _selectedStyle = style),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: isSelected
              ? const LinearGradient(
                  colors: [ZypAuroraColors.cyan, ZypAuroraColors.peach],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: isSelected ? Colors.black : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThemeRow() {
    final themes = [
      {
        'id': 'aurora',
        'title': 'Aurora',
        'grad': const LinearGradient(colors: [ZypAuroraColors.cyan, ZypAuroraColors.pink, ZypAuroraColors.peach]),
      },
      {
        'id': 'obsidian',
        'title': 'Obsidian',
        'color': ZypAuroraColors.ink2,
        'border': Border.all(color: Colors.white.withOpacity(0.4), width: 1),
      },
      {
        'id': 'emerald',
        'title': 'Emerald',
        'grad': const LinearGradient(colors: [Color(0xFF059669), Color(0xFF10B981)]),
      },
      {
        'id': 'lavender',
        'title': 'Lavender',
        'grad': const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFA78BFA)]),
      },
      {
        'id': 'sunrise',
        'title': 'Sunrise',
        'grad': const LinearGradient(colors: [Color(0xFFEA580C), Color(0xFFF97316)]),
      },
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: themes.map((t) {
        final id = t['id'] as String;
        final isSelected = _selectedTheme == id;
        final grad = t['grad'] as LinearGradient?;
        final color = t['color'] as Color?;
        final border = t['border'] as BoxBorder?;

        return GestureDetector(
          onTap: () => setState(() => _selectedTheme = id),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: grad,
              color: color,
              border: isSelected
                  ? Border.all(color: Colors.white, width: 3)
                  : (border ?? Border.all(color: Colors.white.withOpacity(0.12), width: 1)),
            ),
            child: isSelected
                ? Center(
                    child: Icon(
                      Icons.check,
                      color: id == 'aurora' ? Colors.black : Colors.white,
                      size: 16,
                    ),
                  )
                : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildShareButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [ZypAuroraColors.cyan, ZypAuroraColors.peach],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            onPressed: _isSharing ? null : () => _share('System Share'),
            icon: _isSharing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Icon(
                    Icons.share_rounded,
                    color: Colors.black,
                    size: 20,
                  ),
            label: Text(
              _isSharing ? 'PREPARING...' : 'SHARE',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Colors.black,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
