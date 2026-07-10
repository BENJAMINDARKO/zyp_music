import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Darkens [color] so its HSL lightness is at most [maxLightness].
Color darkenColor(Color color, {double maxLightness = 0.20}) {
  final hsl = HSLColor.fromColor(color);
  final clamped = hsl.withLightness(hsl.lightness.clamp(0.0, maxLightness));
  return clamped.toColor();
}

/// Returns a slightly lighter variant of [base] for the card background.
Color cardColorFrom(Color base) {
  final hsl = HSLColor.fromColor(base);
  return hsl.withLightness((hsl.lightness + 0.08).clamp(0.0, 0.35)).toColor();
}

/// Returns a legible text colour (near-white or near-black) for [background].
Color textColorFor(Color background) {
  final brightness = ThemeData.estimateBrightnessForColor(background);
  return brightness == Brightness.dark
      ? const Color(0xFFF5F0DC) // warm cream
      : const Color(0xFF1A1A1A);
}

class LyricsShareCard extends StatelessWidget {
  final GlobalKey repaintKey;
  final List<String> selectedLines;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final Color baseColor;

  const LyricsShareCard({
    super.key,
    required this.repaintKey,
    required this.selectedLines,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    required this.baseColor,
  });

  static Future<Uint8List?> capture(GlobalKey key) async {
    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = darkenColor(baseColor);
    final card = cardColorFrom(bg);
    final textColor = textColorFor(bg);
    final mutedColor = textColor.withOpacity(0.55);

    return RepaintBoundary(
      key: repaintKey,
      child: Container(
        width: 360,
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Song header
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: thumbnailUrl != null
                            ? CachedNetworkImage(
                                imageUrl: thumbnailUrl!,
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) =>
                                    _placeholderThumb(textColor),
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
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              artist,
                              style: TextStyle(
                                color: mutedColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
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
                      color: textColor.withOpacity(0.18),
                      thickness: 1,
                      height: 1,
                    ),
                  ),
                  // Lyrics
                  ...selectedLines.map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        line,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Zyp branding
                  Row(
                    children: [
                      Image.asset(
                        'assets/logo.png',
                        width: 22,
                        height: 22,
                        color: textColor.withOpacity(0.7),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Zyp Music',
                        style: TextStyle(
                          color: textColor.withOpacity(0.7),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.3,
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
    );
  }

  Widget _placeholderThumb(Color color) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.music_note, color: color.withOpacity(0.4), size: 24),
      );
}
