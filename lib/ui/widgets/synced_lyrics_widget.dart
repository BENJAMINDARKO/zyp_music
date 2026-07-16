import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/lyric_line.dart';

class KaraokeLineSet {
  final LyricLine? previous;
  final LyricLine active;
  final LyricLine? next;

  const KaraokeLineSet({
    required this.previous,
    required this.active,
    required this.next,
  });
}

KaraokeLineSet getKaraokeLines({
  required List<LyricLine> lines,
  required int activeIndex,
}) {
  return KaraokeLineSet(
    previous: activeIndex > 0 ? lines[activeIndex - 1] : null,
    active: lines[activeIndex],
    next: activeIndex < lines.length - 1 ? lines[activeIndex + 1] : null,
  );
}

enum LyricLineVisualState { played, active, next, upcoming }

class BreathingActiveLyric extends StatefulWidget {
  final Widget child;
  const BreathingActiveLyric({super.key, required this.child});

  @override
  State<BreathingActiveLyric> createState() => _BreathingActiveLyricState();
}

class _BreathingActiveLyricState extends State<BreathingActiveLyric>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.012).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) return widget.child;
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}

class SyncedLyricsWidget extends StatefulWidget {
  final String lyricsText;
  final Duration position;
  final bool karaokeMode;
  final bool autoScroll;
  final bool isLoading;
  final double bottomPadding;
  final double topPadding;
  final ValueChanged<Duration>? onSeek;

  // ── Selection mode ────────────────────────────────────────
  /// When true the user can long-press / tap to select lines.
  final bool selectionMode;
  /// Indices of currently-selected lyric lines.
  final Set<int> selectedIndices;
  /// Called when a line is tapped in selection mode.
  final ValueChanged<int>? onLineToggled;
  /// Called when any line is long-pressed (used to *enter* selection mode).
  final ValueChanged<int>? onLineLongPressed;

  const SyncedLyricsWidget({
    super.key,
    required this.lyricsText,
    required this.position,
    this.karaokeMode = false,
    this.autoScroll = true,
    this.isLoading = false,
    this.bottomPadding = 350.0,
    this.topPadding = 8.0,
    this.onSeek,
    this.selectionMode = false,
    this.selectedIndices = const {},
    this.onLineToggled,
    this.onLineLongPressed,
  });

  @override
  State<SyncedLyricsWidget> createState() => _SyncedLyricsWidgetState();
}

class _SyncedLyricsWidgetState extends State<SyncedLyricsWidget> with TickerProviderStateMixin {
  final ItemScrollController _scrollController = ItemScrollController();
  final ScrollOffsetController _scrollOffsetController = ScrollOffsetController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();

  late AnimationController _entranceController;
  late AnimationController _pulseController;

  late Animation<double> _dot1OpacityAnimation;
  late Animation<double> _dot2OpacityAnimation;
  late Animation<double> _dot3OpacityAnimation;
  late Animation<double> _dotsFadeOutAnimation;
  late Animation<double> _dotsTranslateAnimation;
  late Animation<double> _lyricsFadeInAnimation;
  late Animation<double> _lyricsTranslateAnimation;

  List<LyricLine> _lyrics = [];
  bool _isSynced = false;
  int _currentIndex = -1;

