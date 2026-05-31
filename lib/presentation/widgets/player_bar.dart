import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/repeat_mode.dart' as repeat;
import '../providers/player_provider.dart';
import 'queue_sheet.dart';

class PlayerBar extends StatelessWidget {
  final VoidCallback? onTap;

  const PlayerBar({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, player, _) {
        if (player.currentTrack == null) return const SizedBox.shrink();

        final hasPrev = player.queue.isNotEmpty && player.currentIndex > 0;
        final hasNext = player.queue.isNotEmpty && player.currentIndex + 1 < player.queue.length;

        return GestureDetector(
          onTap: onTap,
          child: Container(
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
                          IconButton(
                            icon: const Icon(Icons.queue_music, size: 18),
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                                builder: (_) => const QueueSheet(),
                              );
                            },
                            tooltip: 'Queue (${player.queue.length})',
                          ),
                          if (player.shuffleMode)
                            Icon(Icons.shuffle, size: 14, color: Theme.of(context).colorScheme.primary),
                          if (player.repeatMode != repeat.PlaybackRepeatMode.none)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(
                                player.repeatMode == repeat.PlaybackRepeatMode.one
                                    ? Icons.repeat_one
                                    : Icons.repeat,
                                size: 14,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          if (player.isLoading)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else ...[
                            IconButton(
                              icon: const Icon(Icons.skip_previous),
                              onPressed: hasPrev ? () => player.previous() : null,
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
                              onPressed: hasNext ? () => player.next() : null,
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
                  if (player.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        player.error!,
                        style: const TextStyle(color: Colors.red, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
