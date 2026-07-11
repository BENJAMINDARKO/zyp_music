import re

with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    text = f.read()

# Replace the specific duplicate pattern
pattern = r'      onTap: _resetHideControlsTimer,\n      onPanDown: \(\_\) => _resetHideControlsTimer\(\),\n      onTap:'
text = re.sub(pattern, '      onTap:', text)

# There's also one that might be indented differently:
pattern2 = r'      onTap: _resetHideControlsTimer,\n      onPanDown: \(\_\) => _resetHideControlsTimer\(\),\n                                      onTap:'
text = re.sub(pattern2, '                                      onTap:', text)

with open('lib/ui/screens/playing_screen.dart', 'w') as f:
    f.write(text)
