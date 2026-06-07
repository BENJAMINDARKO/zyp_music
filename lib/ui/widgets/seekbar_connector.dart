import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/providers/player_provider.dart';
import 'custom_audio_seekbar.dart';

/// Single canonical bridge between [PlayerProvider]'s high-frequency
/// position/buffer notifiers and the visual [CustomAudioSeekbar].
///
/// The previous architecture wrapped every seekbar call-site in a
/// `Consumer<PlayerProvider>`, which forced every widget inside the
/// consumer — track title, album art, time labels, play/pause icon,
/// dominant color — to rebuild on every audio frame (multiple times
/// per second). This connector subscribes only to the two
/// `ValueNotifier<Duration>` streams (`positionNotifier` and
/// `bufferedPositionNotifier`), so the seekbar is the only widget
/// in the tree that repaints while the user is listening. Discrete
/// state changes (play/pause, track change, processing-state flip)
/// still propagate through the main [ChangeNotifier] channel for the
/// surrounding widgets.
///
/// `hasTrack` is the empty-state guard supplied by the parent. When
/// `false`, the connector renders a zero-progress bar instead of
/// attempting a division against a zero duration, which would
/// produce a NaN ratio. The parent already knows whether a track is
/// loaded (e.g. `isEmptyState` in the bottom-player), so the
/// connector stays agnostic of the [PlayerProvider] API surface for
/// "do I have something to show?".
///
/// Drag lifecycle is forwarded verbatim to the parent so the
/// provider can maintain the `_isSeeking` lock that suppresses
/// stream updates during a user gesture. See
/// [PlayerProvider.startSeek] / [PlayerProvider.updateSeek] /
/// [PlayerProvider.endSeek].
class SeekbarConnector extends StatelessWidget {
  final bool hasTrack;
  final Color activeColor;
  final Color? inactiveColor;
  final SeekbarStyle style;
  final bool invertColor;
  final bool isPlaying;
  final VoidCallback? onChangeStart;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  const SeekbarConnector({
    super.key,
    required this.hasTrack,
    required this.activeColor,
    this.inactiveColor,
    this.style = SeekbarStyle.minimal,
    this.invertColor = false,
    this.isPlaying = false,
    this.onChangeStart,
    this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerProvider>();

    return ValueListenableBuilder<Duration>(
      valueListenable: player.positionNotifier,
      builder: (_, position, _) => ValueListenableBuilder<Duration>(
        valueListenable: player.bufferedPositionNotifier,
        builder: (_, buffered, _) {
          // Read the duration getter at builder time so a track
          // change picks up the new denominator the next time the
          // position or buffer stream emits (which happens
          // immediately after `_startPolling` in `playTrack`).
          final duration = player.duration;
          final durationMs = duration.inMilliseconds;
          if (!hasTrack || durationMs == 0) {
            return CustomAudioSeekbar(
              value: 0,
              secondaryValue: 0,
              activeColor: activeColor,
              inactiveColor: inactiveColor ?? Colors.white24,
              style: style,
              invertColor: invertColor,
              isPlaying: isPlaying,
              onChangeStart: onChangeStart,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            );
          }
          return CustomAudioSeekbar(
            value: (position.inMilliseconds / durationMs).clamp(0.0, 1.0),
            secondaryValue: (buffered.inMilliseconds / durationMs).clamp(
              0.0,
              1.0,
            ),
            activeColor: activeColor,
            inactiveColor: inactiveColor ?? Colors.white24,
            style: style,
            invertColor: invertColor,
            isPlaying: isPlaying,
            onChangeStart: onChangeStart,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          );
        },
      ),
    );
  }
}
