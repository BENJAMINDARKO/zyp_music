import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/repeat_mode.dart' as repeat;
import '../../core/utils/format_duration.dart';
import '../providers/player_provider.dart';
import '../providers/playlist_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/queue_sheet.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer3<PlayerProvider, SettingsProvider, PlaylistProvider>(
      builder: (context, player, settings, playlistProvider, _) {
        if (player.currentTrack == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Player')),
            body: const Center(child: Text('No track playing')),
          );
        }

        final track = player.currentTrack!;
        final progress = player.duration.inMilliseconds > 0
            ? player.position.inMilliseconds / player.duration.inMilliseconds
            : 0.0;
        final bufferProgress = player.duration.inMilliseconds > 0
            ? player.bufferedPosition.inMilliseconds /
                  player.duration.inMilliseconds
            : 0.0;
        final isFav = playlistProvider.isFavorite(track.id);

        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF5C3D48),
                  Color(0xFF1A1A1A),
                  Color(0xFF101010),
                ],
                stops: [0.0, 0.36, 1.0],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                child: Column(
                  children: [
                    _buildPlayerHeader(context, player),
                    const Spacer(),
                    _Artwork(imageUrl: track.thumbnailUrl),
                    const SizedBox(height: 32),
                    Row(
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
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                track.author ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            isFav
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: isFav
                                ? const Color(0xFFFF7FA4)
                                : Colors.white,
                          ),
                          tooltip: isFav
                              ? 'Remove from favorites'
                              : 'Add to favorites',
                          onPressed: () =>
                              playlistProvider.toggleFavorite(track),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Text(
                          formatDuration(player.position),
                          style: _timeStyle,
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapDown: (details) {
                                  if (player.duration.inMilliseconds <= 0) {
                                    return;
                                  }
                                  final value =
                                      (details.localPosition.dx /
                                              constraints.maxWidth)
                                          .clamp(0.0, 1.0);
                                  player.seekTo(
                                    Duration(
                                      milliseconds:
                                          (value *
                                                  player
                                                      .duration
                                                      .inMilliseconds)
                                              .round(),
                                    ),
                                  );
                                },
                                child: SizedBox(
                                  height: 58,
                                  child: CustomPaint(
                                    painter: _WaveformPainter(
                                      progress: progress.clamp(0.0, 1.0),
                                      bufferProgress: bufferProgress.clamp(
                                        0.0,
                                        1.0,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Text(
                          formatDuration(player.duration),
                          style: _timeStyle,
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _ControlButton(
                          icon: Icons.shuffle_rounded,
                          active: player.shuffleMode,
                          onPressed: player.toggleShuffle,
                        ),
                        _ControlButton(
                          icon: Icons.skip_previous_rounded,
                          onPressed: player.currentIndex > 0
                              ? () => player.previous()
                              : null,
                        ),
                        player.isLoading
                            ? const SizedBox(
                                width: 62,
                                height: 62,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : SizedBox(
                                width: 64,
                                height: 64,
                                child: IconButton(
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    shape: const CircleBorder(),
                                  ),
                                  icon: Icon(
                                    player.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 34,
                                  ),
                                  onPressed: player.togglePlayPause,
                                ),
                              ),
                        _ControlButton(
                          icon: Icons.skip_next_rounded,
                          onPressed:
                              player.currentIndex + 1 < player.queue.length
                              ? () => player.next()
                              : null,
                        ),
                        _ControlButton(
                          icon: _repeatIconData(player.repeatMode),
                          active:
                              player.repeatMode !=
                              repeat.PlaybackRepeatMode.none,
                          onPressed: player.cycleRepeatMode,
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    _buildLyricsButton(),
                    if (player.error != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        player.error!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static const _timeStyle = TextStyle(
    color: Colors.white70,
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );

  Widget _buildPlayerHeader(BuildContext context, PlayerProvider player) {
    return Row(
      children: [
        _HeaderButton(
          icon: Icons.arrow_back_ios_new_rounded,
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
        ),
        const Expanded(
          child: Text(
            'Now Playing',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
        ),
        PopupMenuButton<String>(
          color: const Color(0xFF242424),
          icon: const Icon(Icons.more_horiz_rounded),
          tooltip: 'More',
          onSelected: (value) {
            if (value == 'queue') {
              _showQueueSheet(context);
            } else if (value == 'timer') {
              if (player.isSleepTimerActive) {
                player.cancelSleepTimer();
              } else {
                _showSleepTimerDialog(context, player);
              }
            } else if (value == 'clear') {
              _showClearQueueDialog(context, player);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'queue',
              child: Text('Queue (${player.queue.length})'),
            ),
            PopupMenuItem(
              value: 'timer',
              child: Text(
                player.isSleepTimerActive
                    ? 'Cancel timer ${formatDuration(player.sleepTimerRemaining ?? Duration.zero)}'
                    : 'Sleep timer',
              ),
            ),
            if (player.queue.isNotEmpty)
              const PopupMenuItem(value: 'clear', child: Text('Clear queue')),
          ],
        ),
      ],
    );
  }

  Widget _buildLyricsButton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(24),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Lyrics',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down_rounded, size: 16),
        ],
      ),
    );
  }

  void _showClearQueueDialog(BuildContext context, PlayerProvider player) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear queue?'),
        content: Text(
          '${player.queue.length} tracks in queue will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              player.clearQueue();
              Navigator.pop(ctx);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showQueueSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (_) => const QueueSheet(),
    );
  }

  void _showSleepTimerDialog(BuildContext context, PlayerProvider player) {
    final options = [15, 30, 60];
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Sleep Timer',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            if (player.isSleepTimerActive)
              ListTile(
                leading: const Icon(Icons.timer_off, color: Colors.red),
                title: const Text('Turn off timer'),
                onTap: () {
                  player.cancelSleepTimer();
                  Navigator.pop(ctx);
                },
              ),
            ...options.map(
              (minutes) => ListTile(
                leading: const Icon(Icons.timer),
                title: Text(
                  minutes >= 60
                      ? '${minutes ~/ 60}h ${minutes % 60}m'
                      : '${minutes}m',
                ),
                onTap: () {
                  player.startSleepTimer(Duration(minutes: minutes));
                  Navigator.pop(ctx);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Custom...'),
              onTap: () {
                Navigator.pop(ctx);
                _showCustomSleepTimer(context, player);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showCustomSleepTimer(BuildContext context, PlayerProvider player) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom sleep timer'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Minutes'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final minutes = int.tryParse(controller.text);
              if (minutes != null && minutes > 0) {
                player.startSleepTimer(Duration(minutes: minutes));
              }
              Navigator.pop(ctx);
            },
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }

  IconData _repeatIconData(repeat.PlaybackRepeatMode mode) {
    switch (mode) {
      case repeat.PlaybackRepeatMode.none:
      case repeat.PlaybackRepeatMode.all:
        return Icons.repeat_rounded;
      case repeat.PlaybackRepeatMode.one:
        return Icons.repeat_one_rounded;
    }
  }
}

class _Artwork extends StatelessWidget {
  final String? imageUrl;

  const _Artwork({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context).width.clamp(220.0, 280.0);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(120),
            blurRadius: 34,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: CachedNetworkImage(
          imageUrl: imageUrl ?? '',
          fit: BoxFit.cover,
          placeholder: (context, url) =>
              Container(color: const Color(0xFF282828)),
          errorWidget: (context, url, error) => Container(
            color: const Color(0xFF282828),
            child: const Icon(
              Icons.music_video_rounded,
              size: 68,
              color: Colors.white38,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 38,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: tooltip,
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withAlpha(55),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: Icon(icon, size: 18),
        onPressed: onPressed,
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback? onPressed;

  const _ControlButton({
    required this.icon,
    this.active = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 24),
      color: active ? Theme.of(context).colorScheme.primary : Colors.white,
      disabledColor: Colors.white24,
      onPressed: onPressed,
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final double bufferProgress;

  const _WaveformPainter({
    required this.progress,
    required this.bufferProgress,
  });

  static const _bars = [
    0.28,
    0.48,
    0.38,
    0.62,
    0.42,
    0.72,
    0.34,
    0.58,
    0.46,
    0.84,
    0.36,
    0.52,
    0.44,
    0.68,
    0.92,
    0.4,
    0.56,
    0.32,
    0.74,
    0.5,
    0.38,
    0.64,
    0.46,
    0.3,
    0.52,
    0.42,
    0.6,
    0.34,
    0.48,
    0.28,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final activePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final inactivePaint = Paint()
      ..color = Colors.white.withAlpha(36)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final bufferedPaint = Paint()
      ..color = Colors.white.withAlpha(92)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    final step = size.width / _bars.length;
    final activeWidth = size.width * progress;
    final bufferWidth = size.width * bufferProgress;
    for (var i = 0; i < _bars.length; i++) {
      final x = step * i + step / 2;
      final barHeight = size.height * _bars[i];
      final paint = x <= activeWidth
          ? activePaint
          : x <= bufferWidth
          ? bufferedPaint
          : inactivePaint;
      canvas.drawLine(
        Offset(x, (size.height - barHeight) / 2),
        Offset(x, (size.height + barHeight) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.bufferProgress != bufferProgress;
  }
}
