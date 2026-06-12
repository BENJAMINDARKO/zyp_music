import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../domain/entities/auto_dj_mode.dart';
import '../../domain/entities/lyric_line.dart';
import '../../presentation/providers/miniplayer_visibility_provider.dart';
import '../../presentation/providers/player_provider.dart';
import '../../presentation/providers/playlist_provider.dart';
import '../../core/constants/repeat_mode.dart' as repeat;
import '../../domain/entities/video.dart';
import '../widgets/auto_dj_mode_picker.dart';
import '../widgets/playing_track_mask.dart';
import '../widgets/add_to_playlist_modal.dart';
import '../widgets/synced_lyrics_widget.dart';
import '../widgets/single_line_lyrics_widget.dart';
import '../widgets/lyrics_timing_slider.dart';
import '../widgets/playback_speed_selector.dart';
import '../../presentation/providers/settings_provider.dart';
import '../../presentation/providers/download_provider.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/custom_audio_seekbar.dart';
import '../widgets/seekbar_connector.dart';
import 'artist_screen.dart';
import 'album_screen.dart';
import '../widgets/apple_music_sheet.dart';
import "../../core/utils/thumbnail_url.dart";

class PlayingScreen extends StatefulWidget {
  final bool initialLyricsMode;

  const PlayingScreen({
    super.key,
    this.initialLyricsMode = false,
  });

  @override
  State<PlayingScreen> createState() => _PlayingScreenState();
}

enum _LyricsViewMode { compact, fullscreen }

