import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/video.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/download_provider.dart';
import 'playlist_picker_dialog.dart';

class TrackContextMenu {
  static void show(BuildContext context, Track track) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    if (track.thumbnailUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          track.thumbnailUrl!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.music_note, color: Colors.white54, size: 48),
                        ),
                      )
                    else
                      const Icon(Icons.music_note, color: Colors.white54, size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (track.author != null)
                            Text(
                              track.author!,
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.playlist_add, color: Colors.white),
                title: const Text('Add to Playlist', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (_) => PlaylistPickerDialog(track: track),
                  );
                },
              ),
              Consumer<PlaylistProvider>(
                builder: (context, provider, _) {
                  final isFav = provider.isFavorite(track.id);
                  return ListTile(
                    leading: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      color: isFav ? Colors.red : Colors.white,
                    ),
                    title: const Text('Favorite', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      provider.toggleFavorite(track);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(isFav ? 'Removed from Favorites' : 'Added to Favorites')),
                      );
                    },
                  );
                },
              ),
              Consumer<DownloadProvider>(
                builder: (context, provider, _) {
                  final isDownloaded = provider.downloadedTrackIds.contains(track.id);
                  return ListTile(
                    leading: Icon(
                      isDownloaded ? Icons.download_done : Icons.download,
                      color: isDownloaded ? Colors.green : Colors.white,
                    ),
                    title: const Text('Download', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      if (!isDownloaded) {
                        provider.downloadTrack(track, 'downloads');
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Download started')),
                        );
                      } else {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Already downloaded')),
                        );
                      }
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
