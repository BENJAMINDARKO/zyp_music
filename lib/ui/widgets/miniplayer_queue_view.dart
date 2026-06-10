import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../presentation/providers/player_provider.dart';
import 'apple_music_sheet.dart';
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

        return AppleMusicSheet(
          title: 'Playing Next',
          child: SafeArea(
            child: queue.isEmpty
                ? Center(
                    child: Text('Queue is empty', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.38), fontSize: 16)),
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
                                    child: Icon(PhosphorIconsRegular.musicNote, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)),
                                  ),
                                )
                              : Container(
                                  width: 48, height: 48,
                                  color: Colors.grey[800],
                                  child: Icon(PhosphorIconsRegular.musicNote, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)),
                                ),
                        ),
                        title: Text(
                          t.title,
                          style: TextStyle(
                            color: isPlaying ? const Color(0xFFEAB308) : Theme.of(context).colorScheme.onSurface,
                            fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          t.author ?? 'Unknown',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 12),
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
        );
      },
    );
  }
}
