import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import '../../presentation/providers/player_provider.dart';

class PlaybackSpeedSelector extends StatelessWidget {
  const PlaybackSpeedSelector({super.key, this.iconColor});

  final Color? iconColor;

  static const _speedOptions = [0.5, 1.0, 1.5, 2.0];

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
        return GestureDetector(
          key: const Key('playback-speed-selector'),
          onTap: () {
            final currentIndex = _speedOptions.indexOf(currentSpeed);
            final nextIndex = (currentIndex + 1) % _speedOptions.length;
            player.setPlaybackSpeed(_speedOptions[nextIndex]);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                Icon(
                  PhosphorIconsRegular.gauge,
                  size: 14,
                  color: dimColor,
                ),
                const SizedBox(width: 4),
                Text(
                  '${currentSpeed}x',
                  style: TextStyle(
                    fontSize: 12,
                    color: dimColor,
                    fontWeight: isCustom ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
