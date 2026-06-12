import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/video.dart';
import '../../presentation/providers/download_provider.dart';

class TrackExportIcon extends StatefulWidget {
  final Track track;
  final double size;

  const TrackExportIcon({
    super.key,
    required this.track,
    this.size = 24.0,
  });

  @override
  State<TrackExportIcon> createState() => _TrackExportIconState();
}

class _TrackExportIconState extends State<TrackExportIcon> {
  @override
  void initState() {
    super.initState();
    _checkExported();
  }

  @override
  void didUpdateWidget(covariant TrackExportIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _checkExported();
    }
  }

  void _checkExported() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<DownloadProvider>().isExported(widget.track);
      }
    });
  }

  void _onTap() {
    final downloadProvider = context.read<DownloadProvider>();
    if (downloadProvider.exportedTrackIds.contains(widget.track.id)) {
      downloadProvider.unexportTrack(widget.track);
    } else {
      downloadProvider.exportTrack(widget.track);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloadProvider>(
      builder: (context, downloadProvider, _) {
        final isExported = downloadProvider.exportedTrackIds.contains(widget.track.id);
        final isExporting = downloadProvider.activeExports.containsKey(widget.track.id);

        if (isExported) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onTap,
            child: Icon(
              PhosphorIconsFill.thumbsUp,
              color: Colors.green,
              size: widget.size,
            ),
          );
        }

        if (isExporting) {
          return SizedBox(
            width: widget.size,
            height: widget.size,
            child: const CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
            ),
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTap,
          child: Icon(
            PhosphorIconsRegular.thumbsUp,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
            size: widget.size,
          ),
        );
      },
    );
  }
}
