import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../presentation/providers/miniplayer_visibility_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../core/constants/repeat_mode.dart' as repeat;
import '../widgets/playlist_picker_dialog.dart';
import '../widgets/synced_lyrics_widget.dart';
import '../widgets/audio_visualizer.dart';
import '../widgets/custom_lyrics_modal.dart';
import '../../presentation/providers/settings_provider.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/custom_audio_seekbar.dart';
import 'artist_screen.dart';
import 'album_screen.dart';

class PlayingScreen extends StatefulWidget {
  const PlayingScreen({super.key});

  @override
  State<PlayingScreen> createState() => _PlayingScreenState();
}

class _PlayingScreenState extends State<PlayingScreen> with TickerProviderStateMixin {
  late AnimationController _rotationController;
  bool _wasPlaying = false;
  bool _isLyricsMode = false;
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
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) context.read<MiniplayerVisibilityProvider>().hide();
    });
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );

    // Sync rotation with play state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final player = context.read<PlayerProvider>();
      _wasPlaying = player.isActuallyPlaying;
      if (player.isActuallyPlaying) {
        _rotationController.repeat();
      }
    });
  }

  @override
  void dispose() {
    Future.microtask(() {
      if (mounted) context.read<MiniplayerVisibilityProvider>().show();
    });
    _rotationController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '${duration.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, player, _) {
        final track = player.currentTrack;
        if (track == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF0A0A0A),
            body: Center(child: Text('No track playing', style: TextStyle(color: Colors.white))),
          );
        }

        // Sync rotation animation with play state
        if (player.isActuallyPlaying && !_wasPlaying) {
          _rotationController.repeat();
        } else if (!player.isActuallyPlaying && _wasPlaying) {
          _rotationController.stop();
        }
        _wasPlaying = player.isActuallyPlaying;

        final progress = player.duration.inMilliseconds > 0
            ? player.position.inMilliseconds / player.duration.inMilliseconds
            : 0.0;
        final bufferProgress = player.duration.inMilliseconds > 0
            ? player.bufferedPosition.inMilliseconds / player.duration.inMilliseconds
            : 0.0;
            
        final activeColor = player.dominantColor ?? Colors.white;
        final settings = context.watch<SettingsProvider>();
        final seekbarColor = settings.invertSeekbarColor 
            ? (activeColor.computeLuminance() > 0.5 ? Colors.black : Colors.white)
            : activeColor;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              SafeArea(
                child: Column(
                  children: [
                    // Top bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 30),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Expanded(
                            child: Text(
                              'Now Playing',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 0.5),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.more_vert, color: Colors.white),
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ),

                    if (_isLyricsMode) ...[
                      // Compact Header for Lyrics Mode
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                        child: Row(
                          children: [
                            RotationTransition(
                              turns: _rotationController,
                              child: Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  image: (track.thumbnailUrl?.isNotEmpty ?? false)
                                      ? DecorationImage(
                                          image: NetworkImage(track.thumbnailUrl!),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                  color: (track.thumbnailUrl?.isNotEmpty ?? false) ? null : Colors.grey[800],
                                ),
                                child: Center(
                                  child: Container(
                                    width: 15,
                                    height: 15,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFF141414),
                                      border: Border.all(color: Colors.white24, width: 1),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    track.author ?? 'Unknown',
                                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      // Lyrics Utility Toolbar
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                        child: Row(
                          children: [
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white24),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Text('Auto v', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.remove, color: Colors.white70, size: 20),
                              onPressed: () => setState(() => _syncOffsetMs -= 500),
                            ),
                            Text(
                              '${_syncOffsetMs >= 0 ? '+' : ''}${(_syncOffsetMs / 1000).toStringAsFixed(1)}s',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add, color: Colors.white70, size: 20),
                              onPressed: () => setState(() => _syncOffsetMs += 500),
                            ),
                            IconButton(
                              icon: const Icon(Icons.sync, color: Colors.white70, size: 20),
                              onPressed: () => setState(() => _syncOffsetMs = 0),
                            ),
                            IconButton(
                              icon: const Icon(Icons.download_outlined, color: Colors.white70, size: 20),
                              onPressed: () {
                                if (player.lyrics != null) {
                                  _downloadLyrics(context, player.lyrics!, track.title);
                                }
                              },
                            ),
                          ],
                        ),
                      ),

                      // Lyrics Body
                      Expanded(
                        child: player.isLoadingLyrics
                            ? Center(child: CircularProgressIndicator(color: activeColor))
                            : player.lyrics != null
                                ? ShaderMask(
                                    shaderCallback: (Rect bounds) {
                                      return LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.transparent,
                                          Colors.white.withOpacity(0.05),
                                          Colors.white,
                                          Colors.white,
                                          Colors.white.withOpacity(0.05),
                                          Colors.transparent,
                                        ],
                                        stops: const [0.0, 0.1, 0.4, 0.6, 0.9, 1.0],
                                      ).createShader(bounds);
                                    },
                                    blendMode: BlendMode.dstIn,
                                    child: SyncedLyricsWidget(
                                      lyricsText: player.lyrics!,
                                      position: Duration(milliseconds: player.position.inMilliseconds + _syncOffsetMs),
                                      activeColor: activeColor,
                                    ),
                                  )
                                : const Center(
                                    child: Text(
                                      'No lyrics available',
                                      style: TextStyle(color: Colors.white54, fontSize: 16),
                                    ),
                                  ),
                      ),
                    ] else ...[
                      const Spacer(flex: 1),

                      // Rotating disc album art
                      RotationTransition(
                        turns: _rotationController,
                        child: Container(
                          width: MediaQuery.of(context).size.width * 0.72,
                          height: MediaQuery.of(context).size.width * 0.72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.6),
                                blurRadius: 30,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                (track.thumbnailUrl?.isNotEmpty ?? false)
                                    ? CachedNetworkImage(
                                        imageUrl: track.thumbnailUrl!,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        height: double.infinity,
                                        errorWidget: (_, __, ___) => Container(
                                          color: Colors.grey[850],
                                          child: const Icon(Icons.music_note, size: 80, color: Colors.white38),
                                        ),
                                      )
                                    : Container(
                                        color: Colors.grey[850],
                                        child: const Icon(Icons.music_note, size: 80, color: Colors.white38),
                                      ),
                                // Center hole
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black,
                                    border: Border.all(color: Colors.white24, width: 1),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),
                      
                      // Visualizer
                      SizedBox(
                        height: 40,
                        width: MediaQuery.of(context).size.width * 0.8,
                        child: AudioVisualizer(
                          style: settings.visualizerStyle,
                          color: activeColor,
                          isPlaying: player.isActuallyPlaying,
                        ),
                      ),

                      const Spacer(flex: 1),

                      // Track info + favorite
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  GestureDetector(
                                    onTap: () async {
                                      if (track.author != null) {
                                        final provider = context.read<PlaylistProvider>();
                                        final artist = await provider.findCorrectArtist(track.author!, track.album);
                                        if (artist != null && context.mounted) {
                                          Navigator.push(context, MaterialPageRoute(builder: (_) => ArtistScreen(artistId: artist.id)));
                                        }
                                      }
                                    },
                                    child: Text(
                                      track.author ?? 'Unknown Artist',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white70, fontSize: 15, decoration: TextDecoration.underline),
                                    ),
                                  ),
                                  if (track.album != null) ...[
                                    const SizedBox(height: 2),
                                    GestureDetector(
                                      onTap: () async {
                                        final provider = context.read<PlaylistProvider>();
                                        final res = await provider.searchAlbums(track.album!);
                                        if (res.isNotEmpty && context.mounted) {
                                          Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumScreen(albumId: res.first.id)));
                                        }
                                      },
                                      child: Text(
                                        track.album!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white38, fontSize: 13, decoration: TextDecoration.underline),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Consumer<PlaylistProvider>(
                              builder: (context, pp, _) {
                                final isFav = pp.isFavorite(track.id);
                                return IconButton(
                                  icon: Icon(
                                    isFav ? Icons.favorite : Icons.favorite_border,
                                    color: isFav ? Colors.red : Colors.white54,
                                    size: 26,
                                  ),
                                  onPressed: () => pp.toggleFavorite(track),
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),
                    ],

                    // Seek bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          Consumer<SettingsProvider>(
                            builder: (context, settings, _) {
                              SeekbarStyle style = SeekbarStyle.minimal;
                              switch (settings.seekbarStyle) {
                                case 'Gradient': style = SeekbarStyle.gradient; break;
                                case 'Waveform': style = SeekbarStyle.waveform; break;
                                case 'Minimal': style = SeekbarStyle.minimal; break;
                                case 'Wavy': style = SeekbarStyle.wavy; break;
                                case 'Segmented': style = SeekbarStyle.segmented; break;
                              }
                              return CustomAudioSeekbar(
                                value: progress.clamp(0.0, 1.0),
                                secondaryValue: bufferProgress.clamp(0.0, 1.0),
                                activeColor: seekbarColor,
                                style: style,
                                invertColor: settings.invertSeekbarColor,
                                onChanged: (v) {
                                  final pos = Duration(milliseconds: (v * player.duration.inMilliseconds).round());
                                  player.seekTo(pos);
                                },
                              );
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatDuration(player.position),
                                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                Text(_formatDuration(player.duration),
                                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Playback controls
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: Icon(Icons.shuffle,
                                size: 28,
                                color: player.shuffleMode ? activeColor : Colors.white54,
                              ),
                              onPressed: player.toggleShuffle,
                            ),
                            IconButton(
                              icon: const Icon(Icons.skip_previous, size: 40, color: Colors.white),
                              onPressed: player.currentIndex > 0 ? () => player.previous() : null,
                            ),
                          // Play/Pause circle
                          GestureDetector(
                            onTap: player.togglePlayPause,
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: activeColor,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: activeColor.withOpacity(0.3),
                                    blurRadius: 15,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: player.isBuffering
                                  ? Center(
                                      child: SizedBox(
                                        width: 32,
                                        height: 32,
                                        child: CircularProgressIndicator(color: activeColor.computeLuminance() > 0.5 ? Colors.black : Colors.white, strokeWidth: 3),
                                      ),
                                    )
                                  : Icon(
                                      player.isActuallyPlaying ? Icons.pause : Icons.play_arrow,
                                      color: activeColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                                      size: 40,
                                    ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next, size: 40, color: Colors.white),
                            onPressed: player.currentIndex + 1 < player.queue.length
                                ? () => player.next()
                                : null,
                          ),
                          IconButton(
                            icon: Icon(
                              player.repeatMode == repeat.PlaybackRepeatMode.one
                                  ? Icons.repeat_one
                                  : Icons.repeat,
                              size: 28,
                              color: player.repeatMode != repeat.PlaybackRepeatMode.none
                                  ? activeColor
                                  : Colors.white54,
                            ),
                            onPressed: player.cycleRepeatMode,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Bottom action row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: Icon(Icons.mic_none, color: _isLyricsMode ? activeColor : Colors.white54, size: 22),
                            onPressed: () => setState(() => _isLyricsMode = !_isLyricsMode),
                          ),
                          IconButton(
                            icon: const Icon(Icons.playlist_add, color: Colors.white54, size: 22),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => PlaylistPickerDialog(track: track),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.queue_music, color: Colors.white54, size: 22),
                            onPressed: () => _showUpNextModal(context, player),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showUpNextModal(BuildContext context, PlayerProvider player) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (context, scrollController) {
            return Consumer<PlayerProvider>(
              builder: (context, provider, child) {
                final queue = provider.queue;
                final currentIndex = provider.currentIndex;
                
                return Column(
                  children: [
                    const SizedBox(height: 16),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Up Next', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: queue.length,
                        itemBuilder: (context, index) {
                          final t = queue[index];
                          final isPlaying = index == currentIndex;
                          return ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: (t.thumbnailUrl?.isNotEmpty ?? false)
                                  ? CachedNetworkImage(
                                      imageUrl: t.thumbnailUrl!,
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) => Container(color: Colors.grey[800]),
                                    )
                                  : Container(width: 48, height: 48, color: Colors.grey[800]),
                            ),
                            title: Text(
                              t.title,
                              style: TextStyle(
                                color: isPlaying ? const Color(0xFFEAB308) : Colors.white,
                                fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              t.author ?? 'Unknown',
                              style: const TextStyle(color: Colors.white54),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white54),
                              onPressed: () {
                                provider.removeFromQueue(index);
                              },
                            ),
                            onTap: () {
                              provider.playFromQueue(index);
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _showLyricsModal(BuildContext context, PlayerProvider player) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: const CustomLyricsModal(isFromMiniPlayer: false),
        );
      },
    );
  }
}
