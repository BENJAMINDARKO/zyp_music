import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import '../../presentation/providers/player_provider.dart';
import 'synced_lyrics_widget.dart';
import 'miniplayer_flyout_container.dart';

class MiniplayerLyricsView extends StatefulWidget {
  const MiniplayerLyricsView({super.key});

  @override
  State<MiniplayerLyricsView> createState() => _MiniplayerLyricsViewState();
}

class _MiniplayerLyricsViewState extends State<MiniplayerLyricsView> {
  int _syncOffsetMs = 0;

  void _downloadLyrics(BuildContext context, String lyrics, String title) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$title-lyrics.lrc');
      await file.writeAsString(lyrics);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lyrics saved to ${file.path}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save lyrics')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, provider, child) {
        final activeColor = provider.dominantColor ?? const Color(0xFFEAB308);
        final track = provider.currentTrack;

        return MiniplayerFlyoutContainer(
          thumbnailUrl: track?.thumbnailUrl,
          child: SafeArea(
            child: Column(
              children: [
                // Header Toolbar (Primary Actions)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    children: [
                      const Text(
                        'Lyrics',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white70),
                        onPressed: () async {
                          await provider.refreshLyrics();
                        },
                        tooltip: 'Refresh Lyrics',
                      ),
                      IconButton(
                        icon: const Icon(Icons.download_outlined, color: Colors.white70),
                        onPressed: () {
                          if (provider.lyrics != null && track != null) {
                            _downloadLyrics(context, provider.lyrics!, track.title);
                          }
                        },
                        tooltip: 'Download Lyrics',
                      ),
                      IconButton(
                        icon: Icon(
                          provider.autoScroll ? Icons.pause_circle_outline : Icons.play_circle_outline,
                          color: Colors.white70,
                        ),
                        onPressed: () => provider.setAutoScroll(!provider.autoScroll),
                        tooltip: 'Toggle Auto-Scroll',
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.mic_external_on,
                          color: provider.isKaraokeMode ? activeColor : Colors.white70,
                        ),
                        onPressed: () => provider.setKaraokeMode(!provider.isKaraokeMode),
                        tooltip: 'Karaoke Mode',
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // Sync Offset Sub-row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  margin: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 8.0),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Sync Offset:',
                        style: TextStyle(color: Colors.white60, fontSize: 13),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.remove, color: Colors.white70, size: 18),
                        onPressed: () => setState(() => _syncOffsetMs -= 500),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(6),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_syncOffsetMs >= 0 ? '+' : ''}${(_syncOffsetMs / 1000).toStringAsFixed(1)}s',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.add, color: Colors.white70, size: 18),
                        onPressed: () => setState(() => _syncOffsetMs += 500),
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(6),
                      ),
                      const SizedBox(width: 16),
                      TextButton(
                        onPressed: () => setState(() => _syncOffsetMs = 0),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Reset', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: provider.isLoadingLyrics || provider.lyrics != null
                      ? (provider.isKaraokeMode
                          ? SyncedLyricsWidget(
                              lyricsText: provider.lyrics ?? '',
                              isLoading: provider.isLoadingLyrics,
                              position: Duration(milliseconds: provider.position.inMilliseconds + _syncOffsetMs),
                              activeColor: activeColor,
                              karaokeMode: true,
                              autoScroll: provider.autoScroll,
                            )
                          : ShaderMask(
                              shaderCallback: (Rect bounds) {
                                return LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.white,
                                    Colors.white,
                                    Colors.white.withOpacity(0.05),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.0, 0.75, 0.95, 1.0],
                                ).createShader(bounds);
                              },
                              blendMode: BlendMode.dstIn,
                              child: SyncedLyricsWidget(
                                lyricsText: provider.lyrics ?? '',
                                isLoading: provider.isLoadingLyrics,
                                position: Duration(milliseconds: provider.position.inMilliseconds + _syncOffsetMs),
                                activeColor: activeColor,
                                karaokeMode: false,
                                autoScroll: provider.autoScroll,
                              ),
                            ))
                      : const Center(
                          child: Text(
                            'No lyrics available',
                            style: TextStyle(color: Colors.white54, fontSize: 16),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