  @override
  void initState() {
    super.initState();
    
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _pulseController.repeat(reverse: true);

    // Timeline mapping:
    // Dot 1 fades in from 0 to 200ms (0.0 to 0.1)
    _dot1OpacityAnimation = Tween<double>(begin: 0.0, end: 0.6).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.1, curve: Curves.easeIn),
      ),
    );

    // Dot 2 fades in from 400ms to 600ms (0.2 to 0.3)
    _dot2OpacityAnimation = Tween<double>(begin: 0.0, end: 0.6).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.2, 0.3, curve: Curves.easeIn),
      ),
    );

    // Dot 3 fades in from 800ms to 1000ms (0.4 to 0.5)
    _dot3OpacityAnimation = Tween<double>(begin: 0.0, end: 0.6).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.4, 0.5, curve: Curves.easeIn),
      ),
    );

    // Dots scroll up and fade out from 1400ms to 2000ms (0.7 to 1.0)
    _dotsFadeOutAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
      ),
    );

    _dotsTranslateAnimation = Tween<double>(begin: 0.0, end: -40.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
      ),
    );

    // Lyric first line arrives from 1600ms to 2000ms (0.8 to 1.0)
    _lyricsFadeInAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.8, 1.0, curve: Curves.easeIn),
      ),
    );

    _lyricsTranslateAnimation = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.8, 1.0, curve: Curves.easeOut),
      ),
    );

    _entranceController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (_currentIndex != -1) {
          _scrollToIndex(_currentIndex);
        }
      }
    });

    _parseLyrics();

    if (widget.isLoading) {
      _entranceController.animateTo(0.6, duration: const Duration(milliseconds: 1200));
    } else {
      _entranceController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SyncedLyricsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (oldWidget.lyricsText != widget.lyricsText) {
      _parseLyrics();
      if (!widget.isLoading) {
        _entranceController.forward(from: 0.0);
      }
    }

    if (oldWidget.isLoading && !widget.isLoading) {
      // Finished loading: transition from dots to lyrics
      if (_entranceController.value < 0.6) {
        _entranceController.animateTo(1.0);
      } else {
        _entranceController.forward();
      }
    } else if (!widget.isLoading && oldWidget.isLoading != widget.isLoading) {
      // Re-trigger if transitioned in a different state
      _entranceController.forward(from: 0.0);
    }

    if (_isSynced && oldWidget.position != widget.position) {
      _updateCurrentIndex();
    } else if (widget.autoScroll && !oldWidget.autoScroll && _currentIndex != -1) {
      _scrollToIndex(_currentIndex);
    }
  }

  void _parseLyrics() {
    final lines = widget.lyricsText.split('\n');
    final regex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');
    
    _lyrics.clear();
    _isSynced = false;
    _currentIndex = -1;

    for (var line in lines) {
      final match = regex.firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        
        String msStr = match.group(3)!;
        if (msStr.length == 2) msStr += '0';
        final milliseconds = int.parse(msStr);
        
        final text = match.group(4)!.trim();
        
        final time = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );
        
        _lyrics.add(LyricLine(time: time, words: text));
        _isSynced = true;
      }
    }
    
    if (!_isSynced) {
      for (var line in lines) {
        if (line.trim().isNotEmpty) {
          _lyrics.add(LyricLine(time: Duration.zero, words: line.trim()));
        }
      }
    }
  }

  void _updateCurrentIndex() {
    if (_lyrics.isEmpty) return;

    int newIndex = -1;
    for (int i = 0; i < _lyrics.length; i++) {
      if (widget.position >= _lyrics[i].time) {
        newIndex = i;
      } else {
        break;
      }
    }

    if (newIndex != _currentIndex && newIndex != -1) {
      setState(() {
        _currentIndex = newIndex;
      });
      if (widget.autoScroll) {
        _scrollToIndex(newIndex);
      }
    }
  }

  void _scrollToIndex(int index) {
    if (widget.autoScroll && _entranceController.value >= 1.0 && _scrollController.isAttached) {
      _scrollController.scrollTo(
        index: index,
        alignment: index == 0 ? 0.0 : 0.25,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return _buildDotsEntrance();
    }

    if (_lyrics.isEmpty) {
      return Center(
        child: Text(
          'Lyrics not available',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontSize: 18),
        ),
      );
    }

    if (!_isSynced) {
      return AnimatedBuilder(
        animation: _entranceController,
        builder: (context, child) {
          if (_entranceController.value < 0.8) return _buildDotsEntrance();
          final opacity = _lyricsFadeInAnimation.value;
          return Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(0, _lyricsTranslateAnimation.value),
              child: child,
            ),
          );
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 200, top: 8),
          child: Text(
            widget.lyricsText,
            style: TextStyle(
              fontSize: 13,
              height: 1.8,
              fontWeight: FontWeight.normal,
            ),
            textAlign: TextAlign.start,
          ),
        ),
      );
    }

    return Stack(
      children: [
        // Dots entrance layer
        AnimatedBuilder(
          animation: _entranceController,
          builder: (context, child) {
            if (_entranceController.value >= 1.0) return const SizedBox.shrink();
            return _buildDotsEntrance();
          },
        ),
        
        // Lyrics layer
        AnimatedBuilder(
          animation: _entranceController,
          builder: (context, child) {
            if (_entranceController.value < 0.8) return const SizedBox.shrink();
            final opacity = _lyricsFadeInAnimation.value;
            return Opacity(
              opacity: opacity,
              child: Transform.translate(
                offset: Offset(0, _lyricsTranslateAnimation.value),
                child: child,
              ),
            );
          },
          child: widget.karaokeMode ? _buildKaraoke() : _buildLyricsList(),
        ),
      ],
    );
  }

  Widget _buildDotsEntrance() {
    return AnimatedBuilder(
      animation: _entranceController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _dotsTranslateAnimation.value),
          child: child,
        );
      },
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildDot(_dot1OpacityAnimation),
            const SizedBox(height: 12),
            _buildDot(_dot2OpacityAnimation),
            const SizedBox(height: 12),
            _buildDot(_dot3OpacityAnimation),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(Animation<double> opacityAnimation) {
    return AnimatedBuilder(
      animation: Listenable.merge([opacityAnimation, _pulseController]),
      builder: (context, child) {
        final opacity = opacityAnimation.value * _dotsFadeOutAnimation.value;
        if (opacity <= 0.0) return const SizedBox.shrink();
        final scale = 1.0 + 0.2 * _pulseController.value;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }

  LyricLineVisualState _visualState(int index) {
    if (index == _currentIndex) return LyricLineVisualState.active;
    if (index < _currentIndex) return LyricLineVisualState.played;
    if (index == _currentIndex + 1) return LyricLineVisualState.next;
    return LyricLineVisualState.upcoming;
  }

  TextStyle _lyricTextStyle(LyricLineVisualState state) {
    switch (state) {
      case LyricLineVisualState.played:
        return TextStyle(
          color: Colors.white.withOpacity(0.22),
          fontSize: 24,
          fontWeight: FontWeight.w900,
          height: 1.12,
          letterSpacing: -0.8,
        );
      case LyricLineVisualState.active:
        return TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.w900,
          height: 1.12,
          letterSpacing: -0.9,
          shadows: const [
            Shadow(
              color: ZypAuroraColors.cyan,
              blurRadius: 26,
            ),
            Shadow(
              color: Colors.black54,
              blurRadius: 34,
              offset: Offset(0, 8),
            ),
          ],
        );
      case LyricLineVisualState.next:
        return TextStyle(
          color: Colors.white.withOpacity(0.50),
          fontSize: 24,
          fontWeight: FontWeight.w900,
          height: 1.12,
          letterSpacing: -0.8,
        );
      case LyricLineVisualState.upcoming:
        return TextStyle(
          color: Colors.white.withOpacity(0.30),
          fontSize: 24,
          fontWeight: FontWeight.w900,
          height: 1.12,
          letterSpacing: -0.8,
        );
    }
  }

  Widget _buildLyricLine(int index) {
    final line = _lyrics[index];
    final state = _visualState(index);
    final isSelected = widget.selectedIndices.contains(index);

    if (line.words.isEmpty) return const SizedBox(height: 24);

    final selectionAlpha = isSelected ? 1.0 : 0.35;

    Widget textWidget = AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      style: widget.selectionMode
          ? TextStyle(
              color: Colors.white.withOpacity(selectionAlpha),
              fontSize: 21,
              fontWeight: FontWeight.w800,
              height: 1.4,
              letterSpacing: -0.5,
            )
          : _lyricTextStyle(state),
      child: Text(
        line.words,
        textAlign: TextAlign.start,
        softWrap: true,
      ),
    );

    if (state == LyricLineVisualState.active && !widget.selectionMode) {
      textWidget = BreathingActiveLyric(child: textWidget);
    }

    if (state == LyricLineVisualState.played && !widget.selectionMode) {
      textWidget = Opacity(
        opacity: 0.22,
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 0.15, sigmaY: 0.15),
          child: textWidget,
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        if (widget.selectionMode) {
          widget.onLineToggled?.call(index);
        } else {
          widget.onSeek?.call(line.time);
        }
      },
      onLongPress: () => widget.onLineLongPressed?.call(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 12 : 8,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: Colors.white.withOpacity(0.25), width: 1)
              : null,
        ),
        child: textWidget,
      ),
    );
  }

  Widget _buildLyricsList() {
    return ScrollablePositionedList.builder(
      itemCount: _lyrics.length,
      itemScrollController: _scrollController,
      scrollOffsetController: _scrollOffsetController,
      itemPositionsListener: _itemPositionsListener,
      padding: EdgeInsets.only(bottom: widget.bottomPadding, top: widget.topPadding),
      itemBuilder: (context, index) => _buildLyricLine(index),
    );
  }

  Widget _buildKaraoke() {
    final lineSet = getKaraokeLines(lines: _lyrics, activeIndex: _currentIndex);
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (lineSet.previous != null)
              Text(
                lineSet.previous!.words,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  height: 1.15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            if (lineSet.previous != null) const SizedBox(height: 32),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.08),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: BreathingKaraokeLine(
                key: ValueKey('karaoke-active-${lineSet.active.time.inMilliseconds}'),
                child: Text(
                  lineSet.active.words,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    height: 1.12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.0,
                    shadows: [
                      Shadow(
                        color: ZypAuroraColors.cyan,
                        blurRadius: 32,
                      ),
                      Shadow(
                        color: ZypAuroraColors.pink,
                        blurRadius: 18,
                      ),
                      Shadow(
                        color: Colors.black,
                        blurRadius: 34,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (lineSet.next != null) const SizedBox(height: 32),
            if (lineSet.next != null)
              Text(
                lineSet.next!.words,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  height: 1.15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class BreathingKaraokeLine extends StatefulWidget {
  final Widget child;
  const BreathingKaraokeLine({super.key, required this.child});

  @override
  State<BreathingKaraokeLine> createState() => _BreathingKaraokeLineState();
}

class _BreathingKaraokeLineState extends State<BreathingKaraokeLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) return widget.child;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final t = _animation.value;
        return Transform.translate(
          offset: Offset(0, -2 * t),
          child: Transform.scale(
            scale: 1.0 + (0.018 * t),
            child: widget.child,
          ),
        );
      },
    );
  }
}
