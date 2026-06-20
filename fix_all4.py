import re

with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    content = f.read()

# Add Timer State
state_target = """  bool _karaokeMode = false;"""
state_replacement = """  bool _karaokeMode = false;

  bool _showControls = true;
  Timer? _hideControlsTimer;

  void _resetHideControlsTimer() {
    setState(() => _showControls = true);
    _hideControlsTimer?.cancel();
    if (_lyricsViewMode == _LyricsViewMode.fullscreen && !_karaokeMode) {
      _hideControlsTimer = Timer(const Duration(seconds: 10), () {
        if (mounted && _lyricsViewMode == _LyricsViewMode.fullscreen) {
          setState(() => _showControls = false);
        }
      });
    }
  }"""
content = content.replace(state_target, state_replacement)

# Also update dispose to cancel timer
dispose_target = """  @override
  void dispose() {"""
dispose_replacement = """  @override
  void dispose() {
    _hideControlsTimer?.cancel();"""
content = content.replace(dispose_target, dispose_replacement)

with open('lib/ui/screens/playing_screen.dart', 'w') as f:
    f.write(content)

print("Applied cleanly")
