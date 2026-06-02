import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/repeat_mode.dart' as repeat;
import '../../core/utils/format_duration.dart';
import '../../domain/entities/video.dart';
import '../../service/lyrics_service.dart';
import '../providers/download_provider.dart';
import '../providers/player_provider.dart';
import '../providers/playlist_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/queue_sheet.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  static final _lyricsService = LyricsService();

  @override
  Widget build(BuildContext context) {
    return Consumer4<
      PlayerProvider,
      SettingsProvider,
      PlaylistProvider,
      DownloadProvider
    >(
      builder:
          (context, player, settings, playlistProvider, downloadProvider, _) {
            if (player.currentTrack == null) {
              return Scaffold(
                appBar: AppBar(title: const Text('Player')),
                body: const Center(child: Text('No track playing')),
              );
            }

            final track = player.currentTrack!;
            final isFav = playlistProvider.isFavorite(track.id);

            return Scaffold(
              body: Stack(
                fit: StackFit.expand,
                children: [
                  _BlurredArtworkBackground(imageUrl: track.thumbnailUrl),
                  SafeArea(
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
                          _SeekWaveform(
                            position: player.position,
                            duration: player.duration,
                            bufferedPosition: player.bufferedPosition,
                            onSeek: player.seekTo,
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
                                onPressed: player.previous,
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
                                    player.currentIndex + 1 <
                                        player.queue.length
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
                          _buildLyricsButton(context, track),
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
                ],
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
        _HeaderButton(
          icon: Icons.more_horiz_rounded,
          tooltip: 'More',
          onPressed: () => _showMoreSheet(context, player),
        ),
      ],
    );
  }

  Widget _buildLyricsButton(BuildContext context, Track track) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.white.withAlpha(24),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      onPressed: () => _showLyricsSheet(context, track),
      icon: const Icon(Icons.lyrics_rounded, size: 16),
      label: const Text(
        'Lyrics',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }

  void _showMoreSheet(BuildContext context, PlayerProvider player) {
    final track = player.currentTrack;
    final downloadProvider = context.read<DownloadProvider>();
    final settings = context.read<SettingsProvider>();
    final isDownloaded =
        track != null && downloadProvider.downloadedTrackIds.contains(track.id);
    final isDownloading =
        track != null && downloadProvider.activeDownloads.containsKey(track.id);
    final items = [
      _MoreAction(
        icon: Icons.queue_music_rounded,
        title: 'Queue',
        subtitle: '${player.queue.length} tracks',
        onTap: () {
          Navigator.pop(context);
          _showQueueSheet(context);
        },
      ),
      if (track != null)
        _MoreAction(
          icon: isDownloaded
              ? Icons.offline_pin_rounded
              : isDownloading
              ? Icons.downloading_rounded
              : Icons.download_rounded,
          title: isDownloaded
              ? 'Downloaded'
              : isDownloading
              ? 'Downloading'
              : 'Download',
          subtitle: isDownloaded
              ? 'Available offline'
              : isDownloading
              ? 'Already in progress'
              : 'Cache this track',
          onTap: isDownloaded || isDownloading
              ? null
              : () {
                  Navigator.pop(context);
                  downloadProvider.downloadTrack(
                    track,
                    player.currentPlaylistId ?? track.id,
                    quality: settings.audioQuality.name,
                  );
                },
        ),
      _MoreAction(
        icon: player.isSleepTimerActive
            ? Icons.timer_off_rounded
            : Icons.timer_rounded,
        title: player.isSleepTimerActive ? 'Cancel sleep timer' : 'Sleep timer',
        subtitle: player.isSleepTimerActive
            ? formatDuration(player.sleepTimerRemaining ?? Duration.zero)
            : 'Stop playback later',
        onTap: () {
          Navigator.pop(context);
          if (player.isSleepTimerActive) {
            player.cancelSleepTimer();
          } else {
            _showSleepTimerDialog(context, player);
          }
        },
      ),
      if (player.queue.isNotEmpty)
        _MoreAction(
          icon: Icons.clear_all_rounded,
          title: 'Clear queue',
          subtitle: 'Remove upcoming tracks',
          destructive: true,
          onTap: () {
            Navigator.pop(context);
            _showClearQueueDialog(context, player);
          },
        ),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: const Color(0xFF171717),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withAlpha(14)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Now playing',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              ...items.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: item.destructive
                          ? Colors.redAccent.withAlpha(28)
                          : Colors.white.withAlpha(12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      item.icon,
                      color: item.destructive ? Colors.redAccent : Colors.white,
                    ),
                  ),
                  title: Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(item.subtitle),
                  enabled: item.onTap != null,
                  onTap: item.onTap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLyricsSheet(BuildContext context, Track track) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.sizeOf(context).height * 0.78,
        margin: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF171717),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withAlpha(14)),
        ),
        clipBehavior: Clip.antiAlias,
        child: FutureBuilder<LyricsResult?>(
          future: _lyricsService.getLyrics(track),
          builder: (context, snapshot) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
                  child: Row(
                    children: [
                      const Icon(Icons.lyrics_rounded),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _LyricsSheetBody(
                    result: snapshot.data,
                    isLoading:
                        snapshot.connectionState == ConnectionState.waiting,
                  ),
                ),
              ],
            );
          },
        ),
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

