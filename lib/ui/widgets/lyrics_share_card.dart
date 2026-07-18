import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../core/theme/app_theme.dart';

enum LyricCardStyle {
  defaultGlass,
  glassPoem,
  minimal,
}

class LyricsShareCard extends StatelessWidget {
  final GlobalKey repaintKey;
  final List<String> selectedLines;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final String themeName; // 'aurora', 'obsidian', 'emerald', 'lavender', 'sunrise'
  final LyricCardStyle selectedStyle;

  const LyricsShareCard({
    super.key,
    required this.repaintKey,
    required this.selectedLines,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    required this.themeName,
    required this.selectedStyle,
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
    if (selectedStyle == LyricCardStyle.minimal) {
      return BoxDecoration(
        color: ZypAuroraColors.ink2.withOpacity(0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
      );
    }

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
    if (selectedStyle == LyricCardStyle.minimal) {
      return Colors.white;
    }
    if (themeName == 'aurora') {
      return const Color(0xFF05040B);
    }
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    if (selectedStyle == LyricCardStyle.glassPoem) {
      final isCompact = selectedLines.length > 3;
      final artSize = isCompact ? 58.0 : 68.0;
      final artRadius = isCompact ? 12.0 : 16.0;
      final titleSize = isCompact ? 16.0 : 20.0;
      final artistSize = isCompact ? 13.0 : 15.0;
      final lyricsMarginTop = isCompact ? 20.0 : 32.0;
      final quoteLeftSize = isCompact ? 52.0 : 64.0;
      final quoteRightSize = isCompact ? 44.0 : 54.0;
      final wavesBottom = isCompact ? 66.0 : 82.0;
      final wavesOpacity = isCompact ? 0.20 : 0.26;

      return RepaintBoundary(
        key: repaintKey,
        child: SizedBox(
          width: 320,
          height: 400,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(34),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                // Base dark gradient
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(34),
                      border: Border.all(color: const Color(0xFFEBF1FF).withOpacity(0.55), width: 2),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF293352),
                          Color(0xFF12172F),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.56),
                          blurRadius: 90,
                          offset: const Offset(0, 30),
                        ),
                      ],
                    ),
                  ),
                ),
                // Top-left pink radial glow (~18% 10%)
                Positioned(
                  top: -20,
                  left: -20,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFFFCDD5).withOpacity(0.26),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // Bottom-right peach radial glow (~86% 84%)
                Positioned(
                  bottom: -50,
                  right: -50,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFFF7AA5).withOpacity(0.26),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // Mid-right blue radial glow (~76% 28%)
                Positioned(
                  top: 60,
                  right: -30,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF7EA8FF).withOpacity(0.18),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // White gloss sheen overlay (::before)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(34),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFFFF8F8),
                            Color(0x00FFFFFF),
                            Color(0x00FFFFFF),
                            Color(0x1AFFFFFF),
                          ],
                          stops: [0.0, 0.25, 0.68, 1.0],
                        ),
                      ),
                      // CSS equivalent: opacity: .72 from ::before
                      // We embed the opacity in the gradient colors above
                    ),
                  ),
                ),
                // Bottom-right glow orb (::after)
                Positioned(
                  right: -80,
                  bottom: -80,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFFF7D9B).withOpacity(0.32),
                          Colors.transparent,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF7D9B).withOpacity(0.20),
                          blurRadius: 40,
                        ),
                      ],
                    ),
                  ),
                ),
                // Dotted Pattern Top Right
                Positioned(
                  top: 34,
                  right: 35,
                  child: SizedBox(
                    width: 78,
                    height: 78,
                    child: CustomPaint(
                      painter: DottedPatternPainter(),
                    ),
                  ),
                ),
                // Decorative Quotes (Opening) — left
                Positioned(
                  left: 25,
                  top: isCompact ? 82.0 : 98.0,
                  child: Text(
                    '“',
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: quoteLeftSize,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFFFF8FA3).withOpacity(0.9),
                      height: 1.0,
                    ),
                  ),
                ),
                // Decorative closing quote — right
                Positioned(
                  right: 33,
                  bottom: isCompact ? 70.0 : 86.0,
                  child: Text(
                    '”',
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: quoteRightSize,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFFA7A6FF).withOpacity(0.85),
                      height: 1.0,
                    ),
                  ),
                ),
                // Decorative Waves at Bottom
                Positioned(
                  left: -26,
                  right: -26,
                  bottom: wavesBottom,
                  height: 120,
                  child: Opacity(
                    opacity: wavesOpacity,
                    child: Transform.rotate(
                      angle: -3 * 3.14159 / 180,
                      child: ClipRect(
                        child: CustomPaint(
                          painter: WaveLinesPainter(),
                        ),
                      ),
                    ),
                  ),
                ),
                // Foreground content (meta + lyrics + footer)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header — meta section matching HTML grid cols
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(artRadius),
                            child: (thumbnailUrl?.isNotEmpty ?? false)
                                ? CachedNetworkImage(
                                    imageUrl: thumbnailUrl!,
                                    width: artSize,
                                    height: artSize,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => _poemPlaceholderThumb(artSize, artRadius),
                                  )
                                : _poemPlaceholderThumb(artSize, artRadius),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: titleSize,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.8,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  artist,
                                  style: TextStyle(
                                    color: const Color(0xFFFF8FA3),
                                    fontSize: artistSize,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: lyricsMarginTop),
                      // Lyrics lines
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: RichText(
                          text: TextSpan(
                            children: _buildPoemLineSpans(selectedLines),
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Footer — always visible at bottom
                      Row(
                        children: [
                          _buildSpark(),
                          const SizedBox(width: 12),
                          Container(
                            width: 44,
                            height: 2,
                            color: Colors.white.withOpacity(0.22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'LYRICS FROM ${title.toUpperCase()}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.8,
                                color: Color(0xFFEBF1FF),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final textColor = _resolveTextColor();
    final mutedColor = textColor.withOpacity(0.68);
    final isMinimal = selectedStyle == LyricCardStyle.minimal;

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
            if (themeName == 'aurora' && !isMinimal)
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
                if (isMinimal) ...[
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: const Text(
                      'MIN',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            
            if (!isMinimal)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Divider(
                  color: textColor.withOpacity(0.12),
                  thickness: 1,
                  height: 1,
                ),
              )
            else
              const SizedBox(height: 24),
            
            if (isMinimal)
              // Minimal style draws the lyrics as a single continuous paragraph text
              Text(
                selectedLines.join(', '),
                style: TextStyle(
                  color: textColor,
                  fontSize: selectedLines.length > 3 ? 15.0 : 20.0,
                  fontWeight: FontWeight.w900,
                  height: 1.3,
                  letterSpacing: -0.6,
                ),
              )
            else
              // Default Glass style has inner rounded list blocks
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white.withOpacity(0.065),
                  border: Border.all(color: Colors.white.withOpacity(0.09)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: selectedLines.map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        line,
                        style: TextStyle(
                          color: textColor,
                          fontSize: selectedLines.length > 3 ? 14.0 : 18.0,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                  ).toList(),
                ),
              ),
            
            const SizedBox(height: 20),
            
            // Branding
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [ZypAuroraColors.cyan, ZypAuroraColors.pink, ZypAuroraColors.peach],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'ZYP MUSIC',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: textColor.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
                if (!isMinimal)
                  Text(
                    'zyp.app/lyrics',
                    style: TextStyle(
                      fontSize: 10,
                      color: textColor.withOpacity(0.5),
                    ),
                  ),
              ],
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

  Widget _poemPlaceholderThumb(double size, double radius) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Icon(Icons.music_note, color: Colors.white30, size: size * 0.4),
      );

  double _poemFontSize(List<String> lines) {
    final count = lines.length;
    final maxLen = lines.fold<int>(0, (max, l) => l.length > max ? l.length : max);
    final score = count + maxLen / 7.0;
    double size;
    if (score <= 5) {
      size = 34;
    } else if (score <= 6) {
      size = 30;
    } else if (score <= 7) {
      size = 27;
    } else if (score <= 9) {
      size = 23;
    } else if (score <= 11) {
      size = 20;
    } else if (score <= 14) {
      size = 17;
    } else {
      size = 14;
    }
    return size;
  }

  List<InlineSpan> _buildPoemLineSpans(List<String> lines) {
    final List<InlineSpan> spans = [];
    final fontSize = _poemFontSize(lines);
    final lineHeight = fontSize >= 26 ? 1.02 : 1.15;
    final letterSpacing = fontSize >= 26 ? -0.65 : -0.3;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      Color color = Colors.white;
      if (lines.length > 1) {
        if (i == 1) {
          color = const Color(0xFFFF8FA3); // rose highlight
        } else if (i == lines.length - 1) {
          color = const Color(0xFFA8A1FF); // violet highlight
        }
      }
      spans.add(TextSpan(
        text: line,
        style: TextStyle(
          fontFamily: 'Georgia',
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          height: lineHeight,
          letterSpacing: letterSpacing,
          color: color,
        ),
      ));
      if (i < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }
    return spans;
  }

  Widget _buildSpark() {
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 6,
            height: 24,
            decoration: BoxDecoration(
              color: const Color(0xFFFF9AA9),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Container(
            width: 24,
            height: 6,
            decoration: BoxDecoration(
              color: const Color(0xFFFF9AA9),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ),
    );
  }
}

class DottedPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, ui.Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.48)
      ..style = PaintingStyle.fill;

    const double spacing = 14.0;
    const double radius = 1.6;

    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x + radius, y + radius), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class WaveLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, ui.Size size) {
    final paint = Paint()
      ..color = const Color(0xFFAADCFF).withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final center = Offset(size.width * 0.18, size.height);

    for (double r = 12.0; r < size.width * 1.5; r += 24.0) {
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
