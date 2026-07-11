import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/lyric_line.dart';
import '../../presentation/providers/player_provider.dart';

class SingleLineLyricsWidget extends StatelessWidget {
  const SingleLineLyricsWidget({super.key});

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<PlayerProvider>(
      builder: (context, player, _) {
        final lyricsText = player.lyrics;
        if (lyricsText == null || lyricsText.trim().isEmpty) {
          return const SizedBox.shrink();
        }

        final lyrics = _parseLyrics(lyricsText);
        if (lyrics.isEmpty) {
          return const SizedBox.shrink();
        }

        // Subscribe to position updates so the active line advances
        // during playback without requiring a full Consumer rebuild.
        return ValueListenableBuilder<Duration>(
          valueListenable: player.positionNotifier,
          builder: (context, position, _) {
            final activeLine = _findActiveLine(lyrics, position);

            if (activeLine == null) {
              return const SizedBox.shrink();
            }

            final screenHeight = MediaQuery.of(context).size.height;
            final bool isSmallScreen = screenHeight < 680;
            final double lyricFontSize = isSmallScreen ? 15.0 : 20.0;

            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeIn,
              switchOutCurve: Curves.easeOut,
              layoutBuilder: (currentChild, previousChildren) {
                return currentChild ?? const SizedBox.shrink();
              },
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: Container(
                key: ValueKey('single-lyric-${activeLine.words}'),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  activeLine.words,
                  key: ValueKey('lyric-text-${activeLine.time.inMilliseconds}'),
                  textAlign: TextAlign.left,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w400,
                    color: theme.colorScheme.onSurface,
                    fontSize: lyricFontSize,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
