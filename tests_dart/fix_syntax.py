import re

with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    lines = f.readlines()

# Delete lines 496 and 497 (0-indexed 495, 496)
del lines[495:497]

with open('lib/ui/screens/playing_screen.dart', 'w') as f:
    f.writelines(lines)
