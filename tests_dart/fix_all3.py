import re

with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    content = f.read()

# 1. Replace PlaybackSpeedSelector
content = content.replace("import '../widgets/playback_speed_selector.dart';", "import '../widgets/audio_output_selector.dart';\nimport 'dart:async';")
content = content.replace("PlaybackSpeedSelector(iconColor: secondaryIconColor),", "AudioOutputSelector(iconColor: secondaryIconColor),")
content = content.replace("const PlaybackSpeedSelector(),", "const SizedBox.shrink(),")

# 2. Add Timer State
state_target = """  _LyricsViewMode _lyricsViewMode = _LyricsViewMode.compact;
  bool _karaokeMode = false;
  int? _frozenPositionMs;
  bool _lyricsScrollPaused = false;

  @override
  void dispose() {"""
state_replacement = """  _LyricsViewMode _lyricsViewMode = _LyricsViewMode.compact;
  bool _karaokeMode = false;
  int? _frozenPositionMs;
  bool _lyricsScrollPaused = false;

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
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();"""
content = content.replace(state_target, state_replacement)

# 3. Add gesture detector
body_target = """        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: ["""
body_replacement = """        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: Colors.transparent,
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _resetHideControlsTimer,
            onPanDown: (_) => _resetHideControlsTimer(),
            child: Stack(
              fit: StackFit.expand,
              children: ["""
content = content.replace(body_target, body_replacement)

# 4. bottomNavigationBar replace
nav_target = """            ],
          ),
          bottomNavigationBar: _buildMediaControls(
            context,
            player,
            track,
            seekbarColor,
            settings,
          ),
        );"""

nav_replacement = """                Positioned(
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
        );"""

content = content.replace(nav_target, nav_replacement)

with open('lib/ui/screens/playing_screen.dart', 'w') as f:
    f.write(content)

print("Applied cleanly")
