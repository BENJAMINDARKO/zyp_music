import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../domain/entities/playlist.dart';

class PlaylistCard extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;
  final VoidCallback? onPlay;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;
  final bool isCurrentPlaylist;
  final bool isPlaying;
  final bool isDownloaded;
  final bool isDownloading;
  final double? downloadProgress;

  const PlaylistCard({
    super.key,
    required this.playlist,
    required this.onTap,
    this.onPlay,
    this.onDownload,
    this.onDelete,
    this.isCurrentPlaylist = false,
    this.isPlaying = false,
    this.isDownloaded = false,
    this.isDownloading = false,
    this.downloadProgress,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(playlist.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        if (onDelete == null) return false;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Remove playlist'),
            content: const Text('Remove this playlist from your library?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Remove', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          onDelete!.call();
        }
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: isCurrentPlaylist
              ? const Border(
                  left: BorderSide(color: Color(0xFF1DB954), width: 4),
                )
              : null,
        ),
        child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: const EdgeInsets.all(8),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: CachedNetworkImage(
                    imageUrl: playlist.thumbnailUrl ?? '',
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(color: Colors.grey[800]),
                    errorWidget: (context, url, error) => const Icon(Icons.music_note, color: Colors.grey),
                  ),
                ),
              ),
              title: Text(
                playlist.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${playlist.videoCount} tracks${playlist.author != null ? ' · ${playlist.author}' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onPlay != null)
                      IconButton(
                        icon: Icon(
                          isCurrentPlaylist && isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                          size: 20,
                        ),
                        onPressed: onPlay,
                      ),
                    if (onDownload != null)
                      IconButton(
                        icon: Icon(
                          Icons.download,
                          size: 20,
                          color: isDownloaded
                              ? Colors.green
                              : isDownloading
                                  ? Colors.orange
                                  : null,
                        ),
                        onPressed: onDownload,
                      ),
                  ],
                ),
              onTap: onTap,
            ),
            if (isDownloading && downloadProgress != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(
                  value: downloadProgress!.clamp(0.0, 1.0),
                  minHeight: 2,
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}
