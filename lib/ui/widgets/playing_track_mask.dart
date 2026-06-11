import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../domain/entities/video.dart';

class PlayingTrackMask extends StatelessWidget {
  final Track track;
  final Widget child;

  const PlayingTrackMask({super.key, required this.track, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, player, _) {
        final isPlayingThisTrack = player.currentTrack?.id == track.id;
        
        if (!isPlayingThisTrack) {
          return child;
        }

        return Stack(
          children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: ValueListenableBuilder<Duration>(
                  valueListenable: player.positionNotifier,
                  builder: (context, position, _) {
                    final duration = player.currentTrack?.duration ?? const Duration(seconds: 1);
                    final progress = duration.inMilliseconds > 0 
                        ? position.inMilliseconds / duration.inMilliseconds 
                        : 0.0;
                    
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: progress.clamp(0.0, 1.0),
                        child: Container(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
