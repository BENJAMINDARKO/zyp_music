import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import '../../presentation/providers/player_provider.dart';
import 'synced_lyrics_widget.dart';
import 'dart:ui';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class CustomLyricsModal extends StatefulWidget {
  final bool isFromMiniPlayer;

  const CustomLyricsModal({
    super.key,
    required this.isFromMiniPlayer,
  });

  @override
  State<CustomLyricsModal> createState() => _CustomLyricsModalState();
}

class _CustomLyricsModalState extends State<CustomLyricsModal> with SingleTickerProviderStateMixin {
  int _syncOffsetMs = 0;
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final player = context.read<PlayerProvider>();
      if (player.isActuallyPlaying) {
        _rotationController.repeat();
      }
    });
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

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
        if (provider.isActuallyPlaying && !_rotationController.isAnimating) {
          _rotationController.repeat();
        } else if (!provider.isActuallyPlaying && _rotationController.isAnimating) {
          _rotationController.stop();
        }

        final activeColor = provider.dominantColor ?? const Color(0xFFEAB308);
        final bgOpacity = widget.isFromMiniPlayer ? 0.95 : 0.85;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF141414).withOpacity(bgOpacity),
              borderRadius: widget.isFromMiniPlayer
                  ? BorderRadius.zero
                  : const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _buildHeader(context, provider),
                  _buildLyricsBody(provider, activeColor),
                  _buildBottomPlayer(provider, activeColor),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, PlayerProvider provider) {
    if (widget.isFromMiniPlayer) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          children: [
            const Text(
              'Lyrics',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.remove, color: Colors.white70),
              onPressed: () => setState(() => _syncOffsetMs -= 500),
            ),
            Text(
              '${_syncOffsetMs >= 0 ? '+' : ''}${(_syncOffsetMs / 1000).toStringAsFixed(1)}s',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            IconButton(
              icon: const Icon(Icons.add, color: Colors.white70),
              onPressed: () => setState(() => _syncOffsetMs += 500),
            ),
            IconButton(
              icon: const Icon(Icons.sync, color: Colors.white70),
              onPressed: () => setState(() => _syncOffsetMs = 0),
            ),
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.white70),
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    } else {
      return Column(
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              children: [
                RotationTransition(
                  turns: _rotationController,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      image: (provider.currentTrack?.thumbnailUrl?.isNotEmpty ?? false)
                          ? DecorationImage(
                              image: NetworkImage(provider.currentTrack!.thumbnailUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                      color: (provider.currentTrack?.thumbnailUrl?.isNotEmpty ?? false) ? null : Colors.grey[800],
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
                        provider.currentTrack?.title ?? 'Unknown',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        provider.currentTrack?.author ?? 'Unknown',
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.download_outlined, color: Colors.white70),
                  onPressed: () {
                    if (provider.lyrics != null && provider.currentTrack != null) {
                      _downloadLyrics(context, provider.lyrics!, provider.currentTrack!.title);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      );
    }
  }

  Widget _buildLyricsBody(PlayerProvider provider, Color activeColor) {
    return Expanded(
      child: provider.isLoadingLyrics
          ? Center(child: CircularProgressIndicator(color: activeColor))
          : provider.lyrics != null
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
                    lyricsText: provider.lyrics!,
                    position: Duration(milliseconds: provider.position.inMilliseconds + _syncOffsetMs),
                    activeColor: activeColor,
                  ),
                )
              : const Center(
                  child: Text(
                    'No lyrics available',
                    style: TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                ),
    );
  }

  Widget _buildBottomPlayer(PlayerProvider provider, Color activeColor) {
    if (widget.isFromMiniPlayer) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: (provider.currentTrack?.thumbnailUrl?.isNotEmpty ?? false)
                      ? Image.network(
                          provider.currentTrack!.thumbnailUrl!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 48,
                            height: 48,
                            color: Colors.white10,
                            child: const Icon(Icons.music_note, color: Colors.white54),
                          ),
                        )
                      : Container(
                          width: 48,
                          height: 48,
                          color: Colors.white10,
                          child: const Icon(Icons.music_note, color: Colors.white54),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.currentTrack?.title ?? 'Unknown',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${provider.currentTrack?.author ?? 'Unknown'} • ${provider.currentTrack?.year ?? ''}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(icon: const Icon(Icons.favorite_border, color: Colors.white70), onPressed: () {}),
                IconButton(icon: const Icon(Icons.mic_external_on, color: Colors.white70), onPressed: () {}),
                IconButton(icon: const Icon(Icons.playlist_add, color: Colors.white70), onPressed: () {}),
                IconButton(icon: const Icon(Icons.timer_outlined, color: Colors.white70), onPressed: () {}),
                IconButton(icon: const Icon(Icons.queue_music, color: Colors.white70), onPressed: () {}),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  _formatDuration(provider.position),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ProgressBar(
                    progress: provider.position,
                    buffered: provider.bufferedPosition,
                    total: provider.duration,
                    onSeek: provider.seekTo,
                    barHeight: 4,
                    baseBarColor: Colors.white24,
                    bufferedBarColor: Colors.white38,
                    progressBarColor: activeColor,
                    thumbColor: activeColor,
                    thumbRadius: 6,
                    timeLabelLocation: TimeLabelLocation.none,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDuration(provider.duration),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.shuffle, color: Colors.white70),
                  onPressed: provider.toggleShuffle,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_previous, color: Colors.white, size: 32),
                  onPressed: provider.previous,
                ),
                GestureDetector(
                  onTap: provider.togglePlayPause,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: activeColor,
                      shape: BoxShape.circle,
                    ),
                    child: provider.isBuffering
                        ? SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              color: activeColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                        : Icon(
                            provider.isActuallyPlaying ? Icons.pause : Icons.play_arrow,
                            color: activeColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                            size: 32,
                          ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next, color: Colors.white, size: 32),
                  onPressed: provider.next,
                ),
                IconButton(
                  icon: const Icon(Icons.repeat, color: Colors.white70),
                  onPressed: provider.cycleRepeatMode,
                ),
                IconButton(
                  icon: const Icon(Icons.cast, color: Colors.white70),
                  onPressed: () {},
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  _formatDuration(provider.position),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ProgressBar(
                    progress: provider.position,
                    buffered: provider.bufferedPosition,
                    total: provider.duration,
                    onSeek: provider.seekTo,
                    barHeight: 4,
                    baseBarColor: Colors.white24,
                    bufferedBarColor: Colors.white38,
                    progressBarColor: activeColor,
                    thumbColor: activeColor,
                    thumbRadius: 6,
                    timeLabelLocation: TimeLabelLocation.none,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDuration(provider.duration),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.shuffle, color: Colors.white70),
                  onPressed: provider.toggleShuffle,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_previous, color: Colors.white, size: 32),
                  onPressed: provider.previous,
                ),
                GestureDetector(
                  onTap: provider.togglePlayPause,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: provider.isBuffering
                        ? const SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3),
                          )
                        : Icon(
                            provider.isActuallyPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.black,
                            size: 32,
                          ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next, color: Colors.white, size: 32),
                  onPressed: provider.next,
                ),
                IconButton(
                  icon: const Icon(Icons.repeat, color: Colors.white70),
                  onPressed: provider.cycleRepeatMode,
                ),
              ],
            ),
          ],
        ),
      );
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '${d.inMinutes}:$seconds';
  }
}
