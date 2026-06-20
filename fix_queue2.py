import re

with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    content = f.read()

# Replace the Action Buttons Row
old_action_row = '''          // 2. Action Buttons Row (Shuffle, Repeat, BaseDJ, SmartDJ)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(
                  player.isShuffleModeEnabled ? PhosphorIconsFill.shuffle : PhosphorIconsRegular.shuffle,
                  color: player.isShuffleModeEnabled ? Theme.of(context).colorScheme.primary : onSurface.withOpacity(0.7),
                ),
                onPressed: () => player.setShuffleModeEnabled(!player.isShuffleModeEnabled),
              ),
              IconButton(
                icon: Icon(
                  player.repeatMode == repeat.PlaybackRepeatMode.one
                      ? PhosphorIconsFill.repeatOnce
                      : (player.repeatMode == repeat.PlaybackRepeatMode.all
                          ? PhosphorIconsFill.repeat
                          : PhosphorIconsRegular.repeat),
                  color: player.repeatMode != repeat.PlaybackRepeatMode.none
                      ? Theme.of(context).colorScheme.primary
                      : onSurface.withOpacity(0.7),
                ),
                onPressed: () {
                  final modes = repeat.PlaybackRepeatMode.values;
                  final nextMode = modes[(player.repeatMode.index + 1) % modes.length];
                  player.setRepeatMode(nextMode);
                },
              ),
              AutoDJModePicker(
                currentMode: player.baseAutoDJMode,
                onModeSelected: (m) => player.setBaseAutoDJMode(m),
                isSmart: false,
              ),
              AutoDJModePicker(
                currentMode: player.smartAutoDJMode,
                onModeSelected: (m) => player.setSmartAutoDJMode(m),
                isSmart: true,
              ),
            ],
          ),'''

new_action_row = '''          // 2. Action Buttons Row (Shuffle, Repeat, BaseDJ, SmartDJ)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(
                  player.isShuffleModeEnabled ? PhosphorIconsFill.shuffle : PhosphorIconsRegular.shuffle,
                  color: player.isShuffleModeEnabled ? Theme.of(context).colorScheme.primary : onSurface.withOpacity(0.7),
                ),
                onPressed: () => player.setShuffleModeEnabled(!player.isShuffleModeEnabled),
              ),
              IconButton(
                icon: Icon(
                  player.repeatMode == repeat.PlaybackRepeatMode.one
                      ? PhosphorIconsFill.repeatOnce
                      : (player.repeatMode == repeat.PlaybackRepeatMode.all
                          ? PhosphorIconsFill.repeat
                          : PhosphorIconsRegular.repeat),
                  color: player.repeatMode != repeat.PlaybackRepeatMode.none
                      ? Theme.of(context).colorScheme.primary
                      : onSurface.withOpacity(0.7),
                ),
                onPressed: () {
                  final modes = repeat.PlaybackRepeatMode.values;
                  final nextMode = modes[(player.repeatMode.index + 1) % modes.length];
                  player.setRepeatMode(nextMode);
                },
              ),
              IconButton(
                icon: Icon(
                  player.baseAutoDJMode != AutoDJMode.off ? PhosphorIconsFill.magicWand : PhosphorIconsRegular.magicWand,
                  color: player.baseAutoDJMode != AutoDJMode.off ? Theme.of(context).colorScheme.primary : onSurface.withOpacity(0.7),
                ),
                onPressed: () => AutoDJModePicker.show(context),
              ),
              IconButton(
                icon: Icon(
                  player.smartAutoDJMode != AutoDJMode.off ? PhosphorIconsFill.sparkle : PhosphorIconsRegular.sparkle,
                  color: player.smartAutoDJMode != AutoDJMode.off ? Theme.of(context).colorScheme.primary : onSurface.withOpacity(0.7),
                ),
                onPressed: () => AutoDJModePicker.show(context),
              ),
            ],
          ),'''

content = content.replace(old_action_row, new_action_row)

with open('lib/ui/screens/playing_screen.dart', 'w') as f:
    f.write(content)

