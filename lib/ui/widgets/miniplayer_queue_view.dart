import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../presentation/providers/player_provider.dart';
import 'miniplayer_flyout_container.dart';
import 'package:mini_music_visualizer/mini_music_visualizer.dart';
import "../../core/utils/thumbnail_url.dart";

class MiniplayerQueueView extends StatelessWidget {
  const MiniplayerQueueView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, player, _) {
        final track = player.currentTrack;
        final queue = player.queue;
        final currentIndex = player.currentIndex;

        return MiniplayerFlyoutContainer(
          thumbnailUrl: track?.thumbnailUrl,
          child: SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
                  child: Row(
                    children: [
                      const Text(
                        'Playing Next',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                // Queue list
                Expanded(
                  child: queue.isEmpty
                      ? const Center(
                          child: Text('Queue is empty', style: TextStyle(color: Colors.white38, fontSize: 16)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: queue.length,
                          itemBuilder: (context, index) {
                            final t = queue[index];
                            final isPlaying = index == currentIndex;

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: (t.thumbnailUrl?.isNotEmpty ?? false)
                                    ? CachedNetworkImage(
                                        imageUrl: rewriteThumbnailSize(t.thumbnailUrl),
                                        width: 48,
                                        height: 48,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) => Container(
                                          width: 48, height: 48,
                                          color: Colors.grey[800],
                                          child: const Icon(Icons.music_note, color: Colors.white54),
                                        ),
                                      )
                                    : Container(
                                        width: 48, height: 48,
                                        color: Colors.grey[800],
                                        child: const Icon(Icons.music_note, color: Colors.white54),
                                      ),
                              ),
                              title: Text(
                                t.title,
                                style: TextStyle(
                                  color: isPlaying ? const Color(0xFFEAB308) : Colors.white,
                                  fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                t.author ?? 'Unknown',
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: isPlaying
                                  ? SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: MiniMusicVisualizer(
                                        color: const Color(0xFFEAB308),
                                        width: 3,
                                        height: 16,
                                        animate: player.isActuallyPlaying,
                                      ),
                                    )
                                  : null,
                              onTap: () {
                                player.playFromQueue(index);
                                Navigator.of(context).pop();
                              },
                            );
                          },
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
