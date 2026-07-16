import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mini_music_visualizer/mini_music_visualizer.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/auto_dj_mode.dart';
import '../../domain/entities/video.dart';
import '../../presentation/providers/player_provider.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../presentation/providers/download_provider.dart';
import '../../presentation/providers/miniplayer_visibility_provider.dart';
import '../screens/playing_screen.dart';
import '../screens/artist_screen.dart';
import '../screens/album_screen.dart';
import 'auto_dj_mode_picker.dart';
import 'playlist_picker_dialog.dart';
import '../../core/constants/repeat_mode.dart' as repeat;
import '../../presentation/providers/settings_provider.dart';
import 'custom_audio_seekbar.dart';
import 'seekbar_connector.dart';
import '../../core/navigation/navigator_key.dart';
import "../../core/utils/thumbnail_url.dart";

class PrismCapsuleProgressPainter extends CustomPainter {
  PrismCapsuleProgressPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(3),
      const Radius.circular(25),
    );
    final path = Path()..addRRect(rrect);
    final metric = path.computeMetrics().first;
    final drawLength = metric.length * progress.clamp(0.0, 1.0);
    if (drawLength <= 0) return;

    final progressPath = metric.extractPath(0, drawLength);

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [
          ZypAuroraColors.cyan,
          ZypAuroraColors.pink,
          ZypAuroraColors.peach,
        ],
      ).createShader(rect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(progressPath, glowPaint);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [
          ZypAuroraColors.cyan,
          ZypAuroraColors.pink,
          ZypAuroraColors.peach,
        ],
      ).createShader(rect);
    canvas.drawPath(progressPath, ringPaint);
  }

  @override
  bool shouldRepaint(covariant PrismCapsuleProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

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
        navigatorKey.currentState!.push(
          MaterialPageRoute(builder: (_) => ArtistScreen(artistId: artist.id)),
        );
      }
    }

    void navigateToAlbum(String name) async {
      final provider = context.read<PlaylistProvider>();
      final res = await provider.searchAlbums(name);
      if (res.isNotEmpty && navigatorKey.currentState != null) {
        navigatorKey.currentState!.push(
          MaterialPageRoute(builder: (_) => AlbumScreen(albumId: res.first.id)),
        );
      }
    }

    if (track.author != null && track.author!.isNotEmpty) {
      parts.add(
        GestureDetector(
          onTap: () => navigateToArtist(track.author!, track.album),
          child: Text(
            track.author!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
              fontSize: 11,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      );
    }

    if (track.album != null && track.album!.isNotEmpty) {
      if (parts.isNotEmpty) {
        parts.add(
          Text(
            ' • ',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 11),
          ),
        );
      }
      parts.add(
        GestureDetector(
          onTap: () => navigateToAlbum(track.album!),
          child: Text(
            track.album!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
              fontSize: 11,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      );
    }

    if (track.year != null) {
      if (parts.isNotEmpty) {
        parts.add(
          Text(
            ' • ',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 11),
          ),
        );
      }
      parts.add(
        Text(
          track.year.toString(),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 11),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(mainAxisSize: MainAxisSize.min, children: parts),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MiniplayerVisibilityProvider>(
      builder: (context, visibility, _) {
        if (!visibility.isVisible) {
          return const SizedBox.shrink();
        }
        return Consumer<PlayerProvider>(
          builder: (context, player, _) {
            final isEmptyState = player.currentTrack == null;
            if (isEmptyState) {
              return const SizedBox.shrink();
            }

            final track = player.currentTrack!;
            final activeColor = player.dominantColor ?? const Color(0xFFEAB308);
            final isDesktop = MediaQuery.of(context).size.width >= 800;

            Widget playerWidget;
            if (isDesktop) {
              playerWidget = _buildDesktopPlayer(
                context,
                player,
                track,
                activeColor,
                false,
              );
            } else {
              playerWidget = _buildMobilePlayer(
                context,
                player,
                track,
                activeColor,
              );
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
                        Icon(PhosphorIconsFill.warning, color: Theme.of(context).colorScheme.onSurface, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            player.error!,
                            style: const TextStyle(
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            PhosphorIconsRegular.x,
                            color: Theme.of(context).colorScheme.onSurface,
                            size: 16,
                          ),
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
      },
    );
  }

  Widget _buildDesktopPlayer(
    BuildContext context,
    PlayerProvider player,
    dynamic track,
    Color activeColor,
    bool isEmptyState,
  ) {
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
                  SeekbarStyle style = SeekbarStyle.prism;
                  switch (settings.seekbarStyle) {
                    case 'Gradient':
                      style = SeekbarStyle.gradient;
                      break;
                    case 'Waveform':
                      style = SeekbarStyle.waveform;
                      break;
                    case 'Minimal':
                      style = SeekbarStyle.minimal;
                      break;
                    case 'Wavy':
                      style = SeekbarStyle.wavy;
                      break;
                    case 'Segmented':
                      style = SeekbarStyle.segmented;
                      break;
                    case 'Prism':
                      style = SeekbarStyle.prism;
                      break;
                  }
                  return SeekbarConnector(
                    hasTrack: !isEmptyState,
                    activeColor: activeColor,
                    style: style,
                    invertColor: settings.invertSeekbarColor,
                    isPlaying: player.isActuallyPlaying,
                    onChangeStart: () => player.startSeek(),
                    onChanged: (v) {
                      final pos = Duration(
                        milliseconds: (v * player.duration.inMilliseconds)
                            .round(),
                      );
                      player.updateSeek(pos);
                    },
                    onChangeEnd: (v) {
                      final pos = Duration(
                        milliseconds: (v * player.duration.inMilliseconds)
                            .round(),
                      );
                      player.endSeek(pos);
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
                                imageUrl: rewriteThumbnailSize(track.thumbnailUrl),
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                errorWidget: (context, url, error) => Container(
                                  width: 56,
                                  height: 56,
                                  color: Colors.grey[800],
                                  child: const Icon(PhosphorIconsRegular.musicNote),
                                ),
                              )
                            : Container(
                                width: 56,
                                height: 56,
                                color: Colors.grey[800],
                                child: const Icon(PhosphorIconsRegular.musicNote),
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
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              track.author ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.70),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        width: 30,
                        height: 20,
                        child: MiniMusicVisualizer(
                          color: Theme.of(context).colorScheme.onSurface,
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
                            icon: Icon(
                              PhosphorIconsFill.skipBack,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            onPressed: !isEmptyState && player.currentIndex > 0
                                ? () => player.previous()
                                : null,
                          ),
                          player.isBuffering
                              ? Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16),
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Theme.of(context).colorScheme.onSurface,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  icon: Icon(
                                    player.isActuallyPlaying
                                        ? PhosphorIconsFill.pauseCircle
                                        : PhosphorIconsFill.playCircle,
                                    size: 48,
                                    color: isEmptyState
                                        ? Theme.of(context).colorScheme.onSurface.withOpacity(0.54)
                                        : Theme.of(context).colorScheme.onSurface,
                                  ),
                                  onPressed: isEmptyState
                                      ? null
                                      : player.togglePlayPause,
                                ),
                          IconButton(
                            icon: Icon(
                              PhosphorIconsFill.skipForward,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            onPressed:
                                !isEmptyState &&
                                    player.currentIndex + 1 <
                                        player.queue.length
                                ? () => player.next()
                                : null,
                          ),
                        ],
                      ),
                      const Spacer(),
                      ValueListenableBuilder<Duration>(
                        valueListenable: player.positionNotifier,
                        builder: (_, pos, __) =>
                            ValueListenableBuilder<Duration>(
                          valueListenable: player.durationNotifier,
                          builder: (_, dur, __) => Text(
                            '${_formatDuration(pos)} / ${_formatDuration(dur)}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        PhosphorIconsRegular.speakerHigh,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
                        size: 20,
                      ),
                      SizedBox(
                        width: 100,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6,
                            ),
                            activeTrackColor: Theme.of(context).colorScheme.onSurface,
                            inactiveTrackColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.24),
                          ),
                          child: Slider(value: 1.0, onChanged: (v) {}),
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

  Widget _buildMobilePlayer(
    BuildContext context,
    PlayerProvider player,
    dynamic track,
    Color activeColor,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (navigatorKey.currentState != null) {
          navigatorKey.currentState!.push(
            MaterialPageRoute(builder: (_) => const PlayingScreen()),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: ValueListenableBuilder<Duration>(
          valueListenable: player.positionNotifier,
          builder: (_, position, child) {
            final duration = player.duration;
            final progress = duration.inMilliseconds == 0
                ? 0.0
                : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
            return CustomPaint(
              painter: PrismCapsuleProgressPainter(progress: progress),
              child: child!,
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(25),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(
                  height: 70,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ZypAuroraColors.glass,
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color: ZypAuroraColors.stroke,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Hero(
                        tag: 'now-playing-art',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(17),
                          child: (track.thumbnailUrl?.isNotEmpty ?? false)
                              ? CachedNetworkImage(
                                  imageUrl: rewriteThumbnailSize(track.thumbnailUrl, 120),
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => _buildArtPlaceholder(context),
                                )
                              : _buildArtPlaceholder(context),
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (track.author != null && track.author!.isNotEmpty)
                              Text(
                                '${track.author!} • 58% prism',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.62),
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Consumer<PlaylistProvider>(
                        builder: (context, playlists, _) {
                          final isFavorite = playlists.isFavorite(track.id);
                          return IconButton(
                            icon: Icon(
                              isFavorite ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                              color: isFavorite ? ZypAuroraColors.success : Colors.white.withOpacity(0.54),
                              size: 25,
                            ),
                            onPressed: () {
                              playlists.toggleFavorite(
                                track,
                                downloadProvider: context.read<DownloadProvider>(),
                              );
                            },
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(),
                            tooltip: isFavorite ? 'Unlike' : 'Like',
                          );
                        },
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: player.togglePlayPause,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(17),
                            gradient: const LinearGradient(
                              colors: [ZypAuroraColors.cyan, ZypAuroraColors.lime],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              player.isActuallyPlaying ? Icons.pause : Icons.play_arrow,
                              color: const Color(0xFF07110D),
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArtPlaceholder(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Icon(
        PhosphorIconsRegular.musicNote,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        size: 24,
      ),
    );
  }
}
