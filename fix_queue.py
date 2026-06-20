import re

with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    content = f.read()

# Add _showQueue state
state_vars = '''  _LyricsViewMode _lyricsViewMode = _LyricsViewMode.compact;
  bool _karaokeMode = false;
  bool _showQueue = false;'''
content = re.sub(r'  _LyricsViewMode _lyricsViewMode = _LyricsViewMode\.compact;\n  bool _karaokeMode = false;', state_vars, content)

# Modify the queue icon button at the bottom to toggle _showQueue
queue_btn_old = '''                IconButton(
                  icon: Icon(
                    PhosphorIconsRegular.queue,
                    color: secondaryIconColor,
                    size: 22,
                  ),
                  onPressed: () => _showUpNextModal(context, player),
                ),'''
queue_btn_new = '''                IconButton(
                  icon: Icon(
                    _showQueue ? PhosphorIconsFill.queue : PhosphorIconsRegular.queue,
                    color: _showQueue ? Theme.of(context).colorScheme.primary : secondaryIconColor,
                    size: 22,
                  ),
                  onPressed: () {
                    setState(() {
                      _showQueue = !_showQueue;
                      if (_showQueue) {
                        _lyricsViewMode = _LyricsViewMode.compact;
                      }
                    });
                  },
                ),'''
content = content.replace(queue_btn_old, queue_btn_new)

# Inject the Queue View in the main layout
# We will replace the State A (boxed album art + lyrics + track info) with either the Queue View or the standard view
state_a_old = '''                    } else ...[
                      // State A: boxed album art → lyric → title/artist

                      // Boxed album art (centered, 70% width, 8px radius)'''

state_a_new = '''                    } else if (_showQueue) ...[
                      // Queue View
                      Expanded(
                        child: _buildInlineQueueView(context, player, track),
                      ),
                    ] else ...[
                      // State A: boxed album art → lyric → title/artist

                      // Boxed album art (centered, 70% width, 8px radius)'''
content = content.replace(state_a_old, state_a_new)

with open('lib/ui/screens/playing_screen.dart', 'w') as f:
    f.write(content)

