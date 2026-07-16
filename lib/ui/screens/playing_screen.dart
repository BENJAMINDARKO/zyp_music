import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audio_session/audio_session.dart';
import '../../core/theme/app_theme.dart';
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
import '../../presentation/providers/equalizer_provider.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/custom_audio_seekbar.dart';
import '../widgets/seekbar_connector.dart';
import '../widgets/aurora_glass.dart';
import 'artist_screen.dart';
import 'album_screen.dart';
import '../widgets/apple_music_sheet.dart';
import '../widgets/miniplayer_timer_view.dart';
import 'equalizer_screen.dart';
import '../widgets/explicit_icon.dart';
import '../widgets/animated_eq_mini_curve.dart';
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
  bool _showEq = false;


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
    if (_lyricsViewMode == _LyricsViewMode.fullscreen) {
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
                          ? _buildUnifiedLyricsCard(
                              context,
                              player,
                              track,
                              seekbarColor,
                              settings,
                            )
                          : _showQueue
                              ? _buildInlineQueueView(context, player, track)
                              : LayoutBuilder(
                                  builder: (context, constraints) {
                                    final double maxAvailableHeight = constraints.maxHeight;
                                    final bool isSmallScreen = maxAvailableHeight < 300;
                                    final double lyricsBoxHeight = isSmallScreen ? 42.0 : 65.0;
                                    
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
                                          child: Container(
                                            key: const Key('album-art'),
                                            width: artSize,
                                            height: artSize,
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.08),
                                              borderRadius: BorderRadius.circular(30),
                                              border: Border.all(color: Colors.white.withOpacity(0.16)),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.36),
                                                  blurRadius: 70,
                                                  offset: const Offset(0, 24),
                                                ),
                                                BoxShadow(
                                                  color: ZypAuroraColors.cyan.withOpacity(0.13),
                                                  blurRadius: 60,
                                                ),
                                              ],
                                            ),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(22),
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
                        final bool showBottomControls = _showControls || (_lyricsViewMode == _LyricsViewMode.fullscreen);
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

  Widget _buildPlayerEqDrawer(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 12, right: 12),
      child: Consumer<EqualizerProvider>(
        builder: (context, eq, _) {
          final settings = eq.settings;
          final activePreset = eq.presets.firstWhere(
            (p) => p.id == settings.selectedPresetId,
            orElse: () => eq.presets.first,
          );
          final presetName = settings.selectedPresetId == 'custom'
              ? 'Custom'
              : activePreset.name;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  color: Colors.white.withOpacity(0.055),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Equalizer',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$presetName • applies live',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.62),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: (settings.enabled ? ZypAuroraColors.cyan : Colors.grey).withOpacity(0.10),
                        border: Border.all(
                          color: (settings.enabled ? ZypAuroraColors.cyan : Colors.grey).withOpacity(0.14),
                        ),
                      ),
                      child: Text(
                        settings.enabled ? 'ON' : 'OFF',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: settings.enabled ? ZypAuroraColors.cyan : Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 5,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, index) {
                    final preset = eq.presets[index];
                    final isActive = preset.id == settings.selectedPresetId;
                    return GestureDetector(
                      onTap: () => eq.selectPreset(preset.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: isActive
                              ? null
                              : Border.all(color: Colors.white.withOpacity(0.10)),
                          gradient: isActive
                              ? const LinearGradient(
                                  colors: [ZypAuroraColors.cyan, ZypAuroraColors.lime],
                                )
                              : null,
                          color: isActive ? null : Colors.white.withOpacity(0.055),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          preset.name,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: isActive
                                ? const Color(0xFF080711)
                                : Colors.white.withOpacity(0.68),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              AnimatedEqMiniCurve(
                values: settings.bandGains,
                height: 60,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const EqualizerScreen(),
                        ),
                      ),
                      child: Container(
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.10)),
                          color: Colors.white.withOpacity(0.055),
                        ),
                        child: Text(
                          'Pre-amp',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Colors.white.withOpacity(0.72),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const EqualizerScreen(),
                        ),
                      ),
                      child: Container(
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.10)),
                          color: Colors.white.withOpacity(0.055),
                        ),
                        child: Text(
                          'Bands',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Colors.white.withOpacity(0.72),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const EqualizerScreen(),
                        ),
                      ),
                      child: Container(
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            colors: [ZypAuroraColors.cyan, ZypAuroraColors.lime],
                          ),
                        ),
                        child: const Text(
                          'Open full',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF080711),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  void _showMoreTools(BuildContext context, Track track, PlayerProvider player) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (ctx) {
        return SafeArea(
          bottom: true,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 24, top: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(34),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28.0, sigmaY: 28.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF161616).withOpacity(0.70),
                    borderRadius: BorderRadius.circular(34),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.15),
                      width: 1.0,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 58,
                        height: 6,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: Colors.white.withOpacity(0.28),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'More Tools',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.55,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Quick controls for the currently playing track.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.62),
                        ),
                      ),
                      const SizedBox(height: 16),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.2,
                        children: [
                          _buildToolTile(
                            context,
                            icon: '◎',
                            title: 'Audio Output',
                            subtitle: 'Choose device',
                            glowColor: ZypAuroraColors.violet,
                            onTap: () {
                              Navigator.pop(ctx);
                              _showOutputSelector(context);
                            },
                          ),
                          _buildToolTile(
                            context,
                            icon: '1×',
                            title: 'Speed',
                            subtitle: 'Playback speed',
                            glowColor: ZypAuroraColors.pink,
                            onTap: () {
                              Navigator.pop(ctx);
                              _showSpeedSelector(context, player);
                            },
                          ),
                          _buildToolTile(
                            context,
                            icon: '☾',
                            title: 'Sleep Timer',
                            subtitle: 'Stop playback later',
                            glowColor: ZypAuroraColors.peach,
                            onTap: () {
                              Navigator.pop(ctx);
                              showModalBottomSheet(
                                context: context,
                                backgroundColor: Colors.transparent,
                                builder: (_) => const MiniplayerTimerView(),
                              );
                            },
                          ),
                          _buildToolTile(
                            context,
                            icon: '✦',
                            title: 'Auto-DJ',
                            subtitle: 'Tune next songs',
                            glowColor: ZypAuroraColors.lime,
                            onTap: () {
                              Navigator.pop(ctx);
                              AutoDJModePicker.show(context);
                            },
                          ),
                          _buildToolTile(
                            context,
                            icon: '⋯',
                            title: 'More',
                            subtitle: 'Track options',
                            glowColor: const Color(0xFF6EA8FF),
                            onTap: () {
                              Navigator.pop(ctx);
                              TrackContextMenu.show(context, track);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildToolTile(
    BuildContext context, {
    required String icon,
    required String title,
    required String subtitle,
    required Color glowColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
          color: Colors.white.withOpacity(0.06),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: -24,
              top: -24,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: glowColor.withOpacity(0.16),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(
                    icon,
                    style: TextStyle(
                      fontSize: 18,
                      color: glowColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withOpacity(0.54),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showOutputSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: const AudioOutputSelector(iconColor: Colors.white70),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSpeedSelector(BuildContext context, PlayerProvider player) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: PlaybackSpeedSelector(),
              ),
            ),
          ),
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

    final bool isFullscreenLyrics = _lyricsViewMode == _LyricsViewMode.fullscreen;

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
                // Top drag/indicator handle (tappable to minimize)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() {
                      _lyricsViewMode = _LyricsViewMode.compact;
                      _lyricsExpanded = false;
                      _lyricsExpansionTimer?.cancel();
                    });
                  },
                  child: Center(
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
                ),
                // Header Row (Minimize button + Spinning CD + Info + Karaoke button)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 4.0,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          PhosphorIconsRegular.caretDown,
                          color: Colors.white.withOpacity(0.6),
                          size: 24,
                        ),
                        onPressed: () {
                          setState(() {
                            _lyricsViewMode = _LyricsViewMode.compact;
                            _lyricsExpanded = false;
                            _lyricsExpansionTimer?.cancel();
                          });
                        },
                        tooltip: 'Minimize lyrics',
                      ),
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
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
                                  karaokeMode: _karaokeMode,
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
                            : (settings.seekbarStyle == 'Minimal'
                                ? SeekbarStyle.minimal
                                : SeekbarStyle.prism))),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
                      ? ZypAuroraColors.cyan
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
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  _showQueue ? PhosphorIconsFill.queue : PhosphorIconsRegular.queue,
                  color: _showQueue ? ZypAuroraColors.cyan : Colors.white.withOpacity(0.6),
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
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  _showEq ? PhosphorIconsFill.sliders : PhosphorIconsRegular.sliders,
                  color: _showEq ? ZypAuroraColors.cyan : Colors.white.withOpacity(0.6),
                  size: actionIconSize,
                ),
                onPressed: () {
                  _resetLyricsExpansionTimer();
                  setState(() => _showEq = !_showEq);
                },
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  PhosphorIconsRegular.dotsThree,
                  color: Colors.white.withOpacity(0.6),
                  size: actionIconSize,
                ),
                onPressed: () {
                  _resetLyricsExpansionTimer();
                  _showMoreTools(context, track, player);
                },
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: _showEq
              ? _buildPlayerEqDrawer(context)
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 10),
        Center(
          child: AudioOutputSelector(iconColor: Colors.white.withOpacity(0.6)),
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
            isFav ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
            color: isFav ? Colors.redAccent : Colors.white.withOpacity(0.7),
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(34),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.14),
              Colors.white.withOpacity(0.045),
            ],
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.8,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Stack(
                    children: [
                      Positioned(
                        left: -20,
                        top: -20,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: ZypAuroraColors.lime.withOpacity(0.13),
                          ),
                        ),
                      ),
                      Positioned(
                        right: -20,
                        top: -10,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: ZypAuroraColors.cyan.withOpacity(0.16),
                          ),
                        ),
                      ),
                      Positioned(
                        left: -20,
                        bottom: -20,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: ZypAuroraColors.pink.withOpacity(0.14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Continue Playing',
                              style: TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -1.2,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              player.activeAutoDJMode != AutoDJMode.off
                                  ? 'AutoPlaying same genre'
                                  : 'End of manual queue',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.62),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: ZypAuroraColors.cyan.withOpacity(0.10),
                          border: Border.all(color: ZypAuroraColors.cyan.withOpacity(0.18)),
                        ),
                        child: const Text(
                          'Queue',
                          style: TextStyle(
                            color: ZypAuroraColors.cyan,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Consumer<PlaylistProvider>(
                    builder: (context, pp, _) {
                      return CurrentTrackStrip(
                        track: currentTrack,
                        isFavorite: pp.isFavorite(currentTrack.id),
                        onFavoriteToggle: () => pp.toggleFavorite(
                          currentTrack,
                          downloadProvider: context.read<DownloadProvider>(),
                        ),
                        onMoreTap: () => TrackContextMenu.show(context, currentTrack),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  QueueModeButtons(
                    player: player,
                    onQueueToggle: () {
                      setState(() {
                        _showQueue = !_showQueue;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ShaderMask(
                      shaderCallback: (rect) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black,
                          Colors.black,
                          Colors.transparent,
                        ],
                        stops: [0.0, 0.08, 0.92, 1.0],
                      ).createShader(rect),
                      blendMode: BlendMode.dstIn,
                      child: _buildQueueListView(player, upcoming),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueueListView(PlayerProvider player, List<Track> upcoming) {
    final currentIndex = player.currentIndex;
    if (upcoming.isEmpty) {
      return Center(
        child: Text(
          'End of Queue',
          style: TextStyle(color: Colors.white.withOpacity(0.38)),
        ),
      );
    }

    return Theme(
      data: Theme.of(context).copyWith(
        canvasColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),
      child: ReorderableListView.builder(
        padding: EdgeInsets.zero,
        buildDefaultDragHandles: false,
        itemCount: upcoming.length,
        onReorder: (oldIdx, newIdx) {
          if (oldIdx < newIdx) {
            newIdx -= 1;
          }
          final oldQueueIdx = currentIndex + 1 + oldIdx;
          final newQueueIdx = currentIndex + 1 + newIdx;
          player.reorderQueue(oldQueueIdx, newQueueIdx);
        },
        itemBuilder: (context, index) {
          final track = upcoming[index];
          final queueIdx = currentIndex + 1 + index;
          return QueueRow(
            key: ValueKey('redesigned_queue_${track.id}_$queueIdx'),
            track: track,
            index: index,
            glowColor: _getTrackGlowColor(track),
            draggable: true,
            onTap: () {
              player.playFromQueue(queueIdx);
            },
            onDelete: () {
              player.removeFromQueue(queueIdx);
            },
          );
        },
      ),
    );
  }

  Color _getTrackGlowColor(Track track) {
    final hash = track.id.hashCode;
    final colors = [
      ZypAuroraColors.cyan,
      ZypAuroraColors.pink,
      ZypAuroraColors.violet,
      ZypAuroraColors.peach,
      ZypAuroraColors.lime,
    ];
    return colors[hash.abs() % colors.length];
  }

  IconData _getBaseModeIcon(AutoDJMode mode) {
    switch (mode) {
      case AutoDJMode.shuffleLibrary:
        return PhosphorIconsRegular.shuffle;
      case AutoDJMode.similarSongs:
        return PhosphorIconsRegular.waveform;
      case AutoDJMode.sameGenre:
        return PhosphorIconsRegular.musicNotes;
      case AutoDJMode.sameArtist:
        return PhosphorIconsRegular.user;
      default:
        return PhosphorIconsRegular.infinity;
    }
  }

  IconData _getSmartModeIcon(AutoDJMode mode) {
    switch (mode) {
      case AutoDJMode.smartDj:
        return PhosphorIconsRegular.sparkle;
      case AutoDJMode.vibeMatch:
        return PhosphorIconsRegular.activity;
      default:
        return PhosphorIconsRegular.disc;
    }
  }

  String _getAutoplaySubtext(AutoDJMode mode) {
    switch (mode) {
      case AutoDJMode.shuffleLibrary:
        return 'AutoPlaying from library';
      case AutoDJMode.similarSongs:
        return 'AutoPlaying similar music';
      case AutoDJMode.sameGenre:
        return 'AutoPlaying same genre';
      case AutoDJMode.sameArtist:
        return 'AutoPlaying same artist';
      case AutoDJMode.smartDj:
        return 'AutoPlaying Smart DJ mix';
      case AutoDJMode.vibeMatch:
        return 'AutoPlaying Vibe Match mix';
      default:
        return '';
    }
  }





}

// ==========================================
// REDESIGNED QUEUE SUPPORT WIDGETS
// ==========================================

class QueueBoard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badge;
  final Widget child;
  final bool isNested;

  const QueueBoard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.child,
    this.isNested = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isNested) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -1.0,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: ZypAuroraColors.cyan.withOpacity(0.85),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: ZypAuroraColors.cyan.withOpacity(0.10),
                  border: Border.all(color: ZypAuroraColors.cyan.withOpacity(0.18)),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: ZypAuroraColors.cyan,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.14),
            Colors.white.withOpacity(0.045),
          ],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.8,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Stack(
                  children: [
                    Positioned(
                      left: -20,
                      top: -20,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ZypAuroraColors.lime.withOpacity(0.13),
                        ),
                      ),
                    ),
                    Positioned(
                      right: -20,
                      top: -10,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ZypAuroraColors.cyan.withOpacity(0.16),
                        ),
                      ),
                    ),
                    Positioned(
                      left: -20,
                      bottom: -20,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ZypAuroraColors.pink.withOpacity(0.14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -1.2,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.62),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: ZypAuroraColors.cyan.withOpacity(0.10),
                        border: Border.all(color: ZypAuroraColors.cyan.withOpacity(0.18)),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          color: ZypAuroraColors.cyan,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class QueueRow extends StatelessWidget {
  final Track track;
  final int index;
  final Color glowColor;
  final VoidCallback? onTap;
  final bool draggable;
  final VoidCallback? onDelete;

  const QueueRow({
    super.key,
    required this.track,
    required this.index,
    required this.glowColor,
    this.onTap,
    this.draggable = true,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withOpacity(0.085)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.10),
                Colors.white.withOpacity(0.035),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -46,
                bottom: -46,
                child: Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: glowColor.withOpacity(0.13),
                    boxShadow: [
                      BoxShadow(
                        color: glowColor.withOpacity(0.13),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(9),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: onTap,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(17),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.22),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(17),
                          child: (track.thumbnailUrl?.isNotEmpty ?? false)
                              ? CachedNetworkImage(
                                  imageUrl: rewriteThumbnailSize(track.thumbnailUrl, 200),
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => _fallbackCover(),
                                )
                              : _fallbackCover(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: onTap,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              track.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.3,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              track.author ?? 'Unknown Artist',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.62),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (onDelete != null)
                      IconButton(
                        icon: Icon(
                          PhosphorIconsRegular.trash,
                          color: Colors.white.withOpacity(0.4),
                          size: 18,
                        ),
                        onPressed: onDelete,
                      ),
                    if (draggable)
                      ReorderableDragStartListener(
                        index: index,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15),
                            color: Colors.white.withOpacity(0.055),
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                          ),
                          child: const Center(
                            child: Text(
                              '=',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 20,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackCover() {
    return Container(
      color: Colors.white.withOpacity(0.08),
      child: const Center(
        child: Icon(PhosphorIconsRegular.musicNote, color: Colors.white30, size: 24),
      ),
    );
  }
}

class PrismSeekbar extends StatelessWidget {
  const PrismSeekbar({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerProvider>();
    return ValueListenableBuilder<Duration>(
      valueListenable: player.positionNotifier,
      builder: (context, position, _) {
        final duration = player.duration;
        final durationMs = duration.inMilliseconds;
        final progress = durationMs > 0 
            ? (position.inMilliseconds / durationMs).clamp(0.0, 1.0)
            : 0.0;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => player.startSeek(),
          onHorizontalDragUpdate: (details) {
            final box = context.findRenderObject() as RenderBox;
            final width = box.size.width;
            final v = (details.localPosition.dx / width).clamp(0.0, 1.0);
            player.updateSeek(Duration(milliseconds: (v * durationMs).round()));
          },
          onHorizontalDragEnd: (details) {
            player.endSeek(player.positionNotifier.value);
          },
          onTapDown: (details) {
            final box = context.findRenderObject() as RenderBox;
            final width = box.size.width;
            final v = (details.localPosition.dx / width).clamp(0.0, 1.0);
            player.startSeek();
            final target = Duration(milliseconds: (v * durationMs).round());
            player.updateSeek(target);
            player.endSeek(target);
          },
          child: Container(
            height: 24,
            alignment: Alignment.center,
            child: Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: Colors.white.withOpacity(0.13),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: const LinearGradient(
                        colors: [
                          ZypAuroraColors.cyan,
                          ZypAuroraColors.pink,
                          ZypAuroraColors.peach,
                        ],
                      ),
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

class CurrentTrackStrip extends StatelessWidget {
  final Track track;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onMoreTap;

  const CurrentTrackStrip({
    super.key,
    required this.track,
    required this.isFavorite,
    required this.onFavoriteToggle,
    required this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: (track.thumbnailUrl?.isNotEmpty ?? false)
                  ? CachedNetworkImage(
                      imageUrl: rewriteThumbnailSize(track.thumbnailUrl, 200),
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _fallbackCover(),
                    )
                  : _fallbackCover(),
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
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  track.author ?? 'Unknown Artist',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.62),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onFavoriteToggle,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                color: Colors.white.withOpacity(0.055),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: Center(
                child: Icon(
                  isFavorite ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                  color: isFavorite ? ZypAuroraColors.pink : Colors.white70,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onMoreTap,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                color: Colors.white.withOpacity(0.055),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: const Center(
                child: Icon(
                  PhosphorIconsRegular.dotsThree,
                  color: Colors.white70,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackCover() {
    return Container(
      color: Colors.white.withOpacity(0.08),
      child: const Center(
        child: Icon(PhosphorIconsRegular.musicNote, color: Colors.white30, size: 24),
      ),
    );
  }
}

class QueueModeButtons extends StatelessWidget {
  final PlayerProvider player;
  final VoidCallback onQueueToggle;

  const QueueModeButtons({
    super.key,
    required this.player,
    required this.onQueueToggle,
  });

  @override
  Widget build(BuildContext context) {
    final shuffleActive = player.shuffleMode;
    final repeatActive = player.repeatMode != repeat.PlaybackRepeatMode.none;
    final autoDjActive = player.isAutoDJEnabled;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: player.toggleShuffle,
              child: _buildModeBtn(
                isActive: shuffleActive,
                icon: shuffleActive ? PhosphorIconsFill.shuffle : PhosphorIconsRegular.shuffle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: player.cycleRepeatMode,
              child: _buildModeBtn(
                isActive: repeatActive,
                icon: player.repeatMode == repeat.PlaybackRepeatMode.one
                    ? PhosphorIconsFill.repeatOnce
                    : repeatActive
                        ? PhosphorIconsFill.repeat
                        : PhosphorIconsRegular.repeat,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: onQueueToggle,
              child: _buildModeBtn(
                isActive: true,
                icon: PhosphorIconsFill.queue,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () {
                AutoDJModePicker.show(context);
              },
              child: _buildModeBtn(
                isActive: autoDjActive,
                icon: autoDjActive ? PhosphorIconsFill.sparkle : PhosphorIconsRegular.sparkle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeBtn({required bool isActive, required IconData icon}) {
    if (isActive) {
      return Container(
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: [ZypAuroraColors.cyan, ZypAuroraColors.lime],
          ),
          boxShadow: [
            BoxShadow(
              color: ZypAuroraColors.cyan.withOpacity(0.16),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Center(
          child: Icon(icon, color: const Color(0xFF080711), size: 21),
        ),
      );
    } else {
      return Container(
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
          color: Colors.white.withOpacity(0.06),
        ),
        child: Center(
          child: Icon(icon, color: Colors.white.withOpacity(0.72), size: 21),
        ),
      );
    }
  }
}

class PlayerControlCard extends StatelessWidget {
  final Track track;
  final PlayerProvider player;

  const PlayerControlCard({
    super.key,
    required this.track,
    required this.player,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.14),
            Colors.white.withOpacity(0.045),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.4,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.author ?? 'Unknown Artist',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.62),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Consumer<PlaylistProvider>(
                builder: (context, pp, _) {
                  final isFav = pp.isFavorite(track.id);
                  return GestureDetector(
                    onTap: () => pp.toggleFavorite(
                      track,
                      downloadProvider: context.read<DownloadProvider>(),
                    ),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.10)),
                        color: Colors.white.withOpacity(0.06),
                      ),
                      child: Center(
                        child: Icon(
                          isFav ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                          color: isFav ? ZypAuroraColors.pink : Colors.white70,
                          size: 22,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          const PrismSeekbar(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ValueListenableBuilder<Duration>(
                  valueListenable: player.positionNotifier,
                  builder: (_, pos, __) => Text(
                    _formatDuration(pos),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.62),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                ValueListenableBuilder<Duration>(
                  valueListenable: player.durationNotifier,
                  builder: (_, dur, __) => Text(
                    _formatDuration(dur),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.62),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                icon: Icon(
                  player.shuffleMode ? PhosphorIconsFill.shuffle : PhosphorIconsRegular.shuffle,
                  color: player.shuffleMode ? ZypAuroraColors.cyan : Colors.white.withOpacity(0.62),
                ),
                iconSize: 22,
                onPressed: player.toggleShuffle,
              ),
              IconButton(
                icon: const Icon(PhosphorIconsFill.skipBack),
                color: Colors.white,
                iconSize: 24,
                onPressed: player.currentIndex > 0 ? player.previous : null,
              ),
              _buildPlayPauseBtn(player),
              IconButton(
                icon: const Icon(PhosphorIconsFill.skipForward),
                color: Colors.white,
                iconSize: 24,
                onPressed: player.currentIndex + 1 < player.queue.length ? player.next : null,
              ),
              IconButton(
                icon: Icon(
                  player.repeatMode == repeat.PlaybackRepeatMode.one
                      ? PhosphorIconsFill.repeatOnce
                      : player.repeatMode != repeat.PlaybackRepeatMode.none
                          ? PhosphorIconsFill.repeat
                          : PhosphorIconsRegular.repeat,
                  color: player.repeatMode != repeat.PlaybackRepeatMode.none
                      ? ZypAuroraColors.cyan
                      : Colors.white.withOpacity(0.62),
                ),
                iconSize: 22,
                onPressed: player.cycleRepeatMode,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Center(
            child: AudioOutputSelector(iconColor: Colors.white.withOpacity(0.68)),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayPauseBtn(PlayerProvider player) {
    return GestureDetector(
      onTap: player.togglePlayPause,
      child: Container(
        width: 62,
        height: 62,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: player.isBuffering
            ? const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    color: Colors.black,
                    strokeWidth: 3,
                  ),
                ),
              )
            : Icon(
                player.isActuallyPlaying ? PhosphorIconsFill.pause : PhosphorIconsFill.play,
                color: Colors.black,
                size: 26,
              ),
      ),
    );
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
}
