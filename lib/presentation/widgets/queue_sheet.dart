import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/utils/format_duration.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';

class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, player, _) {
        final queue = player.queue;
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.queue_music, size: 20),
                      const SizedBox(width: 8),
                      Text('Queue (${queue.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (queue.isNotEmpty)
                        TextButton.icon(
                          icon: const Icon(Icons.clear_all, size: 18),
                          label: const Text('Clear'),
                          onPressed: () {
                            Navigator.pop(context);
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Clear queue?'),
                                content: Text('${queue.length} tracks will be removed.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                  TextButton(onPressed: () {
                                    player.clearQueue();
                                    Navigator.pop(ctx);
                                  }, child: const Text('Clear')),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (queue.isEmpty)
                  Expanded(
                    child: Center(child: Text('Queue is empty', style: TextStyle(color: Colors.grey[400]))),
                  )
                else
                  Expanded(
                    child: ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      itemCount: queue.length,
                      onReorderItem: player.reorderQueue,
                      itemBuilder: (context, index) {
                        final track = queue[index];
                        final isCurrent = index == player.currentIndex;
                        return ListTile(
                          key: ValueKey('${track.id}_$index'),
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ReorderableDragStartListener(
                                index: index,
                                child: const Icon(Icons.drag_handle, size: 20),
                              ),
                              const SizedBox(width: 4),
                              isCurrent
                                  ? Icon(Icons.play_arrow, color: Theme.of(context).colorScheme.primary, size: 20)
                                  : Text('${index + 1}', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                            ],
                          ),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                              color: isCurrent ? Theme.of(context).colorScheme.primary : null,
                            ),
                          ),
                          subtitle: Text(
                            '${track.author ?? "Unknown"} · ${formatDuration(track.duration)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => player.removeFromQueue(index),
                          ),
                          onTap: isCurrent ? null : () {
                            final quality = context.read<SettingsProvider>().audioQuality;
                            player.playFromQueue(index, quality: quality);
                          },
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
