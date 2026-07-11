import re

with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    content = f.read()

# Add imports
imports = '''import 'package:flutter/material.dart';
import '../../core/services/vocal_remover_service.dart';'''
content = content.replace("import 'package:flutter/material.dart';", imports, 1)

# Add _vocalSliderVisible to state
state_vars = '''  _LyricsViewMode _lyricsViewMode = _LyricsViewMode.compact;
  bool _karaokeMode = false;
  bool _vocalSliderVisible = false;'''
content = content.replace("  _LyricsViewMode _lyricsViewMode = _LyricsViewMode.compact;\n  bool _karaokeMode = false;", state_vars)

# Inject the waveform icon next to the Karaoke icon. 
# Karaoke icon is in the lyrics header row.
karaoke_icon = '''                        IconButton(
                          icon: Icon(
                            PhosphorIconsFill.microphoneStage,
                            color: _karaokeMode
                                ? const Color(0xFFEAB308)
                                : Theme.of(context).colorScheme.onSurface.withOpacity(0.50),
                          ),
                          onPressed: () {
                            setState(() => _karaokeMode = !_karaokeMode);
                          },
                        ),'''
karaoke_icon_with_vocal = '''                        IconButton(
                          icon: Icon(
                            PhosphorIconsFill.waveform,
                            color: _vocalSliderVisible
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface.withOpacity(0.50),
                          ),
                          onPressed: () {
                            setState(() => _vocalSliderVisible = !_vocalSliderVisible);
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            PhosphorIconsFill.microphoneStage,
                            color: _karaokeMode
                                ? const Color(0xFFEAB308)
                                : Theme.of(context).colorScheme.onSurface.withOpacity(0.50),
                          ),
                          onPressed: () {
                            setState(() => _karaokeMode = !_karaokeMode);
                          },
                        ),'''
content = content.replace(karaoke_icon, karaoke_icon_with_vocal)

# Inject the slider below the song title (in State A).
# Actually, let's put it right above the Seek Bar!
seek_bar = '''          // Seek bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ProgressBar('''

vocal_slider = '''          if (_vocalSliderVisible)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Icon(PhosphorIconsFill.microphone, size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 4,
                        activeTrackColor: Theme.of(context).colorScheme.primary,
                        inactiveTrackColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                        thumbColor: Theme.of(context).colorScheme.primary,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      ),
                      child: Slider(
                        value: VocalRemoverService.vocalAttenuation,
                        onChanged: (val) {
                          setState(() {
                            VocalRemoverService.vocalAttenuation = val;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Seek bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ProgressBar('''
content = content.replace(seek_bar, vocal_slider)

with open('lib/ui/screens/playing_screen.dart', 'w') as f:
    f.write(content)

