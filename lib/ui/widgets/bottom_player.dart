import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mini_music_visualizer/mini_music_visualizer.dart';
import '../../domain/entities/video.dart';
import '../../presentation/providers/player_provider.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/download_provider.dart';
import '../screens/playing_screen.dart';
import '../screens/artist_screen.dart';
import '../screens/album_screen.dart';
import 'playlist_picker_dialog.dart';
import '../../core/constants/repeat_mode.dart' as repeat;
import '../../presentation/providers/settings_provider.dart';
import 'custom_audio_seekbar.dart';
import '../widgets/miniplayer_timer_view.dart';
import '../widgets/miniplayer_queue_view.dart';
import '../widgets/miniplayer_lyrics_view.dart';
import '../../core/navigation/navigator_key.dart';

class BottomPlayer extends StatelessWidget {
  const BottomPlayer({super.key});

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${duration.inHours}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  Widget _buildSubtitleRow(BuildContext context, dynamic track) {
    final parts = <Widget>[];

    void navigateToArtist(String name, String? album) async {
      final provider = context.read<PlaylistProvider>();
      final artist = await provider.findCorrectArtist(name, album);
      if (artist != null && navigatorKey.currentState != null) {
        navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => ArtistScreen(artistId: artist.id)));
      }
    }

    void navigateToAlbum(String name) async {
      final provider = context.read<PlaylistProvider>();
      final res = await provider.searchAlbums(name);
      if (res.isNotEmpty && navigatorKey.currentState != null) {
        navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => AlbumScreen(albumId: res.first.id)));
      }
    }

    if (track.author != null && track.author!.isNotEmpty) {
      parts.add(GestureDetector(
        onTap: () => navigateToArtist(track.author!, track.album),
        child: Text(track.author!, style: const TextStyle(color: Colors.white54, fontSize: 11, decoration: TextDecoration.underline)),
      ));
    }
    
    if (track.album != null && track.album!.isNotEmpty) {
      if (parts.isNotEmpty) {
        parts.add(const Text(' • ', style: TextStyle(color: Colors.white54, fontSize: 11)));
      }
      parts.add(GestureDetector(
        onTap: () => navigateToAlbum(track.album!),
        child: Text(track.album!, style: const TextStyle(color: Colors.white54, fontSize: 11, decoration: TextDecoration.underline)),
      ));
    }

    if (track.year != null) {
      if (parts.isNotEmpty) {
        parts.add(const Text(' • ', style: TextStyle(color: Colors.white54, fontSize: 11)));
      }
      parts.add(Text(track.year.toString(), style: const TextStyle(color: Colors.white54, fontSize: 11)));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: parts,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, player, _) {
        final isEmptyState = player.currentTrack == null;
        final track = player.currentTrack ?? const Track(
          id: 'empty',
          title: 'Not Playing',
          author: 'Select a track to start listening',
          duration: Duration.zero,
          source: TrackSource.youtube,
        );

        final progress = !isEmptyState && player.duration.inMilliseconds > 0
            ? player.position.inMilliseconds / player.duration.inMilliseconds
            : 0.0;
        final bufferProgress = !isEmptyState && player.duration.inMilliseconds > 0
            ? player.bufferedPosition.inMilliseconds / player.duration.inMilliseconds
            : 0.0;
        
        final activeColor = !isEmptyState ? (player.dominantColor ?? const Color(0xFFEAB308)) : Colors.grey;
            
        final isDesktop = MediaQuery.of(context).size.width >= 800;

        Widget playerWidget;
        if (isDesktop) {
          playerWidget = _buildDesktopPlayer(context, player, track, progress, bufferProgress, activeColor, isEmptyState);
        } else {
          playerWidget = _buildMobilePlayer(context, player, track, progress, bufferProgress, activeColor, isEmptyState);
        }

        if (player.error != null) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 40,
                color: Colors.red.shade900,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        player.error!,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: player.clearError,
                    ),
                  ],
                ),
              ),
              playerWidget,
            ],
          );
        }

        return playerWidget;
      },
    );
  }

  Widget _buildDesktopPlayer(BuildContext context, PlayerProvider player, dynamic track, double progress, double bufferProgress, Color activeColor, bool isEmptyState) {
    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: const Color(0xFF141414).withAlpha(220),
        border: const Border(
          top: BorderSide(color: Color(0xFF2A2A2A), width: 1),
        ),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
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
                    activeColor: activeColor,
                    style: style,
                    invertColor: settings.invertSeekbarColor,
                    isPlaying: player.isActuallyPlaying,
                    onChanged: (v) {
                      final pos = Duration(milliseconds: (v * player.duration.inMilliseconds).round());
                      player.seekTo(pos);
                    },
                  );
                },
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: (track.thumbnailUrl?.isNotEmpty ?? false)
                            ? CachedNetworkImage(
                                imageUrl: track.thumbnailUrl!,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                errorWidget: (context, url, error) => Container(
                                  width: 56, height: 56, color: Colors.grey[800],
                                  child: const Icon(Icons.music_note),
                                ),
                              )
                            : Container(
                                width: 56, height: 56, color: Colors.grey[800],
                                child: const Icon(Icons.music_note),
                              ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              track.author ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        width: 30,
                        height: 20,
                        child: MiniMusicVisualizer(
                          color: Colors.white,
                          width: 4,
                          height: 15,
                          animate: player.isActuallyPlaying,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.skip_previous, color: Colors.white),
                            onPressed: !isEmptyState && player.currentIndex > 0 ? () => player.previous() : null,
                          ),
                          player.isBuffering
                            ? const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                ),
                              )
                            : IconButton(
                                icon: Icon(
                                  player.isActuallyPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                                  size: 48,
                                  color: isEmptyState ? Colors.white54 : Colors.white,
                                ),
                                onPressed: isEmptyState ? null : player.togglePlayPause,
                              ),
                          IconButton(
                            icon: const Icon(Icons.skip_next, color: Colors.white),
                            onPressed: !isEmptyState && player.currentIndex + 1 < player.queue.length
                                ? () => player.next()
                                : null,
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        "${_formatDuration(player.position)} / ${_formatDuration(player.duration)}",
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      const SizedBox(width: 16),
                      const Icon(Icons.volume_up, color: Colors.white54, size: 20),
                      SizedBox(
                        width: 100,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white24,
                          ),
                          child: Slider(
                            value: 1.0, 
                            onChanged: (v) {},
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobilePlayer(BuildContext context, PlayerProvider player, dynamic track, double progress, double bufferProgress, Color activeColor, bool isEmptyState) {
    return GestureDetector(
      onTap: () {
        if (!isEmptyState && navigatorKey.currentState != null) {
          navigatorKey.currentState!.push(
            MaterialPageRoute(builder: (_) => const PlayingScreen()),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF141414).withAlpha(240),
          border: const Border(
            top: BorderSide(color: Color(0xFF2A2A2A), width: 1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Row: Art, Titles, Icons
              Row(
                children: [
                  Hero(
                    tag: 'now-playing-art',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: (track.thumbnailUrl?.isNotEmpty ?? false)
                          ? CachedNetworkImage(
                              imageUrl: track.thumbnailUrl!,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) => Container(
                                width: 48, height: 48, color: Colors.grey[800],
                                child: const Icon(Icons.music_note),
                              ),
                            )
                          : Container(
                              width: 48, height: 48, color: Colors.grey[800],
                              child: const Icon(Icons.music_note),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        // Artist • Album • Year row (like Monochrome reference)
                        _buildSubtitleRow(context, track),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Consumer<PlaylistProvider>(
                        builder: (context, playlistProvider, child) {
                          final isFav = playlistProvider.isFavorite(track.id);
                          return IconButton(
                            icon: Icon(
                              isFav ? Icons.favorite : Icons.favorite_border,
                              color: isFav ? Colors.red : Colors.white54,
                              size: 24,
                            ),
                            onPressed: () {
                              playlistProvider.toggleFavorite(
                                track,
                                downloadProvider: context.read<DownloadProvider>(),
                              );
                            },
                          );
                        },
                      ),
                      // Auto DJ button — only present when the manual queue
                      // still has items remaining. Tapping instantly engages
                      // the hybrid AutoNext engine so the player keeps
                      // rolling recommendations (or shuffled offline cache)
                      // once the current track ends.
                      if (_hasManualQueueRemaining(player))
                        IconButton(
                          icon: Icon(
                            player.isAutoDJEnabled
                                ? Icons.auto_awesome
                                : Icons.auto_awesome_outlined,
                            color: player.isAutoDJEnabled
                                ? const Color(0xFFEAB308)
                                : Colors.white54,
                            size: 22,
                          ),
                          tooltip: player.isAutoDJEnabled
                              ? 'Auto DJ engaged — tap to disengage'
                              : 'Engage Auto DJ',
                          onPressed: () {
                            player.toggleAutoDJ();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  player.isAutoDJEnabled
                                      ? 'Auto DJ engaged'
                                      : 'Auto DJ disengaged',
                                ),
                              ),
                            );
                          },
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          constraints: const BoxConstraints(),
                        ),
                      IconButton(
                        icon: const Icon(Icons.mic_none, color: Colors.white54, size: 18),
                        onPressed: () {
                          _showLyricsModal(context, player);
                        },
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        constraints: const BoxConstraints(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.playlist_add, color: Colors.white54, size: 18),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => PlaylistPickerDialog(track: track),
                          );
                        },
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        constraints: const BoxConstraints(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.access_time, color: Colors.white54, size: 18),
                        onPressed: () => _showTimerFlyout(context),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        constraints: const BoxConstraints(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.format_list_bulleted, color: Colors.white54, size: 18),
                        onPressed: () => _showQueueFlyout(context),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Middle Row: Progress Slider
              Row(
                children: [
                  Text(_formatDuration(player.position), style: const TextStyle(color: Colors.white54, fontSize: 10)),
                  Expanded(
                    child: Consumer<SettingsProvider>(
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
                          activeColor: activeColor,
                          style: style,
                          invertColor: settings.invertSeekbarColor,
                          isPlaying: player.isActuallyPlaying,
                          onChanged: (v) {
                            final pos = Duration(milliseconds: (v * player.duration.inMilliseconds).round());
                            player.seekTo(pos);
                          },
                        );
                      },
                    ),
                  ),
                  Text(_formatDuration(player.duration), style: const TextStyle(color: Colors.white54, fontSize: 10)),
                ],
              ),
              const SizedBox(height: 8),

              // Bottom Row: Controls
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        icon: Icon(Icons.shuffle, color: player.shuffleMode ? Colors.white : Colors.white54),
                        onPressed: player.toggleShuffle,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.skip_previous, color: Colors.white),
                        onPressed: player.currentIndex > 0 ? () => player.previous() : null,
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: player.togglePlayPause,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: activeColor,
                            shape: BoxShape.circle,
                          ),
                          child: player.isBuffering
                              ? const Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                                  ),
                                )
                              : Icon(
                                  player.isActuallyPlaying ? Icons.pause : Icons.play_arrow,
                                  color: activeColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                                  size: 28,
                                ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.skip_next, color: Colors.white),
                        onPressed: player.currentIndex + 1 < player.queue.length
                            ? () => player.next()
                            : null,
                      ),
                    ],
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: Icon(
                            player.repeatMode == repeat.PlaybackRepeatMode.one 
                                ? Icons.repeat_one 
                                : Icons.repeat,
                            color: player.repeatMode != repeat.PlaybackRepeatMode.none ? Colors.white : Colors.white54,
                          ),
                          onPressed: player.cycleRepeatMode,
                        ),
                        IconButton(
                          icon: const Icon(Icons.cast, color: Colors.white54),
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  void _showFlyout(BuildContext context, Widget content) {
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final statusBarHeight = mediaQuery.padding.top;
    final appBarHeight = kToolbarHeight;
    final bottomPlayerHeight = 146.0 + mediaQuery.padding.bottom;
    final flyoutHeight = screenHeight - statusBarHeight - appBarHeight - bottomPlayerHeight;

    showBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SizedBox(
          height: flyoutHeight > 0 ? flyoutHeight : 450.0,
          child: content,
        );
      },
    );
  }

  void _showLyricsModal(BuildContext context, PlayerProvider player) {
    _showFlyout(context, const MiniplayerLyricsView());
  }

  void _showTimerFlyout(BuildContext context) {
    _showFlyout(context, const MiniplayerTimerView());
  }

  void _showQueueFlyout(BuildContext context) {
    _showFlyout(context, const MiniplayerQueueView());
  }

  /// True iff there is at least one track still queued after the current
  /// one. The Auto DJ button is hidden when the queue is empty (or the
  /// current track is the only entry) so it never appears in the "single
  /// play" state — explicit queue context is required.
  bool _hasManualQueueRemaining(PlayerProvider player) {
    if (player.currentTrack == null) return false;
    return player.currentIndex + 1 < player.queue.length;
  }

}
