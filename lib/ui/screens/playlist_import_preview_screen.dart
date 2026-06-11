import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../domain/entities/video.dart';

class PlaylistImportPreviewScreen extends StatefulWidget {
  final String sourceUrl;
  final String playlistName;
  final List<Map<String, dynamic>> scrapedTracks;

  const PlaylistImportPreviewScreen({
    super.key,
    required this.sourceUrl,
    required this.playlistName,
    required this.scrapedTracks,
  });

  @override
  State<PlaylistImportPreviewScreen> createState() => _PlaylistImportPreviewScreenState();
}

class _PlaylistImportPreviewScreenState extends State<PlaylistImportPreviewScreen> {
  final Set<int> _selectedIndices = {};
  bool _isImporting = false;
  int _importProgress = 0;

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < widget.scrapedTracks.length; i++) {
      _selectedIndices.add(i);
    }
  }

  Future<void> _startImport() async {
    setState(() {
      _isImporting = true;
      _importProgress = 0;
    });

    final playlistProvider = context.read<PlaylistProvider>();
    final targetPlaylist = await playlistProvider.createPlaylist(widget.playlistName);

    final selectedTracks = _selectedIndices.map((i) => widget.scrapedTracks[i]).toList();

    final tracksToAdd = <Track>[];
    for (int i = 0; i < selectedTracks.length; i++) {
      final t = selectedTracks[i];
      
      setState(() {
        _importProgress = i + 1;
      });

      tracksToAdd.add(Track(
        id: t['id'] ?? 'importstub_${t['title'].hashCode}_${t['artist'].hashCode}',
        title: t['title'] ?? 'Unknown',
        author: t['artist'] ?? 'Unknown',
        thumbnailUrl: t['albumArt']?.isNotEmpty == true ? t['albumArt'] : null,
        duration: const Duration(seconds: 0),
        source: TrackSource.youtube,
      ));
    }

    await playlistProvider.addTracksToPlaylist(targetPlaylist.id, tracksToAdd);

    // Run background resolution of YouTube Music tracks so the UI matches faster
    playlistProvider.resolveImportStubs(targetPlaylist.id);

    setState(() {
      _isImporting = false;
      _importProgress = selectedTracks.length;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${selectedTracks.length} tracks to ${widget.playlistName}!')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Import Preview'),
        backgroundColor: Colors.transparent,
        actions: [
          if (!_isImporting)
            TextButton(
              onPressed: _selectedIndices.isEmpty ? null : _startImport,
              child: const Text('Import', style: TextStyle(color: Color(0xFFEAB308), fontWeight: FontWeight.bold)),
            )
        ],
      ),
      body: _isImporting
          ? _buildImportingState()
          : _buildPreviewList(),
    );
  }

  Widget _buildImportingState() {
    final total = _selectedIndices.length;
    final progress = total == 0 ? 0.0 : _importProgress / total;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFFEAB308)),
            const SizedBox(height: 32),
            Text(
              'Importing $_importProgress / $total',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFEAB308)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewList() {
    return ListView.builder(
      itemCount: widget.scrapedTracks.length,
      itemBuilder: (context, index) {
        final track = widget.scrapedTracks[index];
        final isSelected = _selectedIndices.contains(index);

        return ListTile(
          leading: Checkbox(
            value: isSelected,
            activeColor: const Color(0xFFEAB308),
            onChanged: (val) {
              setState(() {
                if (val == true) {
                  _selectedIndices.add(index);
                } else {
                  _selectedIndices.remove(index);
                }
              });
            },
          ),
          title: Text(track['title'] ?? 'Unknown', style: const TextStyle(color: Colors.white), maxLines: 1),
          subtitle: Text(track['artist'] ?? 'Unknown', style: const TextStyle(color: Colors.white54), maxLines: 1),
          trailing: track['albumArt']?.isNotEmpty == true
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: track['albumArt']!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                )
              : const SizedBox(width: 48, height: 48, child: Icon(PhosphorIconsRegular.musicNote, color: Colors.white24)),
        );
      },
    );
  }
}
