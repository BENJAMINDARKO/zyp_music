import 'dart:math';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../domain/entities/lyric_line.dart';

class SyncedLyricsWidget extends StatefulWidget {
  final String lyricsText;
  final Duration position;
  final Color activeColor;

  const SyncedLyricsWidget({
    super.key,
    required this.lyricsText,
    required this.position,
    required this.activeColor,
  });

  @override
  State<SyncedLyricsWidget> createState() => _SyncedLyricsWidgetState();
}

class _SyncedLyricsWidgetState extends State<SyncedLyricsWidget> {
  final ItemScrollController _scrollController = ItemScrollController();
  final ScrollOffsetController _scrollOffsetController = ScrollOffsetController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();

  List<LyricLine> _lyrics = [];
  bool _isSynced = false;
  int _currentIndex = -1;

  @override
  void initState() {
    super.initState();
    _parseLyrics();
  }

  @override
  void didUpdateWidget(covariant SyncedLyricsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyricsText != widget.lyricsText) {
      _parseLyrics();
    }
    if (_isSynced && oldWidget.position != widget.position) {
      _updateCurrentIndex();
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
        
        // Handle both .xx and .xxx milliseconds formats safely
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
    
    // If we didn't find any timestamps, just create one big line or split by newline
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
      _scrollToIndex(newIndex);
    }
  }

  void _scrollToIndex(int index) {
    if (_scrollController.isAttached) {
      _scrollController.scrollTo(
        index: max(0, index - 2), // Keep active line roughly in the middle
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_lyrics.isEmpty) {
      return const Center(
        child: Text(
          'No lyrics available',
          style: TextStyle(color: Colors.white54, fontSize: 18),
        ),
      );
    }

    if (!_isSynced) {
      return SingleChildScrollView(
        child: Text(
          widget.lyricsText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            height: 1.8,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.start,
        ),
      );
    }

    return ScrollablePositionedList.builder(
      itemCount: _lyrics.length,
      itemScrollController: _scrollController,
      scrollOffsetController: _scrollOffsetController,
      itemPositionsListener: _itemPositionsListener,
      padding: const EdgeInsets.only(bottom: 200, top: 40),
      itemBuilder: (context, index) {
        final line = _lyrics[index];
        final isActive = index == _currentIndex;
        final isPassed = index < _currentIndex;
        
        if (line.words.isEmpty) {
          return const SizedBox(height: 24);
        }

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            line.words,
            style: TextStyle(
              color: isActive
                  ? widget.activeColor
                  : (isPassed ? Colors.white.withOpacity(0.4) : Colors.white24),
              fontSize: isActive ? 26 : 22,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
              height: 1.4,
            ),
            textAlign: TextAlign.start,
          ),
        );
      },
    );
  }
}
