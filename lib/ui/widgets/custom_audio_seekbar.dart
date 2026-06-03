import 'package:flutter/material.dart';
import 'dart:math';

enum SeekbarStyle {
  gradient,
  waveform,
  minimal,
  wavy,
  segmented,
}

class CustomAudioSeekbar extends StatefulWidget {
  final double value;
  final double secondaryValue;
  final ValueChanged<double> onChanged;
  final Color activeColor;
  final SeekbarStyle style;
  final bool invertColor;

  const CustomAudioSeekbar({
    super.key,
    required this.value,
    required this.secondaryValue,
    required this.onChanged,
    required this.activeColor,
    this.style = SeekbarStyle.minimal,
    this.invertColor = false,
  });

  @override
  State<CustomAudioSeekbar> createState() => _CustomAudioSeekbarState();
}

class _CustomAudioSeekbarState extends State<CustomAudioSeekbar> {
  void _handleUpdate(Offset localPosition, double width) {
    double newValue = (localPosition.dx / width).clamp(0.0, 1.0);
    widget.onChanged(newValue);
  }

  @override
  Widget build(BuildContext context) {
    Color effectiveColor = widget.activeColor;
    if (widget.invertColor) {
      effectiveColor = effectiveColor.computeLuminance() < 0.5 ? Colors.white : Colors.black;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onHorizontalDragUpdate: (details) => _handleUpdate(details.localPosition, constraints.maxWidth),
          onTapDown: (details) => _handleUpdate(details.localPosition, constraints.maxWidth),
          child: Container(
            width: constraints.maxWidth,
            height: 24, // Touch target height
            color: Colors.transparent,
            child: CustomPaint(
              painter: _SeekbarPainter(
                value: widget.value,
                secondaryValue: widget.secondaryValue,
                activeColor: effectiveColor,
                style: widget.style,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SeekbarPainter extends CustomPainter {
  final double value;
  final double secondaryValue;
  final Color activeColor;
  final SeekbarStyle style;

  _SeekbarPainter({
    required this.value,
    required this.secondaryValue,
    required this.activeColor,
    required this.style,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case SeekbarStyle.gradient:
        _paintGradient(canvas, size);
        break;
      case SeekbarStyle.waveform:
        _paintWaveform(canvas, size);
        break;
      case SeekbarStyle.minimal:
        _paintMinimal(canvas, size);
        break;
      case SeekbarStyle.wavy:
        _paintWavy(canvas, size);
        break;
      case SeekbarStyle.segmented:
        _paintSegmented(canvas, size);
        break;
    }
  }

  void _paintMinimal(Canvas canvas, Size size) {
    final trackPaint = Paint()..color = Colors.white24..strokeWidth = 2;
    final activePaint = Paint()..color = activeColor..strokeWidth = 2;
    final secondaryPaint = Paint()..color = Colors.white54..strokeWidth = 2;
    final thumbPaint = Paint()..color = activeColor;

    final cy = size.height / 2;
    final activeWidth = size.width * value;
    final secondaryWidth = size.width * secondaryValue;

    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), trackPaint);
    canvas.drawLine(Offset(0, cy), Offset(secondaryWidth, cy), secondaryPaint);
    canvas.drawLine(Offset(0, cy), Offset(activeWidth, cy), activePaint);

    canvas.drawCircle(Offset(activeWidth, cy), 6, thumbPaint);
  }

  void _paintGradient(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final activeWidth = size.width * value;

    final trackPaint = Paint()..color = Colors.white12..strokeWidth = 4..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), trackPaint);

    if (activeWidth > 0) {
      final gradientPaint = Paint()
        ..shader = LinearGradient(colors: [activeColor.withOpacity(0.3), activeColor]).createShader(Rect.fromLTWH(0, 0, activeWidth, size.height))
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(0, cy), Offset(activeWidth, cy), gradientPaint);
    }

    final thumbPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(activeWidth, cy), 5, thumbPaint);
  }

  void _paintWaveform(Canvas canvas, Size size) {
    final barWidth = 3.0;
    final spacing = 2.0;
    final activeWidth = size.width * value;
    
    // We use a fixed seed based on the screen width to keep waveform consistent
    final rand = Random(42);
    
    double x = 0;
    while (x < size.width) {
      double maxH = size.height * 0.8;
      double h = (rand.nextDouble() * 0.6 + 0.2) * maxH;
      
      bool isActive = x <= activeWidth;
      final p = Paint()
        ..color = isActive ? activeColor : Colors.white24
        ..strokeWidth = barWidth
        ..strokeCap = StrokeCap.round;

      final cy = size.height / 2;
      canvas.drawLine(Offset(x, cy - h/2), Offset(x, cy + h/2), p);
      
      x += barWidth + spacing;
    }
  }

  void _paintWavy(Canvas canvas, Size size) {
    final activeWidth = size.width * value;
    final cy = size.height / 2;
    
    final path = Path();
    path.moveTo(0, cy);
    
    int waveCount = 20;
    double waveLen = size.width / waveCount;
    
    for (int i = 0; i < waveCount; i++) {
      path.quadraticBezierTo(
        waveLen * i + waveLen / 2,
        cy + (i % 2 == 0 ? -4 : 4),
        waveLen * (i + 1),
        cy,
      );
    }

    final trackPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
      
    canvas.drawPath(path, trackPaint);

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, activeWidth, size.height));
    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawPath(path, activePaint);
    canvas.restore();
    
    final thumbPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(activeWidth, cy), 4, thumbPaint);
  }

  void _paintSegmented(Canvas canvas, Size size) {
    final activeWidth = size.width * value;
    final cy = size.height / 2;
    
    int segments = 40;
    double segWidth = size.width / segments;
    
    for (int i = 0; i < segments; i++) {
      double x = i * segWidth;
      bool isActive = x <= activeWidth;
      
      final p = Paint()
        ..color = isActive ? activeColor : Colors.white24
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
        
      canvas.drawLine(Offset(x + 1, cy), Offset(x + segWidth - 2, cy), p);
    }
  }

  @override
  bool shouldRepaint(covariant _SeekbarPainter oldDelegate) {
    return oldDelegate.value != value ||
           oldDelegate.secondaryValue != secondaryValue ||
           oldDelegate.activeColor != activeColor ||
           oldDelegate.style != style;
  }
}