class _LyricsSheetBody extends StatelessWidget {
  final LyricsResult? result;
  final bool isLoading;

  const _LyricsSheetBody({required this.result, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final lyrics = result;
    if (lyrics == null || !lyrics.hasAnyLyrics) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No direct synced lyrics found for this track.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    if (!lyrics.hasSyncedLyrics) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: SelectableText(
          lyrics.plainLyrics ?? '',
          style: const TextStyle(fontSize: 18, height: 1.55),
        ),
      );
    }

    return _SyncedLyricsList(lines: lyrics.syncedLines);
  }
}

class _SyncedLyricsList extends StatefulWidget {
  final List<LyricLine> lines;

  const _SyncedLyricsList({required this.lines});

  @override
  State<_SyncedLyricsList> createState() => _SyncedLyricsListState();
}

class _SyncedLyricsListState extends State<_SyncedLyricsList> {
  final ScrollController _scrollController = ScrollController();
  late List<GlobalKey> _lineKeys;
  int _lastActiveIndex = -1;

  @override
  void initState() {
    super.initState();
    _lineKeys = List.generate(widget.lines.length, (_) => GlobalKey());
  }

  @override
  void didUpdateWidget(covariant _SyncedLyricsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lines.length != widget.lines.length) {
      _lineKeys = List.generate(widget.lines.length, (_) => GlobalKey());
      _lastActiveIndex = -1;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, player, _) {
        final activeIndex = _activeLyricIndex(widget.lines, player.position);
        _scheduleAutoScroll(activeIndex);
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          itemCount: widget.lines.length,
          itemBuilder: (context, index) {
            final line = widget.lines[index];
            final active = index == activeIndex;
            return GestureDetector(
              key: _lineKeys[index],
              onTap: () => player.seekTo(line.time),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? Theme.of(context).colorScheme.primary.withAlpha(32)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  line.text,
                  style: TextStyle(
                    color: active ? Colors.white : Colors.white54,
                    fontSize: active ? 20 : 17,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _scheduleAutoScroll(int activeIndex) {
    if (activeIndex == _lastActiveIndex ||
        activeIndex < 0 ||
        activeIndex >= _lineKeys.length) {
      return;
    }
    _lastActiveIndex = activeIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_ensureActiveLineVisible(activeIndex)) return;
      if (!_scrollController.hasClients) return;
      final estimatedOffset = (activeIndex * 64.0).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController
          .animateTo(
            estimatedOffset,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          )
          .then((_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _ensureActiveLineVisible(activeIndex);
            });
          });
    });
  }

  bool _ensureActiveLineVisible(int activeIndex) {
    final context = _lineKeys[activeIndex].currentContext;
    if (context == null) return false;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.34,
    );
    return true;
  }

  int _activeLyricIndex(List<LyricLine> lines, Duration position) {
    var active = 0;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].time <= position) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }
}

