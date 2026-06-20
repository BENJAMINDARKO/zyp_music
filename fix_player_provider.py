import re

with open('lib/presentation/providers/player_provider.dart', 'r') as f:
    content = f.read()

# Fix 1055 _autoDJMode
content = content.replace('if (_autoDJMode != AutoDJMode.off) {', 'if (_baseAutoDJMode != AutoDJMode.off || _smartAutoDJMode != AutoDJMode.off) {')

# Remove duplicate queueManager
content = re.sub(r'  QueueManager\? get queueManager => _queueManager;\n+', '  QueueManager? get queueManager => _queueManager;\n', content)

# _autoDJMode at 1159, 1160 is in setAutoDJMode. We need to remove setAutoDJMode entirely.
# Let's find setAutoDJMode and replace it.
pattern = r'  Future<ColdStartResult> setAutoDJMode\(AutoDJMode mode\) async \{.*?\n  \}'
content = re.sub(pattern, '', content, flags=re.DOTALL)

with open('lib/presentation/providers/player_provider.dart', 'w') as f:
    f.write(content)

