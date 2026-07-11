import re

with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    content = f.read()

# Replace bottomNavigationBar
bottom_nav_regex = r'(\s*)\],\n\s*\),\n\s*\bottomNavigationBar: _buildMediaControls\(\n\s*context,\n\s*player,\n\s*track,\n\s*seekbarColor,\n\s*settings,\n\s*\),\n\s*\);'
bottom_nav_replacement = r'''\1  Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: _showControls ? 1.0 : 0.0,
                  child: _buildMediaControls(
                    context,
                    player,
                    track,
                    seekbarColor,
                    settings,
                  ),
                ),
              ),
            ),
          ],
        ),
        );'''
content = re.sub(bottom_nav_regex, bottom_nav_replacement, content, count=1)

with open('lib/ui/screens/playing_screen.dart', 'w') as f:
    f.write(content)

print("Layout fixed")
