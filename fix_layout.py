import re

with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    content = f.read()

# 1. Extract and remove the LyricsTimingSlider block
lyrics_slider_match = re.search(r'(\s*// Lyrics timing slider \+ pause/resume \(visible only in State B\)\n\s*IgnorePointer\(\n.*?\s*\),\n\s*\),\n)', content, re.DOTALL)
if not lyrics_slider_match:
    print("Could not find LyricsTimingSlider block")
    exit(1)

lyrics_slider_block = lyrics_slider_match.group(1)
content = content.replace(lyrics_slider_block, '')

# 2. Extract and remove the Track info + favorite block
track_info_match = re.search(r'(\s*// Track info \+ favorite \(inline\)\n\s*Padding\(\n.*?\n\s*\),\n\s*\),\n)', content, re.DOTALL)
if not track_info_match:
    print("Could not find Track info block")
    exit(1)

track_info_block = track_info_match.group(1)
content = content.replace(track_info_block, '')

# 3. Inject them into _buildMediaControls
injection_point = r'(Widget _buildMediaControls\([^)]+\)\s*{\s*final dominantColor = player\.dominantColor \?\?\s*Theme\.of\(context\)\.scaffoldBackgroundColor;\s*final iconColor = _contrastingIconColor\(dominantColor\);\s*final secondaryIconColor = iconColor\.withOpacity\(0\.6\);\s*final accentColor = Theme\.of\(context\)\.colorScheme\.primary;\s*return SafeArea\(\s*top: false,\s*child: Column\(\s*mainAxisSize: MainAxisSize\.min,\s*children: \[)'

# We need to construct the new content to inject at the top of _buildMediaControls.
# Note: Since _buildMediaControls is outside of the main build method, it doesn't have access to _lyricsViewMode directly if we pass it as a parameter, OR we can access it if _buildMediaControls is a method of _PlayingScreenState.
# Wait, _buildMediaControls IS a method of _PlayingScreenState! So it can access _lyricsViewMode, _lyricsScrollPaused, _toggleLyricsScroll natively!
# We just need to wrap the injected blocks correctly.

injected_content = r'''\1
          if (_lyricsViewMode == _LyricsViewMode.fullscreen) ...[
''' + lyrics_slider_block.replace('\n', '\n  ') + r'''
          ] else ...[
''' + track_info_block.replace('\n', '\n  ') + r'''
          ],
'''

content = re.sub(injection_point, injected_content, content, count=1)

with open('lib/ui/screens/playing_screen.dart', 'w') as f:
    f.write(content)

print("Refactor complete.")
