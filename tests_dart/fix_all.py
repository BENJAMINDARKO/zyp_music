import re

with open('lib/presentation/providers/player_provider.dart', 'r') as f:
    content = f.read()

# Fix unused/duplicate variables
content = re.sub(r'  QueueManager\? get queueManager => _queueManager;\n+', '  QueueManager? get queueManager => _queueManager;\n', content)
content = content.replace('AutoDJMode get baseAutoDJMode => _baseAutoDJMode;\n  AutoDJMode get smartAutoDJMode => _smartAutoDJMode;\n  QueueManager? get queueManager => _queueManager;', 'AutoDJMode get baseAutoDJMode => _baseAutoDJMode;\n  AutoDJMode get smartAutoDJMode => _smartAutoDJMode;')

# Fix _autoDJMode uses in player_provider
content = content.replace('_autoDJMode', '_baseAutoDJMode')

# Since _autoDJMode was replaced with _baseAutoDJMode, let's make sure warmUpNewMode accepts mode correctly
# wait, I already replaced _autoDJMode with _baseAutoDJMode inside the file.
# The only issue is `_queueManager?.setCurrentMode(mode)` which I need to replace with `_queueManager?.setCurrentModes(_baseAutoDJMode, _smartAutoDJMode)`
content = content.replace('_queueManager?.setCurrentMode(_baseAutoDJMode);', '_queueManager?.setCurrentModes(_baseAutoDJMode, _smartAutoDJMode);')

# The unused variables:
content = re.sub(r'  final bool _isColdIdle = false;\n', '', content)
content = re.sub(r'  Future<void> _coldStartForMode\(AutoDJMode mode\) async \{\n.*?\n  \}\n', '', content, flags=re.DOTALL)
content = re.sub(r'      final handlerPlaying = \(_audioHandler as MusicAudioHandler\)\.player\.playing;\n', '', content)
content = re.sub(r'  void synchronizeActiveTrackState\(\) \{\n.*?\n  \}\n', '', content, flags=re.DOTALL)

with open('lib/presentation/providers/player_provider.dart', 'w') as f:
    f.write(content)

