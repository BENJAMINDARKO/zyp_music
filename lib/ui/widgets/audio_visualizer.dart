import 'dart:math';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

class AudioVisualizer extends StatefulWidget {
  final String style; // 'Bars', 'Lines', 'Circles'
  final Color color;
  final bool isPlaying;

  const AudioVisualizer({
    super.key,
    required this.style,
    required this.color,
    required this.isPlaying,
  });

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AudioVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !oldWidget.isPlaying) {
      _controller.repeat();
    } else if (!widget.isPlaying && oldWidget.isPlaying) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _VisualizerPainter(
            animationValue: _controller.value,
            style: widget.style,
            color: widget.color,
            isPlaying: widget.isPlaying,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _VisualizerPainter extends CustomPainter {
  final double animationValue;
  final String style;
  final Color color;
  final bool isPlaying;

  _VisualizerPainter({
    required this.animationValue,
    required this.style,
    required this.color,
    required this.isPlaying,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round;

    final random = Random(42); // fixed seed for stable layout
    final center = Offset(size.width / 2, size.height / 2);

    if (style == 'Circles') {
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2.0;
      
      for (int i = 0; i < 5; i++) {
        final phase = (animationValue + i / 5) % 1.0;
        final radius = phase * (size.height / 2);
        final opacity = isPlaying ? (1.0 - phase) : 0.2;
        paint.color = color.withOpacity(opacity);
        canvas.drawCircle(center, radius, paint);
      }
    } else if (style == 'Lines') {
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2.0;
      final path = Path();
      
      final numPoints = 50;
      final stepX = size.width / numPoints;
      
      path.moveTo(0, center.dy);
      for (int i = 1; i <= numPoints; i++) {
        final x = i * stepX;
        final t = i / numPoints;
        final baseAmplitude = sin(t * pi); 
        final dynamicAmplitude = isPlaying ? sin(t * pi * 8 + animationValue * pi * 2) * random.nextDouble() * 20 : 2;
        final y = center.dy + (baseAmplitude * dynamicAmplitude);
        path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    } else {
      // Default to Bars
      paint.style = PaintingStyle.fill;
      final barCount = 40;
      final spacing = 2.0;
      final barWidth = (size.width - (spacing * (barCount - 1))) / barCount;
      
      for (int i = 0; i < barCount; i++) {
        final t = i / barCount;
        final baseHeight = size.height * 0.2;
        final dynamicHeight = isPlaying ? (sin(t * pi * 4 + animationValue * pi * 2).abs() * size.height * 0.8 * random.nextDouble()) : 5.0;
        final height = baseHeight + dynamicHeight;
        
        final x = i * (barWidth + spacing);
        final y = center.dy - height / 2;
        
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, y, barWidth, height), const Radius.circular(2)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _VisualizerPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
           oldDelegate.style != style ||
           oldDelegate.color != color ||
           oldDelegate.isPlaying != isPlaying;
  }
}
