import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'dart:math';

enum SeekbarStyle { gradient, waveform, minimal, wavy, segmented }

class CustomAudioSeekbar extends StatefulWidget {
  final double value;
  final double secondaryValue;
  final ValueChanged<double>? onChanged;
  final VoidCallback? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final Color activeColor;
  final Color inactiveColor;
  final SeekbarStyle style;
  final bool invertColor;

  /// Whether audio is actively playing. Drives the wave phase animation.
  final bool isPlaying;

  const CustomAudioSeekbar({
    super.key,
    required this.value,
    this.secondaryValue = 0.0,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.activeColor = Colors.white,
    this.inactiveColor = Colors.white24,
    this.style = SeekbarStyle.minimal,
    this.invertColor = false,
    this.isPlaying = false,
  });

  @override
  State<CustomAudioSeekbar> createState() => _CustomAudioSeekbarState();
}

class _CustomAudioSeekbarState extends State<CustomAudioSeekbar>
    with SingleTickerProviderStateMixin {
  late AnimationController _phaseController;

  @override
  void initState() {
    super.initState();
    // Loop 0→1 over 1.2 s for a natural wave speed.
    _phaseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    if (widget.isPlaying && widget.style == SeekbarStyle.wavy) {
      _phaseController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant CustomAudioSeekbar oldWidget) {
    super.didUpdateWidget(oldWidget);

    final shouldAnimate = widget.isPlaying && widget.style == SeekbarStyle.wavy;
    final wasAnimating =
        oldWidget.isPlaying && oldWidget.style == SeekbarStyle.wavy;

    if (shouldAnimate && !wasAnimating) {
      _phaseController.repeat();
    } else if (!shouldAnimate && wasAnimating) {
      _phaseController.stop();
    }
  }

  @override
  void dispose() {
    _phaseController.dispose();
    super.dispose();
  }

  /// Local drag state. While a drag is in progress, [_effectiveValue]
  /// returns [_dragValue] (the position under the user's finger) so
  /// the painter does not snap back to the last position-tick value
  /// the audio engine emitted. Once the drag ends we null
  /// [_dragValue] out and the next builder call falls back to
  /// `widget.value`, which the [SeekbarConnector] will have updated
  /// via [PlayerProvider.updateSeek] / [PlayerProvider.endSeek].
  double? _dragValue;
  bool _isDragging = false;

  double get _effectiveValue =>
      _isDragging ? (_dragValue ?? widget.value) : widget.value;

  void _updateValue(Offset localPosition, double width) {
    final newValue = (localPosition.dx / width).clamp(0.0, 1.0);
    setState(() {
      _dragValue = newValue;
    });
    widget.onChanged?.call(newValue);
  }

  void _handleDragStart(DragStartDetails details, double width) {
    _isDragging = true;
    widget.onChangeStart?.call();
    _updateValue(details.localPosition, width);
  }

  void _handleDragUpdate(DragUpdateDetails details, double width) {
    _updateValue(details.localPosition, width);
  }

  void _handleDragEnd(DragEndDetails details) {
    _isDragging = false;
    widget.onChangeEnd?.call(_dragValue ?? widget.value);
    setState(() {
      _dragValue = null;
    });
  }

  void _handleTapDown(TapDownDetails details, double width) {
    // Order is critical here:
    //   1. Set _isDragging so _effectiveValue reads _dragValue, not
    //      widget.value (which is the last stream tick and would
    //      snap the thumb back to the engine position).
    //   2. Write _dragValue via _updateValue. The painter needs
    //      this to be set before the callbacks fire, otherwise
    //      the engine-driven updateSeek() called from onChanged
    //      would render the bar at widget.value for one frame.
    //   3. Fire onChangeStart so PlayerProvider can flip the
    //      _isSeeking lock.
    //   4. Fire onChangeEnd so the engine commits the seek.
    //   5. Reset drag state in setState so subsequent
    //      ValueListenableBuilder rebuilds use widget.value.
    _isDragging = true;
    _updateValue(details.localPosition, width);
    widget.onChangeStart?.call();
    widget.onChangeEnd?.call(_dragValue ?? widget.value);
    setState(() {
      _isDragging = false;
      _dragValue = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    Color effectiveColor = widget.activeColor;
    if (widget.invertColor) {
      effectiveColor = effectiveColor.computeLuminance() < 0.5
          ? Colors.white
          : Colors.black;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onHorizontalDragStart: (details) =>
              _handleDragStart(details, constraints.maxWidth),
          onHorizontalDragUpdate: (details) =>
              _handleDragUpdate(details, constraints.maxWidth),
          onHorizontalDragEnd: _handleDragEnd,
          onTapDown: (details) => _handleTapDown(details, constraints.maxWidth),
          child: Container(
            width: constraints.maxWidth,
            height: 24, // Touch target height
            color: Colors.transparent,
            child: AnimatedBuilder(
              animation: _phaseController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _SeekbarPainter(
                    value: _effectiveValue,
                    secondaryValue: widget.secondaryValue,
                    activeColor: effectiveColor,
                    inactiveColor: widget.inactiveColor,
                    style: widget.style,
                    // φ = controller.value × 2π  (full cycle per loop)
                    wavePhaseFraction: _phaseController.value,
                  ),
                );
              },
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
  final Color inactiveColor;
  final SeekbarStyle style;

  /// Normalised phase in [0, 1] → mapped to [0, 2π] inside the painter.
  final double wavePhaseFraction;

  _SeekbarPainter({
    required this.value,
    required this.secondaryValue,
    required this.activeColor,
    required this.inactiveColor,
    required this.style,
    this.wavePhaseFraction = 0.0,
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
    final trackPaint = Paint()
      ..color = inactiveColor
      ..strokeWidth = 2;
    final activePaint = Paint()
      ..color = activeColor
      ..strokeWidth = 2;
    final secondaryPaint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 2;
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

    final trackPaint = Paint()
      ..color = inactiveColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), trackPaint);

    if (activeWidth > 0) {
      final gradientPaint = Paint()
        ..shader = LinearGradient(
          colors: [activeColor.withOpacity(0.3), activeColor],
        ).createShader(Rect.fromLTWH(0, 0, activeWidth, size.height))
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(0, cy), Offset(activeWidth, cy), gradientPaint);
    }

    final thumbPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(activeWidth, cy), 5, thumbPaint);
  }

  void _paintWaveform(Canvas canvas, Size size) {
    const barWidth = 3.0;
    const spacing = 2.0;
    final activeWidth = size.width * value;

    // We use a fixed seed based on the screen width to keep waveform consistent
    final rand = Random(42);

    double x = 0;
    while (x < size.width) {
      double maxH = size.height * 0.8;
      double h = (rand.nextDouble() * 0.6 + 0.2) * maxH;

      bool isActive = x <= activeWidth;
      final p = Paint()
        ..color = isActive ? activeColor : inactiveColor
        ..strokeWidth = barWidth
        ..strokeCap = StrokeCap.round;

      final cy = size.height / 2;
      canvas.drawLine(Offset(x, cy - h / 2), Offset(x, cy + h / 2), p);

      x += barWidth + spacing;
    }
  }

  void _paintWavy(Canvas canvas, Size size) {
    // ---- Live Animated Hybrid Progress Bar (Wavy) --------------------------
    //
    // Mathematical model (per spec):
    //
    //   φ  = wavePhaseFraction × 2π          (shifts rightward each frame)
    //   ω  = 2π / waveLength                 (spatial frequency)
    //   A(x) = A_max × (X_split − x) / X_split   for 0 ≤ x ≤ X_split
    //        = 0                                   for x > X_split
    //
    //   Y(x) = cy + A(x) × sin(ω × x − φ)   for 0 ≤ x ≤ X_split
    //   Y(x) = cy                             for x > X_split
    //
    // The linear amplitude envelope [A_max → 0] means the wave naturally
    // "settles" flat right at the progress thumb — no jarring seam.
    // ---------------------------------------------------------------------------

    final xSplit = size.width * value;
    final cy = size.height / 2;

    const double amplitude = 4.5; // A_max  (pixels)
    const double waveLength = 30.0; // pixels per full sine cycle
    final double omega = 2 * pi / waveLength;
    final double phi = wavePhaseFraction * 2 * pi; // live phase offset
    const double step = 1.0; // 1 px sample → smooth curve

    final wavyPaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final flatPaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // ── Played segment: damped sine wave ──────────────────────────────────
    if (xSplit > 0) {
      // Start exactly on the baseline at x = 0 (amplitude is A_max there if
      // xSplit is very small, or full A_max when xSplit ≥ some threshold).
      final y0 = cy + amplitude * sin(omega * 0 - phi);
      final wavePath = Path()..moveTo(0, y0);

      for (double x = step; x <= xSplit; x += step) {
        // Linear damping envelope: full amplitude at x=0, zero at x=xSplit.
        final envelope = (xSplit - x) / xSplit;
        final y = cy + (amplitude * envelope) * sin(omega * x - phi);
        wavePath.lineTo(x, y);
      }
      // Close exactly on the split point at baseline.
      wavePath.lineTo(xSplit, cy);
      canvas.drawPath(wavePath, wavyPaint);
    }

    // ── Unplayed segment: flat line ───────────────────────────────────────
    if (xSplit < size.width) {
      canvas.drawLine(Offset(xSplit, cy), Offset(size.width, cy), flatPaint);
    }

    // ── Thumb marker ─────────────────────────────────────────────────────
    final thumbPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(xSplit, cy), 4, thumbPaint);
  }

  void _paintSegmented(Canvas canvas, Size size) {
    final activeWidth = size.width * value;
    final cy = size.height / 2;

    const int segments = 40;
    final double segWidth = size.width / segments;

    for (int i = 0; i < segments; i++) {
      double x = i * segWidth;
      bool isActive = x <= activeWidth;

      final p = Paint()
        ..color = isActive ? activeColor : inactiveColor
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
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.style != style ||
        oldDelegate.wavePhaseFraction != wavePhaseFraction;
  }
}
