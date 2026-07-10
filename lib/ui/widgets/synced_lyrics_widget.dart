import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../domain/entities/lyric_line.dart';

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
              fontSize: 18,
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

  Widget _buildLyricsList() {
    return ScrollablePositionedList.builder(
      itemCount: _lyrics.length,
      itemScrollController: _scrollController,
      scrollOffsetController: _scrollOffsetController,
      itemPositionsListener: _itemPositionsListener,
      padding: EdgeInsets.only(bottom: widget.bottomPadding, top: widget.topPadding),
      itemBuilder: (context, index) {
        final line = _lyrics[index];
        final isActive = index == _currentIndex;
        final isPassed = index < _currentIndex;
        final isSelected = widget.selectedIndices.contains(index);

        if (line.words.isEmpty) {
          return const SizedBox(height: 24);
        }

        final double alpha = widget.selectionMode
            ? (isSelected ? 1.0 : 0.35)
            : (isActive ? 1.0 : (isPassed ? 0.3 : 0.4));

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
              horizontal: isSelected ? 12 : 0,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withOpacity(0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(
                      color: Colors.white.withOpacity(0.25),
                      width: 1,
                    )
                  : null,
            ),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              style: TextStyle(
                color: Colors.white.withValues(alpha: alpha),
                fontSize: 32.0,
                fontWeight: FontWeight.w800,
                height: 1.3,
                letterSpacing: -1.0,
              ),
              child: Text(
                line.words,
                textAlign: TextAlign.start,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildKaraoke() {
    final currentLine = _currentIndex >= 0 && _currentIndex < _lyrics.length
        ? _lyrics[_currentIndex].words
        : '';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(anim), child: child),
          ),
          child: Text(
            currentLine,
            key: ValueKey(currentLine),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}
