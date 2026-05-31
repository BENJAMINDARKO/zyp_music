import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/repeat_mode.dart' as repeat;
import '../../core/utils/format_duration.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/queue_sheet.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<PlayerProvider, SettingsProvider>(
      builder: (context, player, settings, _) {
        if (player.currentTrack == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Player')),
            body: const Center(child: Text('No track playing')),
          );
        }

        final track = player.currentTrack!;
        final progress = player.duration.inMilliseconds > 0
            ? player.position.inMilliseconds / player.duration.inMilliseconds
            : 0.0;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Now Playing'),
            actions: [
              if (player.isSleepTimerActive)
                TextButton(
                  onPressed: () => _showSleepTimerDialog(context, player),
                  child: Text(
                    formatDuration(player.sleepTimerRemaining ?? Duration.zero),
                    style: const TextStyle(color: Colors.orange, fontSize: 13),
                  ),
                ),
              IconButton(
                icon: Icon(
                  player.isSleepTimerActive ? Icons.timer_off : Icons.timer,
                  color: player.isSleepTimerActive ? Colors.orange : null,
                ),
                tooltip: player.isSleepTimerActive ? 'Cancel sleep timer' : 'Sleep timer',
                onPressed: () {
                  if (player.isSleepTimerActive) {
                    player.cancelSleepTimer();
                  } else {
                    _showSleepTimerDialog(context, player);
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.queue_music),
                tooltip: 'Queue (${player.queue.length})',
                onPressed: () => _showQueueSheet(context),
              ),
              if (player.queue.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear_all),
                  tooltip: 'Clear queue',
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Clear queue?'),
                        content: Text('${player.queue.length} tracks in queue will be removed.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () {
                              player.clearQueue();
                              Navigator.pop(ctx);
                            },
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 300,
                    child: CachedNetworkImage(
                      imageUrl: track.thumbnailUrl ?? '',
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          Container(color: Colors.grey[800]),
                      errorWidget: (context, url, error) =>
                          const Icon(Icons.music_video, size: 64, color: Colors.grey),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  track.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  track.author ?? '',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Text(formatDuration(player.position),
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: Theme.of(context).colorScheme.primary,
                          inactiveTrackColor: Colors.grey[800],
                          thumbColor: Theme.of(context).colorScheme.primary,
                          overlayColor: Theme.of(context).colorScheme.primary.withAlpha(30),
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        ),
                        child: Slider(
                          value: progress.clamp(0.0, 1.0),
                          onChanged: (v) {
                            final pos = Duration(
                              milliseconds: (v * player.duration.inMilliseconds).round(),
                            );
                            player.seekTo(pos);
                          },
                        ),
                      ),
                    ),
                    Text(formatDuration(player.duration),
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.shuffle,
                        color: player.shuffleMode
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      iconSize: 24,
                      tooltip: player.shuffleMode ? 'Disable shuffle' : 'Enable shuffle',
                      onPressed: player.toggleShuffle,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.skip_previous, size: 28),
                      onPressed: player.currentIndex > 0 ? () => player.previous() : null,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: player.isLoading
                          ? const SizedBox(
                              width: 48,
                              height: 48,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              icon: Icon(
                                player.isPlaying
                                    ? Icons.pause_circle_filled
                                    : Icons.play_circle_filled,
                                size: 52,
                              ),
                              color: Theme.of(context).colorScheme.primary,
                              onPressed: player.togglePlayPause,
                            ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.skip_next, size: 28),
                      onPressed: player.currentIndex + 1 < player.queue.length
                          ? () => player.next()
                          : null,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: _repeatIcon(player.repeatMode),
                      iconSize: 24,
                      color: player.repeatMode != repeat.PlaybackRepeatMode.none
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      tooltip: _repeatTooltip(player.repeatMode),
                      onPressed: player.cycleRepeatMode,
                    ),
                  ],
                ),
                if (player.error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    player.error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
                const Spacer(),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showQueueSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (_) => const QueueSheet(),
    );
  }

  void _showSleepTimerDialog(BuildContext context, PlayerProvider player) {
    final options = [
      15, 30, 60,
    ];
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Sleep Timer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            if (player.isSleepTimerActive)
              ListTile(
                leading: const Icon(Icons.timer_off, color: Colors.red),
                title: const Text('Turn off timer'),
                onTap: () {
                  player.cancelSleepTimer();
                  Navigator.pop(ctx);
                },
              ),
            ...options.map((minutes) => ListTile(
              leading: const Icon(Icons.timer),
              title: Text(minutes >= 60 ? '${minutes ~/ 60}h ${minutes % 60}m' : '${minutes}m'),
              onTap: () {
                player.startSleepTimer(Duration(minutes: minutes));
                Navigator.pop(ctx);
              },
            )),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Custom...'),
              onTap: () {
                Navigator.pop(ctx);
                _showCustomSleepTimer(context, player);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showCustomSleepTimer(BuildContext context, PlayerProvider player) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom sleep timer'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Minutes'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final minutes = int.tryParse(controller.text);
              if (minutes != null && minutes > 0) {
                player.startSleepTimer(Duration(minutes: minutes));
              }
              Navigator.pop(ctx);
            },
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }

  Icon _repeatIcon(repeat.PlaybackRepeatMode mode) {
    switch (mode) {
      case repeat.PlaybackRepeatMode.none:
        return const Icon(Icons.repeat);
      case repeat.PlaybackRepeatMode.one:
        return const Icon(Icons.repeat_one);
      case repeat.PlaybackRepeatMode.all:
        return const Icon(Icons.repeat);
    }
  }

  String _repeatTooltip(repeat.PlaybackRepeatMode mode) {
    switch (mode) {
      case repeat.PlaybackRepeatMode.none:
        return 'No repeat';
      case repeat.PlaybackRepeatMode.one:
        return 'Repeat one';
      case repeat.PlaybackRepeatMode.all:
        return 'Repeat all';
    }
  }
}