class _PlayingScreenState extends State<PlayingScreen>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  PersistentBottomSheetController? _queueSheetController;
  late AnimationController _rotationController;
  bool _wasPlaying = false;
  _LyricsViewMode _lyricsViewMode = _LyricsViewMode.compact;
  bool _karaokeMode = false;
  MiniplayerVisibilityProvider? _visibilityProvider;

  void _toggleKaraokeMode() {
    setState(() {
      _karaokeMode = !_karaokeMode;
    });
  }

  bool _lyricsScrollPaused = false;
  int? _frozenPositionMs;

  void _toggleLyricsScroll() {
    setState(() {
      if (_lyricsScrollPaused) {
        _lyricsScrollPaused = false;
        _frozenPositionMs = null;
      } else {
        _lyricsScrollPaused = true;
        _frozenPositionMs = context
            .read<PlayerProvider>()
            .positionNotifier
            .value
            .inMilliseconds;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _visibilityProvider = context.read<MiniplayerVisibilityProvider>();
    if (widget.initialLyricsMode) {
      _lyricsViewMode = _LyricsViewMode.fullscreen;
    }
    Future.microtask(() {
      if (mounted) _visibilityProvider?.hide();
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
    _visibilityProvider?.show();
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
            body: Center(
              child: Text(
                'No track playing',
              ),
            ),
          );
        }

        // Sync rotation animation with play state
        if (player.isActuallyPlaying && !_wasPlaying) {
          _rotationController.repeat();
        } else if (!player.isActuallyPlaying && _wasPlaying) {
          _rotationController.stop();
        }
        _wasPlaying = player.isActuallyPlaying;


        final activeColor = Theme.of(context).colorScheme.onSurface;
        final settings = context.watch<SettingsProvider>();
        final seekbarColor = settings.invertSeekbarColor
            ? Colors.black
            : activeColor;

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Layer 1: full-bleed album art (blurred backdrop)
              Positioned.fill(
                child: (track.thumbnailUrl?.isNotEmpty ?? false)
                    ? CachedNetworkImage(
                        imageUrl: rewriteThumbnailSize(track.thumbnailUrl, 1200),
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => track.thumbnailUrl?.contains('maxresdefault.jpg') == true || rewriteThumbnailSize(track.thumbnailUrl, 1200).contains('maxresdefault.jpg')
                            ? CachedNetworkImage(
                                imageUrl: rewriteThumbnailSize(track.thumbnailUrl, 1200).replaceFirst('maxresdefault.jpg', 'hqdefault.jpg'),
                                fit: BoxFit.cover,
                                errorWidget: (____, _____, ______) => Container(color: const Color(0xFF0A0A0A)),
                              )
                            : Container(color: const Color(0xFF0A0A0A)),
                      )
                    : Container(color: const Color(0xFF0A0A0A)),
              ),
              // Layer 2: 40/40 Gaussian blur
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 40.0, sigmaY: 40.0),
                  child: const SizedBox.shrink(),
                ),
              ),
              // Layer 3: tinted gradient scrim (or fallback dark scrim)
              Positioned.fill(
                child: player.dominantColor != null
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              player.dominantColor!.withOpacity(0.85),
                              player.dominantColor!.withOpacity(0.4),
                              Colors.black.withOpacity(0.85),
                            ],
                            stops: const [0.0, 0.5, 1.0],
                          ),
                        ),
                      )
                    : ColoredBox(color: Colors.black.withOpacity(0.75)),
              ),
              SafeArea(
                child: Column(
                  children: [
                    // Top bar
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              PhosphorIconsRegular.caretDown,
                              color: Theme.of(context).colorScheme.onSurface,
                              size: 30,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Expanded(
                            child: Text(
                              'Now Playing',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: player.autoDJMode == AutoDJMode.off
                                ? Icon(
                                    PhosphorIconsRegular.sparkle,
                                    color: player.isAutoDJEnabled
                                        ? Theme.of(context).colorScheme.onSurface
                                        : Theme.of(context).colorScheme.onSurface.withOpacity(0.35),
                                  )
                                : player.autoDJMode.iconBuilder(
                                    color: player.isAutoDJEnabled
                                        ? Theme.of(context).colorScheme.onSurface
                                        : Theme.of(context).colorScheme.onSurface.withOpacity(0.35),
                                  ),
                            tooltip: player.isAutoDJEnabled
                                ? 'Auto DJ: ${player.autoDJMode.label} — tap to change'
                                : 'Engage Auto DJ',
                            onPressed: () {
                              // Phase 0: opens the mode picker so the
                              // user can pick / change / disengage the
                              // engine. The picker writes through to
                              // PlayerProvider.setAutoDJMode; the
                              // per-mode engine logic lands in Phase 1.
                              AutoDJModePicker.show(context);
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    if (_lyricsViewMode == _LyricsViewMode.fullscreen) ...[
                      // Small thumb row (State B)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24.0,
                          vertical: 8.0,
                        ),
                        child: Row(
                          children: [
                            RotationTransition(
                              turns: _rotationController,
                              child: Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  image:
                                      (track.thumbnailUrl?.isNotEmpty ?? false)
                                      ? DecorationImage(
                                          image: NetworkImage(
                                            rewriteThumbnailSize(track.thumbnailUrl, 1200),
                                          ),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                  color:
                                      (track.thumbnailUrl?.isNotEmpty ?? false)
                                      ? null
                                      : Colors.grey[800],
                                ),
                                child: Center(
                                  child: Container(
                                    width: 15,
                                    height: 15,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFF141414),
                                      border: Border.all(
                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.24),
                                        width: 1,
                                      ),
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
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    track.author ?? 'Unknown',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.70),
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                _karaokeMode
                                    ? PhosphorIconsFill.microphoneStage
                                    : PhosphorIconsRegular.microphoneStage,
                                color: _karaokeMode
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurface,
                                size: 24,
                              ),
                              onPressed: _toggleKaraokeMode,
                              tooltip: 'Karaoke',
                            ),
                          ],
                        ),
                      ),

                      // Fullscreen lyrics (normal or karaoke)
                      Expanded(
                        child: _karaokeMode
                            ? _buildKaraokeView(context)
                                : (player.isLoadingLyrics || player.lyrics != null
                                ? ValueListenableBuilder<Duration>(
                                    valueListenable: player.positionNotifier,
                                    builder: (_, pos, __) {
                                      final effectivePos = _lyricsScrollPaused &&
                                              _frozenPositionMs != null
                                          ? Duration(
                                              milliseconds: _frozenPositionMs!)
                                          : pos;
                                      return Opacity(
                                        opacity:
                                            _lyricsScrollPaused ? 0.5 : 1.0,
                                        child: SyncedLyricsWidget(
                                          lyricsText: player.lyrics ?? '',
                                          isLoading: player.isLoadingLyrics,
                                          position: Duration(
                                            milliseconds:
                                                effectivePos.inMilliseconds +
                                                    player.lyricsSyncOffsetMs,
                                          ),
                                          karaokeMode: false,
                                          autoScroll: !_lyricsScrollPaused,
                                        ),
                                      );
                                    },
                                  )
                                : Center(
                                    child: Text(
                                      'No lyrics available',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
                                        fontSize: 16,
                                      ),
                                    ),
                                  )),
                      ),

                      // Lyrics timing slider + pause/resume (visible only in State B)
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              _lyricsScrollPaused
                                  ? PhosphorIconsFill.play
                                  : PhosphorIconsFill.pause,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            onPressed: _toggleLyricsScroll,
                            tooltip: _lyricsScrollPaused
                                ? 'Resume scrolling'
                                : 'Pause scrolling',
                          ),
                          const Expanded(child: LyricsTimingSlider()),
                        ],
                      ),
                    ] else ...[
                      // State A: boxed album art → lyric → title/artist

                      // Boxed album art (centered, 70% width, 8px radius)
                      Center(
                        child: ClipRRect(
                          key: const Key('album-art'),
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: MediaQuery.of(context).size.width * 0.85,
                            height: MediaQuery.of(context).size.width * 0.85,
                            child: (track.thumbnailUrl?.isNotEmpty ?? false)
                                ? CachedNetworkImage(
                                    imageUrl: rewriteThumbnailSize(track.thumbnailUrl, 1200),
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => track.thumbnailUrl?.contains('maxresdefault.jpg') == true || rewriteThumbnailSize(track.thumbnailUrl, 1200).contains('maxresdefault.jpg')
                                        ? CachedNetworkImage(
                                            imageUrl: rewriteThumbnailSize(track.thumbnailUrl, 1200).replaceFirst('maxresdefault.jpg', 'sddefault.jpg'),
                                            fit: BoxFit.cover,
                                            errorWidget: (____, _____, ______) => CachedNetworkImage(
                                              imageUrl: rewriteThumbnailSize(track.thumbnailUrl, 1200).replaceFirst('maxresdefault.jpg', 'hqdefault.jpg'),
                                              fit: BoxFit.cover,
                                              errorWidget: (_______, ________, _________) => Container(
                                                color: const Color(0xFF0A0A0A),
                                                child: Icon(
                                                  PhosphorIconsRegular.musicNote,
                                                  size: 80,
                                                  color: Colors.white38,
                                                ),
                                              ),
                                            ),
                                          )
                                        : Container(
                                            color: const Color(0xFF0A0A0A),
                                            child: Icon(
                                              PhosphorIconsRegular.musicNote,
                                              size: 80,
                                              color: Colors.white38,
                                            ),
                                          ),
                                  )
                                : Container(
                                    color: const Color(0xFF0A0A0A),
                                    child: Icon(
                                      PhosphorIconsRegular.musicNote,
                                      size: 80,
                                      color: Colors.white38,
                                    ),
                                  ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Single-line active lyrics
                      SingleLineLyricsWidget(),

                      const Spacer(),

                      // Track info + favorite (inline)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTap: () async {
                                      if (track.albumId != null) {
                                        final provider = context
                                            .read<PlaylistProvider>();
                                        final res = await provider.searchAlbums(
                                          track.album!,
                                        );
                                        if (res.isNotEmpty && context.mounted) {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => AlbumScreen(
                                                albumId: res.first.id,
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    child: Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  GestureDetector(
                                    onTap: () async {
                                      if (track.author != null) {
                                        final provider = context
                                            .read<PlaylistProvider>();
                                        final artist = await provider
                                            .findCorrectArtist(
                                              track.author!,
                                              track.album,
                                            );
                                        if (artist != null && context.mounted) {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => ArtistScreen(
                                                artistId: artist.id,
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    child: Text(
                                      track.author ?? 'Unknown Artist',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.normal,
                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.70),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Consumer<PlaylistProvider>(
                              builder: (context, pp, _) {
                                final isFav = pp.isFavorite(track.id);
                                return IconButton(
                                  icon: Icon(
                                    isFav
                                        ? PhosphorIconsFill.heart
                                        : PhosphorIconsRegular.heart,
                                    color: isFav
                                        ? Theme.of(context).colorScheme.onSurface
                                        : Theme.of(context).colorScheme.onSurface.withOpacity(0.35),
                                    size: 26,
                                  ),
                                  onPressed: () => pp.toggleFavorite(
                                    track,
                                    downloadProvider: context
                                        .read<DownloadProvider>(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: _buildMediaControls(
            context,
            player,
            track,
            seekbarColor,
            settings,
          ),
        );
      },
    );
  }

  Color _contrastingIconColor(Color background) {
    return background.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }

  Widget _buildPlayPauseButton(PlayerProvider player, Color dominantColor) {
    final luminance = dominantColor.computeLuminance();
    final circleColor = luminance > 0.5 ? Colors.black : Colors.white;
    final iconColor = luminance > 0.5 ? Colors.white : Colors.black;

    return GestureDetector(
      onTap: player.togglePlayPause,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: circleColor,
          shape: BoxShape.circle,
        ),
        child: player.isBuffering
            ? const Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    color: Colors.black,
                    strokeWidth: 3,
                  ),
                ),
              )
            : Icon(
                player.isActuallyPlaying
                    ? PhosphorIconsFill.pause
                    : PhosphorIconsFill.play,
                color: iconColor,
                size: 40,
              ),
      ),
    );
  }

  Widget _buildMediaControls(
    BuildContext context,
    PlayerProvider player,
    Track track,
    Color seekbarColor,
    SettingsProvider settings,
  ) {
    final dominantColor = player.dominantColor ??
        Theme.of(context).scaffoldBackgroundColor;
    final iconColor = _contrastingIconColor(dominantColor);
    final secondaryIconColor = iconColor.withOpacity(0.6);
    final accentColor = Theme.of(context).colorScheme.primary;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          // Seek bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                SeekbarConnector(
                  hasTrack: true,
                  activeColor: seekbarColor,
                  inactiveColor: settings.invertSeekbarColor
                      ? Colors.black.withOpacity(0.30)
                      : secondaryIconColor.withOpacity(0.5),
                  style: settings.seekbarStyle == 'Gradient'
                      ? SeekbarStyle.gradient
                      : (settings.seekbarStyle == 'Waveform'
                            ? SeekbarStyle.waveform
                            : (settings.seekbarStyle == 'Wavy'
                                  ? SeekbarStyle.wavy
                                  : SeekbarStyle.minimal)),
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
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ValueListenableBuilder<Duration>(
                        valueListenable: player.positionNotifier,
                        builder: (_, pos, __) => Text(
                          _formatDuration(pos),
                          style: TextStyle(
                            color: secondaryIconColor,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      ValueListenableBuilder<Duration>(
                        valueListenable: player.durationNotifier,
                        builder: (_, dur, __) => Text(
                          _formatDuration(dur),
                          style: TextStyle(
                            color: secondaryIconColor,
                            fontSize: 12,
                          ),
                        ),
                      ),
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
                  icon: Icon(
                    player.shuffleMode ? PhosphorIconsFill.shuffle : PhosphorIconsRegular.shuffle,
                    size: 28,
                    color: player.shuffleMode
                        ? accentColor
                        : secondaryIconColor,
                  ),
                  onPressed: player.toggleShuffle,
                ),
                IconButton(
                  icon: Icon(
                    PhosphorIconsFill.skipBack,
                    size: 40,
                    color: iconColor,
                  ),
                  onPressed: player.currentIndex > 0
                      ? () => player.previous()
                      : null,
                ),
                _buildPlayPauseButton(player, dominantColor),
                IconButton(
                  icon: Icon(
                    PhosphorIconsFill.skipForward,
                    size: 40,
                    color: iconColor,
                  ),
                  onPressed: player.currentIndex + 1 < player.queue.length
                      ? () => player.next()
                      : null,
                ),
                IconButton(
                  icon: Icon(
                    player.repeatMode == repeat.PlaybackRepeatMode.one
                        ? PhosphorIconsFill.repeatOnce
                        : player.repeatMode != repeat.PlaybackRepeatMode.none
                            ? PhosphorIconsFill.repeat
                            : PhosphorIconsRegular.repeat,
                    size: 28,
                    color: player.repeatMode != repeat.PlaybackRepeatMode.none
                        ? accentColor
                        : secondaryIconColor,
                  ),
                  onPressed: player.cycleRepeatMode,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Bottom action row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  key: const Key('lyrics-toggle-button'),
                  icon: Icon(
                    PhosphorIcons.scroll,
                    color: _lyricsViewMode == _LyricsViewMode.fullscreen
                        ? accentColor
                        : secondaryIconColor,
                    size: 22,
                  ),
                  onPressed: () =>
                      setState(() {
                        _lyricsViewMode = _lyricsViewMode == _LyricsViewMode.compact
                            ? _LyricsViewMode.fullscreen
                            : _LyricsViewMode.compact;
                      }),
                ),
                PlaybackSpeedSelector(iconColor: secondaryIconColor),
                IconButton(
                  icon: Icon(
                    PhosphorIconsRegular.playlist,
                    color: secondaryIconColor,
                    size: 22,
                  ),
                  onPressed: () {
                    AddToPlaylistModal.show(context, track);
                  },
                ),
                IconButton(
                  icon: Icon(
                    PhosphorIconsRegular.queue,
                    color: secondaryIconColor,
                    size: 22,
                  ),
                  onPressed: () => _showUpNextModal(context, player),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  LyricLine? _findActiveLine(List<LyricLine> lyrics, Duration position) {
    LyricLine? active;
    for (final line in lyrics) {
      if (position >= line.time) {
        active = line;
      } else {
        break;
      }
    }
    return active;
  }

  List<LyricLine> _parseLyrics(String text) {
    final lines = text.split('\n');
    final regex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');
    final result = <LyricLine>[];
    var hasSynced = false;

    for (final line in lines) {
      final match = regex.firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        var msStr = match.group(3)!;
        if (msStr.length == 2) msStr = '${msStr}0';
        final milliseconds = int.parse(msStr);
        final text = match.group(4)!.trim();
        result.add(LyricLine(
          time: Duration(minutes: minutes, seconds: seconds, milliseconds: milliseconds),
          words: text,
        ));
        hasSynced = true;
      }
    }

    if (!hasSynced) {
      for (final line in lines) {
        if (line.trim().isNotEmpty) {
          result.add(LyricLine(time: Duration.zero, words: line.trim()));
        }
      }
    }

    return result;
  }

  Widget _buildKaraokeView(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = Theme.of(context).colorScheme.onSurface;

    return Consumer<PlayerProvider>(
      builder: (context, player, _) {
        final lyricsText = player.lyrics;
        if (lyricsText == null || lyricsText.trim().isEmpty) {
          return Center(
            child: Text(
              'No lyrics available',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: iconColor.withOpacity(0.5),
              ),
            ),
          );
        }

        final lyrics = _parseLyrics(lyricsText);
        if (lyrics.isEmpty) {
          return Center(
            child: Text(
              'No lyrics available',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: iconColor.withOpacity(0.5),
              ),
            ),
          );
        }

        return Column(
          children: [
            Expanded(
              child: Center(
                child: ValueListenableBuilder<Duration>(
                  valueListenable: player.positionNotifier,
                  builder: (context, position, _) {
                    final effectivePosition = _lyricsScrollPaused &&
                            _frozenPositionMs != null
                        ? Duration(milliseconds: _frozenPositionMs!)
                        : position;
                    final activeLine =
                        _findActiveLine(lyrics, effectivePosition);

                    if (activeLine == null) {
                      return const SizedBox.shrink();
                    }

                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      layoutBuilder: (currentChild, previousChildren) {
                        return currentChild ?? const SizedBox.shrink();
                      },
                      transitionBuilder: (child, animation) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                      child: Padding(
                        key: ValueKey('karaoke-${activeLine.time.inMilliseconds}'),
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          activeLine.words,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: iconColor.withOpacity(
                                _lyricsScrollPaused ? 0.5 : 1.0),
                            height: 1.4,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Speed:',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: iconColor.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const PlaybackSpeedSelector(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _showUpNextModal(BuildContext context, PlayerProvider player) {
    if (_queueSheetController != null) {
      _queueSheetController!.close();
      _queueSheetController = null;
      return;
    }

    _queueSheetController = _scaffoldKey.currentState!.showBottomSheet(
      (context) {
        return Consumer<PlayerProvider>(
          builder: (context, provider, child) {
            final queue = provider.queue;
            final currentIndex = provider.currentIndex;

            return AppleMusicSheet(
              title: 'Up Next',
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 4),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: Icon(
                          PhosphorIconsRegular.x,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.70),
                        ),
                        onPressed: () {
                          _queueSheetController?.close();
                          _queueSheetController = null;
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: queue.length,
                      itemBuilder: (context, index) {
                        final t = queue[index];
                        final isPlaying = index == currentIndex;
                        return PlayingTrackMask(
                          track: t,
                          child: ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: (t.thumbnailUrl?.isNotEmpty ?? false)
                                  ? CachedNetworkImage(
                                      imageUrl: rewriteThumbnailSize(t.thumbnailUrl),
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) =>
                                          Container(color: Colors.grey[800]),
                                    )
                                  : Container(
                                      width: 48,
                                      height: 48,
                                      color: Colors.grey[800],
                                    ),
                            ),
                            title: Text(
                              t.title,
                              style: TextStyle(
                                fontWeight: isPlaying
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isPlaying
                                    ? const Color(0xFFEAB308)
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              t.author ?? 'Unknown',
                              style: TextStyle(
                                color: isPlaying
                                    ? const Color(0xFFEAB308).withOpacity(0.8)
                                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: Icon(
                                PhosphorIconsRegular.x,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
                              ),
                              onPressed: () {
                                provider.removeFromQueue(index);
                              },
                            ),
                            onTap: () {
                              provider.playFromQueue(index);
                              _queueSheetController?.close();
                              _queueSheetController = null;
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      backgroundColor: Colors.transparent,
      elevation: 0,
    );
  }
}
