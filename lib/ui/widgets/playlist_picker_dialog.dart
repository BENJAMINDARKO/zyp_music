import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/video.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../domain/entities/playlist.dart';

class PlaylistPickerDialog extends StatefulWidget {
  final Track track;

  const PlaylistPickerDialog({super.key, required this.track});

  @override
  State<PlaylistPickerDialog> createState() => _PlaylistPickerDialogState();
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
    return Dialog(
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Add to Playlist',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // Create New Playlist
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newPlaylistController,
                    decoration: const InputDecoration(
                      hintText: 'New playlist name...',
                      hintStyle: TextStyle(color: Colors.white54),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white30),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: (_) => _createNewPlaylist(context),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.blueAccent),
                  onPressed: () => _createNewPlaylist(context),
                )
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
            // Playlists List
            Flexible(
              child: Consumer<PlaylistProvider>(
                builder: (context, provider, _) {
                  final playlists = provider.playlists.where((p) => p.id.startsWith('local_')).toList();
                  
                  if (playlists.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.0),
                      child: Text(
                        'No local playlists yet.',
                        style: TextStyle(color: Colors.white54),
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
                        leading: const Icon(Icons.queue_music, color: Colors.white70),
                        title: Text(
                          playlist.title,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: isLastAdded
                            ? const Text('Last Added', style: TextStyle(color: Colors.blueAccent, fontSize: 12))
                            : Text('${playlist.videoCount} tracks', style: const TextStyle(color: Colors.white54, fontSize: 12)),
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
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }
}
