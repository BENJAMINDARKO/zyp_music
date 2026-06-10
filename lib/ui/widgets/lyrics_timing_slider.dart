import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../presentation/providers/player_provider.dart';

class LyricsTimingSlider extends StatelessWidget {
  const LyricsTimingSlider({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, player, _) {
        final offsetMs = player.lyricsSyncOffsetMs;
        final offsetSec = offsetMs / 1000.0;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Row(
            children: [
              Text(
                'Sync',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  key: const Key('lyrics-timing-slider'),
                  value: offsetSec.clamp(-5.0, 5.0),
                  min: -5.0,
                  max: 5.0,
                  divisions: 100,
                  label: '${offsetSec >= 0 ? '+' : ''}${offsetSec.toStringAsFixed(1)}s',
                  onChanged: (value) {
                    player.setLyricsSyncOffsetMs((value * 1000).round());
                  },
                ),
              ),
              if (offsetMs != 0)
                IconButton(
                  icon: Icon(
                    Icons.restart_alt,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.70),
                  ),
                  onPressed: () => player.setLyricsSyncOffsetMs(0),
                  tooltip: 'Reset sync offset',
                  visualDensity: VisualDensity.compact,
                ),
              SizedBox(
                width: 48,
                child: Text(
                  '${offsetSec >= 0 ? '+' : ''}${offsetSec.toStringAsFixed(1)}s',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.70),
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
