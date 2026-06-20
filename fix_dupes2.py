with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    lines = f.readlines()

del lines[81:99]

with open('lib/ui/screens/playing_screen.dart', 'w') as f:
    f.writelines(lines)
