import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../domain/entities/video.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final bool isCurrent;
  final VoidCallback onTap;

  const TrackTile({
    super.key,
    required this.track,
    required this.isCurrent,
    required this.onTap,
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
        '${track.author ?? 'Unknown'} · ${_formatDuration(track.duration)}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: isCurrent
          ? const Icon(Icons.play_arrow, size: 20)
          : null,
      onTap: onTap,
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
