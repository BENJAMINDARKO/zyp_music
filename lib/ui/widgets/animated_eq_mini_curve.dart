import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class AnimatedEqMiniCurve extends StatefulWidget {
  final List<double> values;
  final bool isPlaying;
  final double height;

  const AnimatedEqMiniCurve({
    super.key,
    required this.values,
    this.isPlaying = true,
    this.height = 60,
  });

  @override
  State<AnimatedEqMiniCurve> createState() => _AnimatedEqMiniCurveState();
}

class _AnimatedEqMiniCurveState extends State<AnimatedEqMiniCurve>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.isPlaying) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant AnimatedEqMiniCurve oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isPlaying && _controller.isAnimating) {
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
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: Colors.white.withOpacity(0.045),
            border: Border.all(color: Colors.white.withOpacity(0.075)),
          ),
          child: Row(
            children: List.generate(widget.values.length, (i) {
              final base = widget.values.length > i ? widget.values[i] : 0.0;
              final h = ((base + 12) / 24).clamp(0.0, 1.0);
              final t = (i / widget.values.length);
              final phase = ((_controller.value + t) % 1.0);
              final pulse = reduceMotion
                  ? 1.0
                  : 0.66 + (sin(phase * pi) * 0.34);
              final barHeight = (widget.height - 20) * h * pulse;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Container(
                    height: widget.height - 20,
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: double.infinity,
                      height: barHeight.clamp(2.0, widget.height - 20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: const LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            ZypAuroraColors.pink,
                            ZypAuroraColors.cyan,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
