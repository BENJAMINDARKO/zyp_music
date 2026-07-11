import re

with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    content = f.read()

target = """          bottomNavigationBar: _buildMediaControls(
            context,
            player,
            track,
            seekbarColor,
            settings,
          ),
        );"""

replacement = """          Positioned(
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
        );"""

content = content.replace(target, replacement)

with open('lib/ui/screens/playing_screen.dart', 'w') as f:
    f.write(content)

print("Layout fixed safely")
