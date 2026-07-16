import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class GlobalBackground extends StatelessWidget {
  const GlobalBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Dark Base Gradient
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                ZypAuroraColors.ink,
                ZypAuroraColors.ink2,
                Color(0xFF060511),
              ],
              stops: [0.0, 0.46, 1.0],
            ),
          ),
        ),

        // 2. Radial Aurora Glows
        // Glow 1: Pink at 12% 9%
        Positioned(
          left: -150,
          top: -150,
          width: 500,
          height: 500,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  ZypAuroraColors.pink.withOpacity(0.44),
                  Colors.transparent,
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),
        // Glow 2: Cyan at 88% 13%
        Positioned(
          right: -150,
          top: -100,
          width: 450,
          height: 450,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  ZypAuroraColors.cyan.withOpacity(0.34),
                  Colors.transparent,
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),
        // Glow 3: Peach at 70% 82%
        Positioned(
          right: -100,
          bottom: -150,
          width: 500,
          height: 500,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  ZypAuroraColors.peach.withOpacity(0.31),
                  Colors.transparent,
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),

        // 3. Subtle Grid Overlay
        Positioned.fill(
          child: CustomPaint(
            painter: _GridPainter(),
          ),
        ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Mask shader for fading grid at edges
    final shader = RadialGradient(
      center: const Alignment(0.0, -0.24), // circle at 50% 38%
      radius: 0.76,
      colors: [
        Colors.white.withOpacity(0.045 * 0.23), // base grid opacity
        Colors.transparent,
      ],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final paint = Paint()
      ..shader = shader
      ..strokeWidth = 1.0;

    const double gridSize = 42.0;

    // Draw vertical lines
    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // Draw horizontal lines
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
