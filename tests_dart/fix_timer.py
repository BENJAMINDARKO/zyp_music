import re

with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    content = f.read()

# Add _showControls and timer to state
state_vars = """  _LyricsViewMode _lyricsViewMode = _LyricsViewMode.compact;
  bool _karaokeMode = false;
  int? _frozenPositionMs;
  bool _lyricsScrollPaused = false;
  
  bool _showControls = true;
  Timer? _hideControlsTimer;

  void _resetHideControlsTimer() {
    setState(() => _showControls = true);
    _hideControlsTimer?.cancel();
    if (_lyricsViewMode == _LyricsViewMode.fullscreen && !_karaokeMode) {
      _hideControlsTimer = Timer(const Duration(seconds: 5), () {
        if (mounted && _lyricsViewMode == _LyricsViewMode.fullscreen) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
"""

content = content.replace("""  _LyricsViewMode _lyricsViewMode = _LyricsViewMode.compact;
  bool _karaokeMode = false;
  int? _frozenPositionMs;
  bool _lyricsScrollPaused = false;

  @override
  void dispose() {""", state_vars)

# Call timer on interaction
content = content.replace("GestureDetector(", "GestureDetector(\n      onTap: _resetHideControlsTimer,\n      onPanDown: (_) => _resetHideControlsTimer(),")

with open('lib/ui/screens/playing_screen.dart', 'w') as f:
    f.write(content)

print("Timer added")
