import re

with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    lines = f.readlines()

# find duplicate _showControls
start_idx = -1
for i, line in enumerate(lines):
    if line.strip() == "bool _showControls = true;" and i > 60:
        start_idx = i
        break

if start_idx != -1:
    end_idx = start_idx
    for i in range(start_idx, len(lines)):
        if "}" in lines[i] and "_resetHideControlsTimer" in "".join(lines[start_idx:i]):
            # keep looking for the end of the method
            pass
        if "  }" in lines[i] and i > start_idx + 5:
            end_idx = i
            break
    
    del lines[start_idx:end_idx+1]

with open('lib/ui/screens/playing_screen.dart', 'w') as f:
    f.writelines(lines)
