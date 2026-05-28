import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';

class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, player, _) {
        if (player.currentTrack == null) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            boxShadow: [BoxShadow(
              color: Colors.black.withAlpha(77),
              blurRadius: 8,
              offset: const Offset(0, -2),
            )],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            player.currentTrack!.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            player.currentTrack!.author ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (player.isLoading)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else ...[
                          IconButton(
                            icon: const Icon(Icons.skip_previous),
                            onPressed: player.currentIndex > 0 ? () => player.previous() : null,
                            iconSize: 20,
                          ),
                          IconButton(
                            icon: Icon(player.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                            onPressed: player.togglePlayPause,
                            iconSize: 32,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next),
                            onPressed: player.currentIndex + 1 < player.queue.length ? () => player.next() : null,
                            iconSize: 20,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                LinearProgressIndicator(
                  value: player.duration.inMilliseconds > 0
                      ? player.position.inMilliseconds / player.duration.inMilliseconds
                      : 0,
                  backgroundColor: Colors.grey[800],
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
