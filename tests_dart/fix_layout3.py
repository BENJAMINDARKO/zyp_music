import re

with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    content = f.read()

# 1. Add Timer variables and methods
state_vars = '''  bool _lyricsScrollPaused = false;
  int? _frozenPositionMs;

  bool _showControls = true;
  Timer? _hideControlsTimer;

  void _resetHideControlsTimer() {
    setState(() {
      _showControls = true;
    });
    _hideControlsTimer?.cancel();
    if (_lyricsViewMode == _LyricsViewMode.fullscreen) {
      _hideControlsTimer = Timer(const Duration(seconds: 10), () {
        if (mounted) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  void _toggleLyricsScroll() {'''
content = re.sub(r'  bool _lyricsScrollPaused = false;\n  int\? _frozenPositionMs;\n\n  void _toggleLyricsScroll\(\) {', state_vars, content, count=1)

# 2. Add dispose cancellation
dispose_vars = '''  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _visibilityProvider?.show();'''
content = re.sub(r'  @override\n  void dispose\(\) {\n    _visibilityProvider\?\.show\(\);', dispose_vars, content, count=1)

# 3. Find LyricsTimingSlider block
lyrics_slider_match = re.search(r'(\s*// Lyrics timing slider \+ pause/resume \(visible only in State B\)\n\s*Row\(\n\s*children: \[\n\s*IconButton\(\n\s*icon: Icon\(\n\s*_lyricsScrollPaused\n\s*\? PhosphorIconsFill\.play\n\s*: PhosphorIconsFill\.pause,\n\s*color: Theme\.of\(context\)\.colorScheme\.onSurface,\n\s*\),\n\s*onPressed: _toggleLyricsScroll,\n\s*tooltip: _lyricsScrollPaused\n\s*\? \'Resume scrolling\'\n\s*: \'Pause scrolling\',\n\s*\),\n\s*const Expanded\(child: LyricsTimingSlider\(\)\),\n\s*\],\n\s*\),\n)', content, re.DOTALL)
if lyrics_slider_match:
    lyrics_slider_block = lyrics_slider_match.group(1)
    content = content.replace(lyrics_slider_block, '')
else:
    print("WARNING: Could not find LyricsTimingSlider block")
    lyrics_slider_block = ""

# 4. Find Track info block
track_info_match = re.search(r'(\s*// Track info \+ favorite \(inline\)\n\s*Padding\(\n\s*padding: const EdgeInsets\.symmetric\(horizontal: 24\),\n\s*child: Row\(\n\s*crossAxisAlignment: CrossAxisAlignment\.center,\n\s*children: \[\n\s*Expanded\(\n\s*child: Column\(\n\s*crossAxisAlignment: CrossAxisAlignment\.start,\n.*?pp\.toggleFavorite\(\n\s*track,\n\s*downloadProvider: context\n\s*\.read<DownloadProvider>\(\),\n\s*\),\n\s*\);\n\s*},\n\s*\),\n\s*\],\n\s*\),\n\s*\),\n)', content, re.DOTALL)
if track_info_match:
    track_info_block = track_info_match.group(1)
    content = content.replace(track_info_block, '')
else:
    print("WARNING: Could not find Track info block")
    track_info_block = ""

# 5. Fix Stack layout
scaffold_body_regex = r'(        return Scaffold\(\n\s*key: _scaffoldKey,\n\s*extendBody: true,\n\s*backgroundColor: Colors\.transparent,\n\s*body: SafeArea\(\n\s*child: )InkWell\(\n\s*onTap: \(\) {\n\s*// Optionally toggle controls visibility\n\s*},\n\s*child: Stack\(\n\s*children: \[\n\s*Positioned\.fill\(\n\s*child: Column\(\n\s*children: \['
scaffold_body_replacement = r'''\1GestureDetector(
            onTap: _resetHideControlsTimer,
            onPanDown: (_) => _resetHideControlsTimer(),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Column(
                    children: ['''
content = re.sub(scaffold_body_regex, scaffold_body_replacement, content, count=1)

# 6. Change bottomNavigationBar to Stack Positioned overlay
bottom_nav_regex = r'(\s*\],\n\s*\),\n\s*\),\n\s*\],\n\s*\),\n\s*\),\n\s*)bottomNavigationBar: _buildMediaControls\(\n\s*context,\n\s*player,\n\s*track,\n\s*seekbarColor,\n\s*settings,\n\s*\),\n\s*\);\n\s*},\n\s*\);\n\s*}\n\n\s*Widget _buildMediaControls\('
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
      ),
    );
  },
);
  }

  Widget _buildMediaControls('''
content = re.sub(bottom_nav_regex, bottom_nav_replacement, content, count=1)

# 7. Inject blocks into _buildMediaControls
media_controls_regex = r'(Widget _buildMediaControls\([^)]+\)\s*{\s*final dominantColor = player\.dominantColor \?\?\s*Theme\.of\(context\)\.scaffoldBackgroundColor;\s*final iconColor = _contrastingIconColor\(dominantColor\);\s*final secondaryIconColor = iconColor\.withOpacity\(0\.6\);\s*final accentColor = Theme\.of\(context\)\.colorScheme\.primary;\s*return SafeArea\(\s*top: false,\s*child: Column\(\s*mainAxisSize: MainAxisSize\.min,\s*children: \[)'

# Also add padding around the track info so it matches the spacing
if lyrics_slider_block and track_info_block:
    injected_content = r'''\1
          if (_lyricsViewMode == _LyricsViewMode.fullscreen) ...[''' + lyrics_slider_block.replace('\n', '\n  ') + r'''
          ] else ...[''' + track_info_block.replace('\n', '\n  ') + r'''
          ],
          const SizedBox(height: 12),'''
    content = re.sub(media_controls_regex, injected_content, content, count=1)
else:
    print("WARNING: Could not inject blocks into _buildMediaControls")

with open('lib/ui/screens/playing_screen.dart', 'w') as f:
    f.write(content)

print("Layout reconstruction complete.")
