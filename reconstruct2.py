import re

with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    content = f.read()

# 1. Add _showControls and _hideControlsTimer to _PlayingScreenState
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

# 3. Add GestureDetector for resetting timer
gesture_vars = '''          child: GestureDetector(
            onTap: _resetHideControlsTimer,
            onPanDown: (_) => _resetHideControlsTimer(),
            child: Stack('''
content = re.sub(r'          child: InkWell\(\n            onTap: \(\) {\n              // Optionally toggle controls visibility\n            },\n            child: Stack\(', gesture_vars, content, count=1)

# 4. Find and remove LyricsTimingSlider
lyrics_slider_match = re.search(r'(\s*// Lyrics timing slider \+ pause/resume \(visible only in State B\)\n\s*Row\(\n\s*children: \[\n.*?const Expanded\(child: LyricsTimingSlider\(\)\),\n\s*\],\n\s*\),\n)', content, re.DOTALL)
if lyrics_slider_match:
    lyrics_slider_block = lyrics_slider_match.group(1)
    content = content.replace(lyrics_slider_block, '')
else:
    print("Could not find LyricsTimingSlider block")
    lyrics_slider_block = ""

# 5. Find and remove Track info
track_info_match = re.search(r'(\s*// Track info \+ favorite \(inline\)\n\s*Padding\(\n\s*padding: const EdgeInsets\.symmetric\(horizontal: 24\),\n\s*child: Row\(\n\s*crossAxisAlignment: CrossAxisAlignment\.center,\n.*?pp\.toggleFavorite\(\n\s*track,\n\s*downloadProvider: context\n\s*\.read<DownloadProvider>\(\),\n\s*\),\n\s*\);\n\s*},\n\s*\),\n\s*\],\n\s*\),\n\s*\),\n)', content, re.DOTALL)
if track_info_match:
    track_info_block = track_info_match.group(1)
    content = content.replace(track_info_block, '')
else:
    print("Could not find Track info block")
    track_info_block = ""

# 6. Change bottomNavigationBar to Stack Positioned overlay
# The bottomNavigationBar block is near the end of the Scaffold.
# Scaffold has body: SafeArea(child: Stack(...))
# Wait, currently the code has Scaffold(..., body: SafeArea(child: InkWell(child: Stack(children: [ Positioned.fill(child: Column(...)) ]))))
# Actually, let's see how the scaffold is defined now.
