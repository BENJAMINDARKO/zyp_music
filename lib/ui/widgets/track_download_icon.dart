import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../presentation/providers/download_provider.dart';
import '../../domain/entities/video.dart';

class TrackDownloadIcon extends StatelessWidget {
  final Track track;
  final double size;

  const TrackDownloadIcon({
    super.key,
    required this.track,
    this.size = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloadProvider>(
      builder: (context, downloadProvider, _) {
        final isDownloaded = downloadProvider.isDownloaded(track.id);
        final isDownloading = downloadProvider.isDownloading(track.id);

        if (isDownloaded) {
          return Icon(
            Icons.check_circle,
            color: Colors.red,
            size: size,
          );
        }

        if (isDownloading) {
          return SizedBox(
            width: size,
            height: size,
            child: const CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEAB308)),
            ),
          );
        }

        return GestureDetector(
          onTap: () {
            downloadProvider.downloadTrack(track, track.id);
          },
          child: Icon(
            Icons.download_for_offline_outlined,
            color: Colors.white54,
            size: size,
          ),
        );
      },
    );
  }
}
