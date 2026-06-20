import re

with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    text = f.read()

# 1. Fix player.isShuffleModeEnabled -> player.shuffleMode
text = text.replace('player.isShuffleModeEnabled', 'player.shuffleMode')

# 2. Fix setShuffleModeEnabled -> toggleShuffle()
text = re.sub(r'player\.setShuffleModeEnabled\([^)]+\)', 'player.toggleShuffle()', text)

# 3. Fix setRepeatMode -> cycleRepeatMode()
text = re.sub(r'player\.setRepeatMode\([^)]+\)', 'player.cycleRepeatMode()', text)

# 4. Fix currentTrack.thumbnailUrl -> currentTrack.thumbnailUrl ?? ''
text = text.replace('currentTrack.thumbnailUrl,', '(currentTrack.thumbnailUrl ?? \'\'),')

# 5. Fix upcoming track t.thumbnailUrl -> t.thumbnailUrl ?? ''
text = text.replace('t.thumbnailUrl,', '(t.thumbnailUrl ?? \'\'),')

# 6. Inject the Queue view
old_state_a = r'\),                    \] else \.\.\.\['
new_state_a = r'''),                    ] else if (_showQueue) ...[
                      // Queue View
                      Expanded(
                        child: _buildInlineQueueView(context, player, track),
                      ),
                    ] else ...['''
text = re.sub(old_state_a, new_state_a, text)

with open('lib/ui/screens/playing_screen.dart', 'w') as f:
    f.write(text)
