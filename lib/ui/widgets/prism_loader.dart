import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'aurora_glass.dart';

class PrismLoader extends StatefulWidget {
  final String title;
  final String subtitle;

  const PrismLoader({
    super.key,
    this.title = 'Preparing your prism',
    this.subtitle = 'Syncing tracks, artwork, lyrics, and offline signals.',
  });

  @override
  State<PrismLoader> createState() => _PrismLoaderState();
}

class _PrismLoaderState extends State<PrismLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: AuroraGlass(
          borderRadius: 32,
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Rotating Ring Loader
              RotationTransition(
                turns: _controller,
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        ZypAuroraColors.cyan,
                        ZypAuroraColors.violet,
                        ZypAuroraColors.pink,
                        ZypAuroraColors.peach,
                        ZypAuroraColors.lime,
                        ZypAuroraColors.cyan,
                      ],
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: const BoxDecoration(
                        color: ZypAuroraColors.ink,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              // Status text
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.58),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
