import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/album.dart';
import '../../presentation/providers/download_provider.dart';
import '../../presentation/providers/playlist_provider.dart';

class AlbumDownloadIcon extends StatelessWidget {
  final Album album;
  final double size;

  const AlbumDownloadIcon({super.key, required this.album, this.size = 24.0});

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloadProvider>(
      builder: (context, downloadProvider, _) {
        final isDownloading = downloadProvider.isDownloadingPlaylist(album.id);
        final isDownloaded = downloadProvider.isPlaylistFullyDownloaded(album.id);

        Widget icon;
        if (isDownloading) {
          icon = SizedBox(
            width: size,
            height: size,
            child: const CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFEAB308)),
          );
        } else if (isDownloaded) {
          icon = Icon(Icons.download_done, color: Colors.red, size: size);
        } else {
          icon = Icon(Icons.download_for_offline, color: Colors.white54, size: size);
        }

        return GestureDetector(
          onTap: () {
            if (!isDownloading && !isDownloaded) {
              final playlistProvider = context.read<PlaylistProvider>();
              downloadProvider.downloadAlbum(album, playlistProvider);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: icon,
          ),
        );
      },
    );
  }
}
