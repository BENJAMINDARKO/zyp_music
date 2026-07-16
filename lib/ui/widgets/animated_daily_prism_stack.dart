import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class AnimatedDailyPrismStack extends StatefulWidget {
  const AnimatedDailyPrismStack({super.key});

  @override
  State<AnimatedDailyPrismStack> createState() =>
      _AnimatedDailyPrismStackState();
}

class _AnimatedDailyPrismStackState extends State<AnimatedDailyPrismStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildCard({
    required double left,
    required double top,
    required double baseRotation,
    required double delay,
    required Color color,
  }) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final reduceMotion = MediaQuery.of(context).disableAnimations;
        final raw = (_controller.value + delay) % 1.0;
        final wave = reduceMotion ? 0.0 : sin(raw * pi);
        final translateY = -wave * 9;
        final rotation = baseRotation * (1 - wave * 0.35);
        final scale = 1.0 + (wave * 0.035);

        return Positioned(
          left: left,
          top: top + translateY,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..translate(0.0, -translateY)
              ..rotateZ(rotation)
              ..scale(scale),
            child: Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withOpacity(0.14)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, color.withOpacity(0.4)],
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      height: 112,
      child: Stack(
        children: [
          _buildCard(
            left: 0,
            top: 26,
            baseRotation: -0.14,
            delay: 0.0,
            color: ZypAuroraColors.violet,
          ),
          _buildCard(
            left: 26,
            top: 9,
            baseRotation: 0.14,
            delay: 0.25,
            color: ZypAuroraColors.pink,
          ),
          _buildCard(
            left: 14,
            top: 0,
            baseRotation: 0.02,
            delay: 0.50,
            color: ZypAuroraColors.cyan,
          ),
        ],
      ),
    );
  }
}