class _MoreAction {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool destructive;

  const _MoreAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.destructive = false,
  });
}

class _SeekWaveform extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;
  final ValueChanged<Duration> onSeek;

  const _SeekWaveform({
    required this.position,
    required this.duration,
    required this.bufferedPosition,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;
    final bufferProgress = duration.inMilliseconds > 0
        ? bufferedPosition.inMilliseconds / duration.inMilliseconds
        : 0.0;

    void seekFromX(double x, double width) {
      if (duration.inMilliseconds <= 0 || width <= 0) return;
      final value = (x / width).clamp(0.0, 1.0);
      onSeek(Duration(milliseconds: (value * duration.inMilliseconds).round()));
    }

    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(formatDuration(position), style: PlayerScreen._timeStyle),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) =>
                    seekFromX(details.localPosition.dx, constraints.maxWidth),
                onHorizontalDragUpdate: (details) =>
                    seekFromX(details.localPosition.dx, constraints.maxWidth),
                child: SizedBox(
                  height: 58,
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, 58),
                    painter: _WaveformPainter(
                      progress: progress.clamp(0.0, 1.0),
                      bufferProgress: bufferProgress.clamp(0.0, 1.0),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            formatDuration(duration),
            textAlign: TextAlign.end,
            style: PlayerScreen._timeStyle,
          ),
        ),
      ],
    );
  }
}

class _BlurredArtworkBackground extends StatelessWidget {
  final String? imageUrl;

  const _BlurredArtworkBackground({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final original = imageUrl ?? '';
    final fallback = _hiFiArtworkUrl(imageUrl);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (original.isNotEmpty)
          CachedNetworkImage(
            imageUrl: original,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(color: Colors.black),
            errorWidget: (context, url, error) =>
                fallback.isNotEmpty && fallback != original
                ? CachedNetworkImage(
                    imageUrl: fallback,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) =>
                        Container(color: Colors.black),
                  )
                : Container(color: Colors.black),
          ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(color: Colors.black.withAlpha(120)),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x66303030), Color(0xEE151515), Color(0xFF101010)],
              stops: [0.0, 0.42, 1.0],
            ),
          ),
        ),
      ],
    );
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
        child: _ArtworkImage(imageUrl: imageUrl),
      ),
    );
  }
}

class _ArtworkImage extends StatelessWidget {
  final String? imageUrl;

  const _ArtworkImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final original = imageUrl ?? '';
    final fallback = _hiFiArtworkUrl(imageUrl);
    return CachedNetworkImage(
      imageUrl: original,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(color: const Color(0xFF282828)),
      errorWidget: (context, url, error) =>
          fallback.isNotEmpty && fallback != original
          ? CachedNetworkImage(
              imageUrl: fallback,
              fit: BoxFit.cover,
              placeholder: (context, url) =>
                  Container(color: const Color(0xFF282828)),
              errorWidget: (context, url, error) => _ArtworkFallback(),
            )
          : _ArtworkFallback(),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF282828),
      child: const Icon(
        Icons.music_video_rounded,
        size: 68,
        color: Colors.white38,
      ),
    );
  }
}

String _hiFiArtworkUrl(String? url) {
  final value = url ?? '';
  if (value.isEmpty) return value;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.pathSegments.isEmpty) return value;
  final last = uri.pathSegments.last;
  const replaceable = {
    'default.jpg',
    'mqdefault.jpg',
    'hqdefault.jpg',
    'sddefault.jpg',
  };
  if (!replaceable.contains(last)) return value;
  final segments = [...uri.pathSegments];
  segments[segments.length - 1] = 'hqdefault.jpg';
  return uri.replace(pathSegments: segments).toString();
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
