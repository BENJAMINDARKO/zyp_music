import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../core/theme/app_theme.dart';

class LyricsShareCard extends StatelessWidget {
  final GlobalKey repaintKey;
  final List<String> selectedLines;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final String themeName; // 'aurora', 'obsidian', 'emerald', 'lavender', 'sunrise'

  const LyricsShareCard({
    super.key,
    required this.repaintKey,
    required this.selectedLines,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    required this.themeName,
  });

  static Future<Uint8List?> capture(GlobalKey key) async {
    try {
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Decoration _buildDecoration() {
    switch (themeName) {
      case 'aurora':
        return BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [ZypAuroraColors.cyan, ZypAuroraColors.pink, ZypAuroraColors.peach],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        );
      case 'emerald':
        return BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF059669), Color(0xFF10B981)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        );
      case 'lavender':
        return BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF7C3AED), Color(0xFFA78BFA)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        );
      case 'sunrise':
        return BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFFEA580C), Color(0xFFF97316)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        );
      case 'obsidian':
      default:
        return BoxDecoration(
          color: ZypAuroraColors.ink2,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
        );
    }
  }

  Color _resolveTextColor() {
    if (themeName == 'aurora') {
      return const Color(0xFF05040B);
    }
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final textColor = _resolveTextColor();
    final mutedColor = textColor.withOpacity(0.68);

    return RepaintBoundary(
      key: repaintKey,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(24),
        decoration: _buildDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Glow orb effect for Aurora theme
            if (themeName == 'aurora')
              Container(
                width: double.infinity,
                height: 2,
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: ZypAuroraColors.pink.withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 20,
                    ),
                  ],
                ),
              ),
            
            // Song metadata
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: (thumbnailUrl?.isNotEmpty ?? false)
                      ? CachedNetworkImage(
                          imageUrl: thumbnailUrl!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _placeholderThumb(textColor),
                        )
                      : _placeholderThumb(textColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        artist,
                        style: TextStyle(
                          color: mutedColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Divider(
                color: textColor.withOpacity(0.12),
                thickness: 1,
                height: 1,
              ),
            ),
            
            // Lyrics Preview
            ...selectedLines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  line,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    height: 1.35,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 18),
            
            // Branding
            Text(
              'ZYP GLASSSTREAM',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: themeName == 'obsidian' ? ZypAuroraColors.cyan : mutedColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholderThumb(Color color) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.music_note, color: color.withOpacity(0.4), size: 20),
      );
}
