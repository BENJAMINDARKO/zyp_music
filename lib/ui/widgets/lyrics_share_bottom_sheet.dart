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
    super.key,
    required this.selectedLines,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    required this.dominantColor,
  });

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
  bool _isSharing = false;

  Future<void> _share(String targetPlatform) async {
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
          content: Text('Sharing to $targetPlatform...'),
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
                    const SizedBox(height: 16),

                    // Card Preview
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: LyricsShareCard(
                          repaintKey: _repaintKey,
                          selectedLines: widget.selectedLines,
                          title: widget.title,
                          artist: widget.artist,
                          thumbnailUrl: widget.thumbnailUrl,
                          themeName: _selectedTheme,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Theme selector row
                    _buildThemeRow(),

                    const SizedBox(height: 20),

                    // Action buttons grid
                    _buildActionGrid(),
                  ],
                ),
              ),
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

  Widget _buildActionGrid() {
    final actions = [
      {'label': 'Instagram Stories', 'icon': '📸', 'platform': 'Instagram'},
      {'label': 'WhatsApp Status', 'icon': '💬', 'platform': 'WhatsApp'},
      {'label': 'Save to Gallery', 'icon': '📥', 'platform': 'Gallery'},
      {'label': 'More Sharing', 'icon': '🔗', 'platform': 'System Share'},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.3,
        children: actions.map((act) {
          return GestureDetector(
            onTap: _isSharing ? null : () => _share(act['platform']!),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.065),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.09)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      color: Colors.white.withOpacity(0.08),
                    ),
                    child: Center(
                      child: Text(
                        act['icon']!,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      act['label']!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
