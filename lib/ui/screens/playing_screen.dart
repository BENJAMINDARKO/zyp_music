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
import '../widgets/audio_output_selector.dart';
import '../widgets/lyrics_share_bottom_sheet.dart';
import 'dart:async';
import '../../presentation/providers/settings_provider.dart';
import '../../presentation/providers/download_provider.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/custom_audio_seekbar.dart';
import '../widgets/seekbar_connector.dart';
import 'artist_screen.dart';
import 'album_screen.dart';
import '../widgets/apple_music_sheet.dart';
import '../widgets/explicit_icon.dart';
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
  bool _showQueue = false;

  bool _showControls = true;
  Timer? _hideControlsTimer;

  bool _lyricsExpanded = false;
  Timer? _lyricsExpansionTimer;

  void _resetLyricsExpansionTimer() {
    if (_lyricsViewMode != _LyricsViewMode.fullscreen) return;
    if (_lyricsExpanded) {
      setState(() {
        _lyricsExpanded = false;
      });
    }
    _lyricsExpansionTimer?.cancel();
    _lyricsExpansionTimer = Timer(const Duration(seconds: 7), () {
      if (mounted && _lyricsViewMode == _LyricsViewMode.fullscreen) {
        setState(() {
          _lyricsExpanded = true;
        });
      }
    });
  }

  void _resetHideControlsTimer() {
    setState(() => _showControls = true);
    _hideControlsTimer?.cancel();
    if (_lyricsViewMode == _LyricsViewMode.fullscreen && !_karaokeMode) {
      _hideControlsTimer = Timer(const Duration(seconds: 5), () {
        if (mounted && _lyricsViewMode == _LyricsViewMode.fullscreen) {
          setState(() => _showControls = false);
        }
      });
    }
  }
  MiniplayerVisibilityProvider? _visibilityProvider;

  void _toggleKaraokeMode() {
    setState(() {
      _karaokeMode = !_karaokeMode;
    });
  }

  bool _lyricsScrollPaused = false;
  int? _frozenPositionMs;

  // ── Lyrics selection state ───────────────────────────────────
  bool _lyricsSelectionMode = false;
  final Set<int> _selectedLyricIndices = {};
  List<LyricLine> _parsedLyricsCache = [];

  void _enterSelectionMode(int index) {
    final lyrics = context.read<PlayerProvider>().lyrics ?? '';
    setState(() {
      _parsedLyricsCache = _parseLyrics(lyrics);
      _lyricsSelectionMode = true;
      _selectedLyricIndices.add(index);
      // pause scroll so lyrics don't jump while selecting
      if (!_lyricsScrollPaused) _toggleLyricsScroll();
    });
  }

  void _toggleLyricSelection(int index) {
    setState(() {
      if (_selectedLyricIndices.contains(index)) {
        _selectedLyricIndices.remove(index);
      } else {
        _selectedLyricIndices.add(index);
      }
    });
  }

  void _cancelSelectionMode() {
    setState(() {
      _lyricsSelectionMode = false;
      _selectedLyricIndices.clear();
    });
  }

  void _openShareSheet(PlayerProvider player) {
    if (_selectedLyricIndices.isEmpty) return;
    final sorted = _selectedLyricIndices.toList()..sort();
    final lines = sorted
        .where((i) => i < _parsedLyricsCache.length)
        .map((i) => _parsedLyricsCache[i].words)
        .where((w) => w.isNotEmpty)
        .toList();
    if (lines.isEmpty) return;
    LyricsShareBottomSheet.show(
      context,
      selectedLines: lines,
      title: player.currentTrack?.title ?? '',
      artist: player.currentTrack?.author ?? '',
      thumbnailUrl: player.currentTrack?.thumbnailUrl,
      dominantColor: player.dominantColor ?? const Color(0xFF2B2B00),
    );
  }


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
      _resetLyricsExpansionTimer();
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
    _hideControlsTimer?.cancel();
    _lyricsExpansionTimer?.cancel();
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
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _resetHideControlsTimer,
            onPanDown: (_) => _resetHideControlsTimer(),
            child: Stack(
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
                    if (_lyricsViewMode != _LyricsViewMode.fullscreen)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: MediaQuery.of(context).size.height < 680 ? 0.0 : 4.0,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                PhosphorIconsRegular.caretLeft,
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
                                      PhosphorIconsBold.sparkle,
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
                                AutoDJModePicker.show(context);
                              },
                            ),
                          ],
                        ),
                      ),



                    // Expanded main body
                    Expanded(
                      child: _lyricsViewMode == _LyricsViewMode.fullscreen
                          ? (_karaokeMode
                              ? _buildKaraokeView(context)
                              : _buildUnifiedLyricsCard(
                                  context,
                                  player,
                                  track,
                                  seekbarColor,
                                  settings,
                                ))
                          : _showQueue
                              ? _buildInlineQueueView(context, player, track)
                              : LayoutBuilder(
                                  builder: (context, constraints) {
                                    final double maxAvailableHeight = constraints.maxHeight;
                                    final bool isSmallScreen = maxAvailableHeight < 300;
                                    
                                    final double lyricsBoxHeight = isSmallScreen ? 30.0 : 45.0;
                                    
                                    // Calculate artSize to fit exactly within constraints.maxHeight, but cap it on small screens to give lyrics breathing room!
                                    final double maxArtSize = isSmallScreen ? 140.0 : constraints.maxWidth * 0.85;
                                    final double artSize = (maxAvailableHeight - lyricsBoxHeight - (isSmallScreen ? 16.0 : 36.0))
                                        .clamp(100.0, maxArtSize);

                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: [
                                        const Spacer(),
                                        Center(
                                          child: ClipRRect(
                                            key: const Key('album-art'),
                                            borderRadius: BorderRadius.circular(16),
                                            child: SizedBox(
                                              width: artSize,
                                              height: artSize,
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
                                                                    size: artSize * 0.4,
                                                                    color: Colors.white38,
                                                                  ),
                                                                ),
                                                              ),
                                                            )
                                                          : Container(
                                                              color: const Color(0xFF0A0A0A),
                                                              child: Icon(
                                                                PhosphorIconsRegular.musicNote,
                                                                size: artSize * 0.4,
                                                                color: Colors.white38,
                                                              ),
                                                            ),
                                                    )
                                                  : Container(
                                                      color: const Color(0xFF0A0A0A),
                                                      child: Icon(
                                                        PhosphorIconsRegular.musicNote,
                                                        size: artSize * 0.4,
                                                        color: Colors.white38,
                                                      ),
                                                    ),
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        // Fixed height container for lyrics so layout never shifts!
                                        SizedBox(
                                          height: lyricsBoxHeight,
                                          child: const SingleLineLyricsWidget(),
                                        ),
                                        const Spacer(),
                                      ],
                                    );
                                  },
                                ),
                    ),

                    // Media controls naturally laid out at the bottom
                    Builder(
                      builder: (context) {
                        final bool showBottomControls = _showControls || (_lyricsViewMode == _LyricsViewMode.fullscreen && !_karaokeMode);
                        return AnimatedSize(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          child: showBottomControls
                              ? IgnorePointer(
                                  ignoring: !showBottomControls,
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 300),
                                    opacity: showBottomControls ? 1.0 : 0.0,
                                    child: _buildMediaControls(
                                      context,
                                      player,
                                      track,
                                      seekbarColor,
                                      settings,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        );
                      }
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

  Widget _buildPlayPauseButton(PlayerProvider player, double circleSize, double iconSize) {
    return GestureDetector(
      onTap: player.togglePlayPause,
      child: Container(
        width: circleSize,
        height: circleSize,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: player.isBuffering
            ? Center(
                child: SizedBox(
                  width: circleSize * 0.45,
                  height: circleSize * 0.45,
                  child: const CircularProgressIndicator(
                    color: Colors.black,
                    strokeWidth: 3,
                  ),
                ),
              )
            : Icon(
                player.isActuallyPlaying
                    ? PhosphorIconsFill.pause
                    : PhosphorIconsFill.play,
                color: Colors.black,
                size: iconSize,
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
    final screenHeight = MediaQuery.of(context).size.height;
    final bool isSmallScreen = screenHeight < 680;

    // Scale card dimensions dynamically to take less than 35% of the screen
    final double cardPaddingVertical = isSmallScreen ? 4.0 : 10.0;
    final double cardPaddingHorizontal = isSmallScreen ? 6.0 : 10.0;
    final double cardMarginHorizontal = isSmallScreen ? 12.0 : 16.0;
    final double cardMarginBottom = isSmallScreen ? 4.0 : 12.0;
    final double titleFontSize = isSmallScreen ? 13.0 : 17.0;
    final double authorFontSize = isSmallScreen ? 10.0 : 12.0;
    final double playButtonCircleSize = isSmallScreen ? 38.0 : 56.0;
    final double playButtonIconSize = isSmallScreen ? 20.0 : 32.0;
    final double skipButtonSize = isSmallScreen ? 18.0 : 30.0;
    final double otherControlsIconSize = isSmallScreen ? 15.0 : 22.0;
    final double internalSpacing1 = isSmallScreen ? 2.0 : 8.0;
    final double internalSpacing2 = isSmallScreen ? 1.0 : 4.0;
    final double actionIconSize = isSmallScreen ? 16.0 : 20.0;

    final bool isFullscreenLyrics = _lyricsViewMode == _LyricsViewMode.fullscreen && !_karaokeMode;

    return Padding(
      padding: EdgeInsets.only(
        left: cardMarginHorizontal,
        right: cardMarginHorizontal,
        bottom: isFullscreenLyrics && _lyricsExpanded ? 4.0 : cardMarginBottom,
        top: 2.0,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 400),
            curve: Curves.fastOutSlowIn,
            child: Container(
              width: double.infinity,
              padding: isFullscreenLyrics && _lyricsExpanded
                  ? EdgeInsets.zero
                  : EdgeInsets.symmetric(
                      vertical: cardPaddingVertical,
                      horizontal: cardPaddingHorizontal,
                    ),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06), // translucent white/grey for frosted glass look
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                  width: 0.5,
                ),
              ),
              child: isFullscreenLyrics && _lyricsExpanded
                  ? GestureDetector(
                      onTap: () {
                        setState(() {
                          _lyricsExpanded = false;
                          _resetLyricsExpansionTimer();
                        });
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        color: Colors.transparent,
                        child: Center(
                          child: Icon(
                            PhosphorIconsRegular.caretUp,
                            color: Colors.white.withOpacity(0.35),
                            size: 20,
                          ),
                        ),
                      ),
                    )
                  : _lyricsSelectionMode
                      ? _buildSelectionActionBar(player)
                      : _buildMediaControlsContent(
                          context,
                          player,
                          track,
                          seekbarColor,
                          settings,
                          isSmallScreen: isSmallScreen,
                          titleFontSize: titleFontSize,
                          authorFontSize: authorFontSize,
                          playButtonCircleSize: playButtonCircleSize,
                          playButtonIconSize: playButtonIconSize,
                          skipButtonSize: skipButtonSize,
                          otherControlsIconSize: otherControlsIconSize,
                          internalSpacing1: internalSpacing1,
                          internalSpacing2: internalSpacing2,
                          actionIconSize: actionIconSize,
                        ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnifiedLyricsCard(
    BuildContext context,
    PlayerProvider player,
    Track track,
    Color seekbarColor,
    SettingsProvider settings,
  ) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bool isSmallScreen = screenHeight < 680;

    final double cardMarginHorizontal = isSmallScreen ? 12.0 : 16.0;
    final double cardMarginBottom = isSmallScreen ? 4.0 : 12.0;

    return Padding(
      padding: EdgeInsets.only(
        left: cardMarginHorizontal,
        right: cardMarginHorizontal,
        bottom: _lyricsExpanded ? cardMarginBottom : 4.0,
        top: 2.0,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06), // translucent white/grey for frosted glass look
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
                width: 0.5,
              ),
            ),
            child: Column(
              children: [
                // Top drag/indicator handle
                Center(
                  child: Container(
                    width: 36,
                    height: 5,
                    margin: const EdgeInsets.only(top: 8, bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),
                // Header Row (Spinning CD + Info + Karaoke button)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 4.0,
                  ),
                  child: Row(
                    children: [
                      RotationTransition(
                        turns: _rotationController,
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            image: (track.thumbnailUrl?.isNotEmpty ?? false)
                                ? DecorationImage(
                                    image: CachedNetworkImageProvider(
                                      rewriteThumbnailSize(track.thumbnailUrl, 200),
                                    ),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                            color: (track.thumbnailUrl?.isNotEmpty ?? false)
                                ? null
                                : Colors.grey[800],
                          ),
                          child: Center(
                            child: Container(
                              width: 12,
                              height: 12,
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              track.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              track.author ?? 'Unknown',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.70),
                                fontSize: 12,
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
                          size: 22,
                        ),
                        onPressed: _toggleKaraokeMode,
                        tooltip: 'Karaoke',
                      ),
                    ],
                  ),
                ),
                // Divider line separating header from lyrics
                Container(
                  height: 0.5,
                  color: Colors.white.withOpacity(0.08),
                  margin: const EdgeInsets.only(top: 4, bottom: 4),
                ),
                // Lyrics section
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _resetLyricsExpansionTimer,
                    onPanDown: (_) => _resetLyricsExpansionTimer(),
                    child: (player.isLoadingLyrics || player.lyrics != null)
                        ? ValueListenableBuilder<Duration>(
                            valueListenable: player.positionNotifier,
                            builder: (_, pos, __) {
                              final effectivePos = _lyricsScrollPaused &&
                                      _frozenPositionMs != null
                                  ? Duration(milliseconds: _frozenPositionMs!)
                                  : pos;
                              return Opacity(
                                opacity: _lyricsScrollPaused ? 0.5 : 1.0,
                                child: SyncedLyricsWidget(
                                  lyricsText: player.lyrics ?? '',
                                  isLoading: player.isLoadingLyrics,
                                  position: Duration(
                                    milliseconds: effectivePos.inMilliseconds +
                                        player.lyricsSyncOffsetMs,
                                  ),
                                  karaokeMode: false,
                                  autoScroll: !_lyricsScrollPaused,
                                  bottomPadding: 24.0,
                                  topPadding: 24.0,
                                  selectionMode: _lyricsSelectionMode,
                                  selectedIndices: _selectedLyricIndices,
                                  onLineToggled: _toggleLyricSelection,
                                  onLineLongPressed: _enterSelectionMode,
                                  onSeek: (time) {
                                    _resetLyricsExpansionTimer();
                                    player.startSeek();
                                    player.endSeek(time);
                                  },
                                ),
                              );
                            },
                          )
                        : Center(
                            child: Text(
                              'No lyrics available',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.54),
                                fontSize: 16,
                              ),
                            ),
                          ),
                  ),
                ),
                // Divider line separating lyrics from controls
                Container(
                  height: 0.5,
                  color: Colors.white.withOpacity(0.08),
                  margin: const EdgeInsets.only(top: 4, bottom: 4),
                ),
                // Bottom controls for lyrics (Scroll Play/Pause, Sync Offset, Playback Speed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _lyricsScrollPaused ? PhosphorIconsFill.play : PhosphorIconsFill.pause,
                          color: Colors.white.withOpacity(0.6),
                          size: 20,
                        ),
                        onPressed: _toggleLyricsScroll,
                        tooltip: _lyricsScrollPaused ? 'Resume scrolling' : 'Pause scrolling',
                        visualDensity: VisualDensity.compact,
                      ),
                      const Expanded(
                        child: LyricsTimingSlider(),
                      ),
                      PlaybackSpeedSelector(
                        iconColor: Colors.white.withOpacity(0.6),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaControlsContent(
    BuildContext context,
    PlayerProvider player,
    Track track,
    Color seekbarColor,
    SettingsProvider settings, {
    required bool isSmallScreen,
    required double titleFontSize,
    required double authorFontSize,
    required double playButtonCircleSize,
    required double playButtonIconSize,
    required double skipButtonSize,
    required double otherControlsIconSize,
    required double internalSpacing1,
    required double internalSpacing2,
    required double actionIconSize,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Track info + favorite (inline)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
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
                          final provider = context.read<PlaylistProvider>();
                          final res = await provider.searchAlbums(track.album!);
                          if (res.isNotEmpty && context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AlbumScreen(albumId: res.first.id),
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
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    GestureDetector(
                      onTap: () async {
                        if (track.author != null) {
                          final provider = context.read<PlaylistProvider>();
                          final artist = await provider.findCorrectArtist(
                            track.author!,
                            track.album,
                          );
                          if (artist != null && context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ArtistScreen(artistId: artist.id),
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
                          fontSize: authorFontSize,
                          fontWeight: FontWeight.normal,
                          color: Colors.white.withOpacity(0.70),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Consumer<PlaylistProvider>(
                builder: (context, pp, _) {
                  final isFav = pp.isFavorite(track.id);
                  return IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      isFav ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                      color: isFav ? const Color(0xFF22C55E) : Colors.white.withOpacity(0.5),
                      size: isSmallScreen ? 18 : 22,
                    ),
                    onPressed: () => pp.toggleFavorite(
                      track,
                      downloadProvider: context.read<DownloadProvider>(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        SizedBox(height: internalSpacing1),
        // Seek bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              SeekbarConnector(
                hasTrack: true,
                activeColor: Colors.white,
                inactiveColor: Colors.white.withOpacity(0.2),
                style: settings.seekbarStyle == 'Gradient'
                    ? SeekbarStyle.gradient
                    : (settings.seekbarStyle == 'Waveform'
                        ? SeekbarStyle.waveform
                        : (settings.seekbarStyle == 'Wavy'
                            ? SeekbarStyle.wavy
                            : SeekbarStyle.minimal)),
                invertColor: false,
                isPlaying: player.isActuallyPlaying,
                onChangeStart: () {
                  _resetLyricsExpansionTimer();
                  player.startSeek();
                },
                onChanged: (v) {
                  _resetLyricsExpansionTimer();
                  final pos = Duration(
                    milliseconds: (v * player.duration.inMilliseconds).round(),
                  );
                  player.updateSeek(pos);
                },
                onChangeEnd: (v) {
                  _resetLyricsExpansionTimer();
                  final pos = Duration(
                    milliseconds: (v * player.duration.inMilliseconds).round(),
                  );
                  player.endSeek(pos);
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ValueListenableBuilder<Duration>(
                      valueListenable: player.positionNotifier,
                      builder: (_, pos, __) => Text(
                        _formatDuration(pos),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 11,
                        ),
                      ),
                    ),
                    ValueListenableBuilder<Duration>(
                      valueListenable: player.durationNotifier,
                      builder: (_, dur, __) => Text(
                        _formatDuration(dur),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: internalSpacing2),
        // Playback controls
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  player.shuffleMode ? PhosphorIconsFill.shuffle : PhosphorIconsBold.shuffle,
                  size: otherControlsIconSize,
                  color: player.shuffleMode ? const Color(0xFF22C55E) : Colors.white.withOpacity(0.5),
                ),
                onPressed: () {
                  _resetLyricsExpansionTimer();
                  player.toggleShuffle();
                },
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  PhosphorIconsFill.skipBack,
                  size: skipButtonSize,
                  color: Colors.white,
                ),
                onPressed: player.currentIndex > 0
                    ? () {
                        _resetLyricsExpansionTimer();
                        player.previous();
                      }
                    : null,
              ),
              GestureDetector(
                onTapDown: (_) => _resetLyricsExpansionTimer(),
                child: _buildPlayPauseButton(player, playButtonCircleSize, playButtonIconSize),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  PhosphorIconsFill.skipForward,
                  size: skipButtonSize,
                  color: Colors.white,
                ),
                onPressed: player.currentIndex + 1 < player.queue.length
                    ? () {
                        _resetLyricsExpansionTimer();
                        player.next();
                      }
                    : null,
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  player.repeatMode == repeat.PlaybackRepeatMode.one
                      ? PhosphorIconsFill.repeatOnce
                      : player.repeatMode != repeat.PlaybackRepeatMode.none
                          ? PhosphorIconsFill.repeat
                          : PhosphorIconsBold.repeat,
                  size: otherControlsIconSize,
                  color: player.repeatMode != repeat.PlaybackRepeatMode.none
                      ? const Color(0xFF22C55E)
                      : Colors.white.withOpacity(0.5),
                ),
                onPressed: () {
                  _resetLyricsExpansionTimer();
                  player.cycleRepeatMode();
                },
              ),
            ],
          ),
        ),
        SizedBox(height: internalSpacing1),
        // Bottom action row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                key: const Key('lyrics-toggle-button'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  PhosphorIcons.scroll,
                  color: _lyricsViewMode == _LyricsViewMode.fullscreen
                      ? const Color(0xFF22C55E)
                      : Colors.white.withOpacity(0.6),
                  size: actionIconSize,
                ),
                onPressed: () {
                  setState(() {
                    if (_lyricsViewMode == _LyricsViewMode.compact) {
                      _lyricsViewMode = _LyricsViewMode.fullscreen;
                      _lyricsExpanded = false;
                      _resetLyricsExpansionTimer();
                    } else {
                      _lyricsViewMode = _LyricsViewMode.compact;
                      _lyricsExpanded = false;
                      _lyricsExpansionTimer?.cancel();
                    }
                  });
                },
              ),
              AudioOutputSelector(iconColor: Colors.white.withOpacity(0.6)),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  PhosphorIconsBold.playlist,
                  color: Colors.white.withOpacity(0.6),
                  size: actionIconSize,
                ),
                onPressed: () {
                  _resetLyricsExpansionTimer();
                  AddToPlaylistModal.show(context, track);
                },
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  _showQueue ? PhosphorIconsFill.queue : PhosphorIconsRegular.queue,
                  color: _showQueue ? const Color(0xFF22C55E) : Colors.white.withOpacity(0.6),
                  size: actionIconSize,
                ),
                onPressed: () {
                  _resetLyricsExpansionTimer();
                  setState(() {
                    _showQueue = !_showQueue;
                    if (_showQueue) {
                      _lyricsViewMode = _LyricsViewMode.compact;
                    }
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionActionBar(PlayerProvider player) {
    final count = _selectedLyricIndices.length;
    return Padding(
      key: const ValueKey('selection_bar'),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cancel selection',
            onPressed: _cancelSelectionMode,
          ),
          Expanded(
            child: Text(
              count == 0
                  ? 'Tap lines to select'
                  : '$count line${count == 1 ? '' : 's'} selected',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          if (count > 0)
            IconButton(
              icon: const Icon(Icons.share_rounded),
              tooltip: 'Share selected lyrics',
              onPressed: () => _openShareSheet(player),
            ),
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

    // Cache so the share sheet can read the lyric words by index.
    _parsedLyricsCache = result;
    return result;
  }

  Widget _buildLyricsHeaderRow(BuildContext context, PlayerProvider player, Track track) {
    final playlistProvider = context.watch<PlaylistProvider>();
    final isFav = playlistProvider.isFavorite(track.id);

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: (track.thumbnailUrl?.isNotEmpty ?? false)
              ? CachedNetworkImage(
                  imageUrl: rewriteThumbnailSize(track.thumbnailUrl, 200),
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(color: Colors.grey[800]),
                )
              : Container(
                  width: 48,
                  height: 48,
                  color: Colors.grey[800],
                  child: const Icon(PhosphorIconsRegular.musicNote, size: 24),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      track.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (track.isExplicit) ...[
                    const SizedBox(width: 6),
                    const ExplicitIcon(),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                track.author ?? 'Unknown',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.70),
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(
            isFav ? PhosphorIconsFill.star : PhosphorIconsRegular.star,
            color: isFav ? Colors.white : Colors.white.withOpacity(0.7),
            size: 22,
          ),
          onPressed: () {
            playlistProvider.toggleFavorite(
              track,
              downloadProvider: context.read<DownloadProvider>(),
            );
          },
        ),
        IconButton(
          icon: Icon(
            PhosphorIconsRegular.dotsThree,
            color: Colors.white.withOpacity(0.7),
            size: 22,
          ),
          onPressed: () => TrackContextMenu.show(context, track),
        ),
      ],
    );
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
                  const SizedBox.shrink(),
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

  Widget _buildInlineQueueView(BuildContext context, PlayerProvider player, Track currentTrack) {
    final queue = player.queue;
    final currentIndex = player.currentIndex;
    final upcoming = (currentIndex >= 0 && currentIndex + 1 < queue.length)
        ? queue.sublist(currentIndex + 1)
        : <Track>[];
    
    // Filter history: recentlyPlayed tracks, excluding current track
    final history = player.recentlyPlayed
        .where((t) => t.id != currentTrack.id)
        .toList();

    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // 1. History Section (if not empty)
          if (history.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'History',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () => player.clearRecentlyPlayed(),
                  child: Text(
                    'Clear',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            ...history.map((t) {
              final idx = history.indexOf(t);
              return Dismissible(
                key: ValueKey('history_${t.id}_$idx'),
                direction: DismissDirection.startToEnd,
                background: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 20),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(PhosphorIconsRegular.trash, color: Colors.white),
                ),
                onDismissed: (_) {
                  player.removeFromRecentlyPlayed(t.id);
                },
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: (t.thumbnailUrl?.isNotEmpty ?? false)
                        ? CachedNetworkImage(
                            imageUrl: rewriteThumbnailSize(t.thumbnailUrl, 100),
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(color: Colors.white10),
                          )
                        : Container(
                            width: 40,
                            height: 40,
                            color: Colors.white10,
                            child: const Icon(PhosphorIconsRegular.musicNote),
                          ),
                  ),
                  title: Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    t.author ?? 'Unknown',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: onSurface.withOpacity(0.6), fontSize: 13),
                  ),
                  onTap: () {
                    player.playTrack(t);
                  },
                  onLongPress: () {
                    TrackContextMenu.show(context, t);
                  },
                ),
              );
            }),
            const SizedBox(height: 16),
          ],

          // 2. Currently Playing Track Card (Apple Music style)
          Card(
            color: Colors.white.withOpacity(0.06),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            margin: EdgeInsets.zero,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: (currentTrack.thumbnailUrl?.isNotEmpty ?? false)
                        ? CachedNetworkImage(
                            imageUrl: rewriteThumbnailSize(currentTrack.thumbnailUrl, 200),
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(color: Colors.white10),
                          )
                        : Container(
                            width: 60,
                            height: 60,
                            color: Colors.white10,
                            child: const Icon(PhosphorIconsRegular.musicNote, size: 30),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentTrack.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          currentTrack.author ?? 'Unknown Artist',
                          style: TextStyle(
                            fontSize: 13,
                            color: onSurface.withOpacity(0.6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Consumer<PlaylistProvider>(
                    builder: (context, pp, _) {
                      final isFav = pp.isFavorite(currentTrack.id);
                      return IconButton(
                        icon: Icon(
                          isFav ? PhosphorIconsFill.star : PhosphorIconsRegular.star,
                          color: isFav ? Colors.white : onSurface.withOpacity(0.5),
                        ),
                        onPressed: () => pp.toggleFavorite(
                          currentTrack,
                          downloadProvider: context.read<DownloadProvider>(),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(PhosphorIconsRegular.dotsThree),
                    onPressed: () => TrackContextMenu.show(context, currentTrack),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 3. Action Buttons Row (Shuffle, Repeat, Autoplay [Infinity], CD [Auto DJ mode picker])
          _buildQueueActionsRow(context, player),
          const SizedBox(height: 24),

          // 4. Continue Playing Header
          Text(
            'Continue Playing',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: onSurface,
            ),
          ),
          if (player.activeAutoDJMode != AutoDJMode.off)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'AutoPlaying similar music',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
                ),
              ),
            ),
          const SizedBox(height: 8),

          // 5. Upcoming Tracks list
          if (upcoming.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Text(
                  'End of Queue',
                  style: TextStyle(color: onSurface.withOpacity(0.4)),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: upcoming.length,
              itemBuilder: (context, index) {
                final t = upcoming[index];
                final queueIdx = currentIndex + 1 + index;
                return Dismissible(
                  key: ValueKey('upcoming_${t.id}_$queueIdx'),
                  direction: DismissDirection.startToEnd,
                  background: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 20),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(PhosphorIconsRegular.trash, color: Colors.white),
                  ),
                  onDismissed: (_) {
                    player.removeFromQueue(queueIdx);
                  },
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: (t.thumbnailUrl?.isNotEmpty ?? false)
                          ? CachedNetworkImage(
                              imageUrl: rewriteThumbnailSize(t.thumbnailUrl, 100),
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(color: Colors.white10),
                            )
                          : Container(
                              width: 40,
                              height: 40,
                              color: Colors.white10,
                              child: const Icon(PhosphorIconsRegular.musicNote),
                            ),
                    ),
                    title: Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      t.author ?? 'Unknown',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: onSurface.withOpacity(0.6), fontSize: 13),
                    ),
                    trailing: const Padding(
                      padding: EdgeInsets.only(right: 8.0),
                      child: Icon(PhosphorIconsRegular.equals, size: 20),
                    ),
                    onTap: () {
                      player.playFromQueue(queueIdx);
                    },
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildQueueActionsRow(BuildContext context, PlayerProvider player) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Shuffle: rounded square
        _buildQueueIconButton(
          icon: player.shuffleMode ? PhosphorIconsFill.shuffle : PhosphorIconsRegular.shuffle,
          isActive: player.shuffleMode,
          onTap: () => player.toggleShuffle(),
        ),
        // Repeat: rounded square
        _buildQueueIconButton(
          icon: player.repeatMode == repeat.PlaybackRepeatMode.one
              ? PhosphorIconsFill.repeatOnce
              : player.repeatMode != repeat.PlaybackRepeatMode.none
                  ? PhosphorIconsFill.repeat
                  : PhosphorIconsRegular.repeat,
          isActive: player.repeatMode != repeat.PlaybackRepeatMode.none,
          onTap: () => player.cycleRepeatMode(),
        ),
        // Infinity (Autoplay): pill
        _buildQueuePillButton(
          icon: PhosphorIconsRegular.infinity,
          isActive: player.isAutoDJEnabled,
          onTap: () => player.toggleAutoDJ(),
        ),
        // CD (Auto DJ picker): pill
        _buildQueuePillButton(
          icon: PhosphorIconsRegular.disc,
          isActive: false,
          onTap: () => AutoDJModePicker.show(context),
        ),
      ],
    );
  }

  Widget _buildQueueIconButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: isActive ? Colors.black : Colors.white,
          size: 22,
        ),
      ),
    );
  }

  Widget _buildQueuePillButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 48,
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Icon(
          icon,
          color: isActive ? Colors.black : Colors.white,
          size: 24,
        ),
      ),
    );
  }

}
