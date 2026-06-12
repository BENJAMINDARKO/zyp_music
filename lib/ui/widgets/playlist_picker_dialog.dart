import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/video.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../domain/entities/playlist.dart';
import 'apple_music_sheet.dart';

class PlaylistPickerDialog extends StatefulWidget {
  final Track track;

  const PlaylistPickerDialog({super.key, required this.track});

  @override
  State<PlaylistPickerDialog> createState() => _PlaylistPickerDialogState();
  static Future<void> show(BuildContext context, Track track) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => PlaylistPickerDialog(track: track),
    );
  }
}

class _PlaylistPickerDialogState extends State<PlaylistPickerDialog> {
  final _newPlaylistController = TextEditingController();

  @override
  void dispose() {
    _newPlaylistController.dispose();
    super.dispose();
  }

  void _createNewPlaylist(BuildContext context) async {
    final title = _newPlaylistController.text.trim();
    if (title.isEmpty) return;

    try {
      final provider = context.read<PlaylistProvider>();
      final newPlaylist = await provider.createPlaylist(title);
      await provider.addTrackToPlaylist(newPlaylist.id, widget.track);

      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added to $title successfully')),
        );
      }
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    return AppleMusicSheet(
      title: 'Add to Playlist',
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Create New Playlist
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newPlaylistController,
                      decoration: InputDecoration(
                        hintText: 'New playlist name...',
                        hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.30)),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface),
                        ),
                      ),
                      onSubmitted: (_) => _createNewPlaylist(context),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(PhosphorIconsRegular.plusCircle, color: Colors.blueAccent),
                    onPressed: () => _createNewPlaylist(context),
                  )
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.24)),
              // Playlists List
              Flexible(
                child: Consumer<PlaylistProvider>(
                  builder: (context, provider, _) {
                    final playlists = provider.playlists.where((p) => p.id.startsWith('local_')).toList();

                    if (playlists.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24.0),
                        child: Text(
                          'No local playlists yet.',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54)),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: playlists.length,
                      itemBuilder: (context, index) {
                        final playlist = playlists[index];
                        final isLastAdded = provider.lastAddedPlaylistId == playlist.id;

                        return ListTile(
                          leading: Icon(PhosphorIconsRegular.queue, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.70)),
                          title: Text(
                            playlist.title,
                          ),
                          subtitle: isLastAdded
                              ? const Text('Last Added', style: TextStyle(color: Colors.blueAccent, fontSize: 12))
                              : Text('${playlist.videoCount} tracks', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 12)),
                          onTap: () async {
                            try {
                              await provider.addTrackToPlaylist(playlist.id, widget.track);
                              if (context.mounted) {
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Added to ${playlist.title} successfully')),
                                );
                              }
                            } catch (e) {}
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
