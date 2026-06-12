import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/album.dart';
import '../../presentation/providers/download_provider.dart';

class AlbumExportIcon extends StatefulWidget {
  final Album album;
  final double size;

  const AlbumExportIcon({super.key, required this.album, this.size = 24.0});

  @override
  State<AlbumExportIcon> createState() => _AlbumExportIconState();
}

class _AlbumExportIconState extends State<AlbumExportIcon> {
  @override
  void initState() {
    super.initState();
    _checkExported();
  }

  @override
  void didUpdateWidget(covariant AlbumExportIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.album.id != widget.album.id) {
      _checkExported();
    }
  }

  void _checkExported() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final downloadProvider = context.read<DownloadProvider>();
        for (final track in widget.album.tracks) {
          downloadProvider.isExported(track);
        }
      }
    });
  }

  void _onTap(BuildContext context) {
    final downloadProvider = context.read<DownloadProvider>();
    if (downloadProvider.isAlbumExported(widget.album)) {
      downloadProvider.unexportAlbum(widget.album);
    } else {
      downloadProvider.exportAlbum(widget.album);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloadProvider>(
      builder: (context, downloadProvider, _) {
        final isExported = downloadProvider.isAlbumExported(widget.album);
        final isExporting = downloadProvider.isAlbumExporting(widget.album);

        Widget icon;
        if (isExporting) {
          icon = SizedBox(
            width: widget.size,
            height: widget.size,
            child: const CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.green,
            ),
          );
        } else if (isExported) {
          icon = Icon(
            PhosphorIconsFill.thumbsUp,
            color: Colors.green,
            size: widget.size,
          );
        } else {
          icon = Icon(
            PhosphorIconsRegular.thumbsUp,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
            size: widget.size,
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onTap(context),
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: icon,
          ),
        );
      },
    );
  }
}
