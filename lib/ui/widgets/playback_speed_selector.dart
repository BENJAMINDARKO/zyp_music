import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import '../../presentation/providers/player_provider.dart';

class PlaybackSpeedSelector extends StatelessWidget {
  const PlaybackSpeedSelector({super.key, this.iconColor});

  final Color? iconColor;



  Color _resolveColor(BuildContext context, {required bool isActive}) {
    if (iconColor != null) return iconColor!;
    final base = Theme.of(context).colorScheme.onSurface;
    return isActive ? base : base.withOpacity(0.70);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, player, _) {
        final currentSpeed = player.playbackSpeed;
        final isCustom = currentSpeed != 1.0;
        final color = _resolveColor(context, isActive: isCustom);
        final dimColor = color.withOpacity(0.70);
        return Container(
          key: const Key('playback-speed-selector'),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(
              color: isCustom ? color : dimColor.withOpacity(0.35),
            ),
            borderRadius: BorderRadius.circular(16),
            color: isCustom
                ? color.withOpacity(0.15)
                : Colors.transparent,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  player.setPlaybackSpeed(currentSpeed - 0.01);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Icon(
                    Icons.remove,
                    size: 14,
                    color: dimColor,
                  ),
                ),
              ),
              Icon(
                PhosphorIconsRegular.gauge,
                size: 14,
                color: dimColor,
              ),
              const SizedBox(width: 4),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: () {
                  player.setPlaybackSpeed(1.0);
                },
                child: Text(
                  '${currentSpeed.toStringAsFixed(2)}x',
                  style: TextStyle(
                    fontSize: 12,
                    color: dimColor,
                    fontWeight: isCustom ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  player.setPlaybackSpeed(currentSpeed + 0.01);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Icon(
                    Icons.add,
                    size: 14,
                    color: dimColor,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
