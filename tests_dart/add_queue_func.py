import re

with open('lib/ui/screens/playing_screen.dart', 'r') as f:
    content = f.read()

func = '''
  Widget _buildInlineQueueView(BuildContext context, PlayerProvider player, Track currentTrack) {
    final queue = player.queue;
    final currentIndex = player.currentIndex;
    final upcoming = (currentIndex >= 0 && currentIndex + 1 < queue.length)
        ? queue.sublist(currentIndex + 1)
        : <Track>[];
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Current Track Tile
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                currentTrack.thumbnailUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 48,
                  height: 48,
                  color: Colors.white10,
                  child: const Icon(PhosphorIconsRegular.musicNotes),
                ),
              ),
            ),
            title: Text(
              currentTrack.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Text(
              currentTrack.author ?? 'Unknown Artist',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: onSurface.withOpacity(0.7)),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Consumer<PlaylistProvider>(
                  builder: (context, pp, _) {
                    final isFav = pp.isFavorite(currentTrack.id);
                    return IconButton(
                      icon: Icon(
                        isFav ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                        color: isFav ? onSurface : onSurface.withOpacity(0.5),
                      ),
                      onPressed: () => pp.toggleFavorite(currentTrack, downloadProvider: context.read<DownloadProvider>()),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(PhosphorIconsRegular.dotsThree),
                  onPressed: () => AddToPlaylistModal.show(context, currentTrack),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Action Buttons Row (Shuffle, Repeat, BaseDJ, SmartDJ)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(
                  player.isShuffleModeEnabled ? PhosphorIconsFill.shuffle : PhosphorIconsRegular.shuffle,
                  color: player.isShuffleModeEnabled ? Theme.of(context).colorScheme.primary : onSurface.withOpacity(0.7),
                ),
                onPressed: () => player.setShuffleModeEnabled(!player.isShuffleModeEnabled),
              ),
              IconButton(
                icon: Icon(
                  player.repeatMode == repeat.PlaybackRepeatMode.one
                      ? PhosphorIconsFill.repeatOnce
                      : (player.repeatMode == repeat.PlaybackRepeatMode.all
                          ? PhosphorIconsFill.repeat
                          : PhosphorIconsRegular.repeat),
                  color: player.repeatMode != repeat.PlaybackRepeatMode.none
                      ? Theme.of(context).colorScheme.primary
                      : onSurface.withOpacity(0.7),
                ),
                onPressed: () {
                  final modes = repeat.PlaybackRepeatMode.values;
                  final nextMode = modes[(player.repeatMode.index + 1) % modes.length];
                  player.setRepeatMode(nextMode);
                },
              ),
              AutoDJModePicker(
                currentMode: player.baseAutoDJMode,
                onModeSelected: (m) => player.setBaseAutoDJMode(m),
                isSmart: false,
              ),
              AutoDJModePicker(
                currentMode: player.smartAutoDJMode,
                onModeSelected: (m) => player.setSmartAutoDJMode(m),
                isSmart: true,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 3. Continue Playing Header
          Text(
            'Continue Playing',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: onSurface,
            ),
          ),
          if (player.activeAutoDJMode != AutoDJMode.off)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'AutoPlaying similar songs',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          const SizedBox(height: 12),

          // 4. Upcoming Tracks List
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: upcoming.length,
              itemBuilder: (context, index) {
                final t = upcoming[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      t.thumbnailUrl,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 40, height: 40, color: Colors.white10,
                      ),
                    ),
                  ),
                  title: Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    t.author ?? 'Unknown',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: onSurface.withOpacity(0.6), fontSize: 13),
                  ),
                  trailing: IconButton(
                    icon: const Icon(PhosphorIconsRegular.x),
                    onPressed: () => player.removeFromQueue(currentIndex + 1 + index),
                  ),
                  onTap: () {
                    setState(() => _showQueue = false);
                    player.playFromQueue(currentIndex + 1 + index);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
'''

# Inject before the final closing brace of _PlayingScreenState
content = content[:content.rfind('}')] + func + '\n}\n'

with open('lib/ui/screens/playing_screen.dart', 'w') as f:
    f.write(content)
