import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/utils/format_duration.dart';
import '../../domain/entities/video.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final bool isCurrent;
  final VoidCallback onTap;
  final bool isDownloaded;
  final bool isDownloading;
  final VoidCallback? onDownload;

  const TrackTile({
    super.key,
    required this.track,
    required this.isCurrent,
    required this.onTap,
    this.isDownloaded = false,
    this.isDownloading = false,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: isCurrent,
      selectedTileColor: Theme.of(context).colorScheme.primary.withAlpha(25),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 48,
          height: 48,
          child: CachedNetworkImage(
            imageUrl: track.thumbnailUrl ?? '',
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(color: Colors.grey[800]),
            errorWidget: (context, url, error) => const Icon(Icons.music_video, color: Colors.grey),
          ),
        ),
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
        '${track.author ?? 'Unknown'} · ${formatDuration(track.duration)}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: isCurrent
          ? const Icon(Icons.play_arrow, size: 20)
          : isDownloading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : isDownloaded
                  ? const Icon(Icons.download_done, size: 18, color: Colors.green)
                  : onDownload != null
                      ? IconButton(
                          icon: const Icon(Icons.download, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: onDownload,
                        )
                      : null,
      onTap: onTap,
    );
  }

}
