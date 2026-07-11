import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/services/auto_dj_routing_service.dart';
import '../../data/datasources/local/playlist_database.dart';
import '../../domain/entities/auto_dj_mode.dart';
import '../../domain/entities/video.dart';
import '../../presentation/providers/player_provider.dart';
import 'apple_music_sheet.dart';

class AutoDJModePicker {
  static void show(BuildContext context, {Track? seedTrack}) {
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetContext) {
        final currentMode = sheetContext.read<PlayerProvider>().autoDJMode;
        return AppleMusicSheet(
          title: 'Auto DJ',
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Current: ${currentMode.label}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Divider(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.24)),
                  for (final mode in AutoDJMode.values)
                    _ModeTile(
                      mode: mode,
                      isCurrentMode: mode == currentMode,
                      onPick: () async {
                        if (mode == AutoDJMode.shuffleLibrary) {
                          final picked = await ShuffleLibraryFilterSubMenu
                              .show(sheetContext);
                          if (picked == null) {
                            return;
                          }
                          final filter = picked.isEmpty ? null : picked;
                          
                          Navigator.pop(sheetContext);
                          final routing = sheetContext
                              .read<AutoDjRoutingService?>();
                          if (routing != null) {
                            routing.setShuffleLibraryGenreFilter(filter);
                          }
                          final provider = sheetContext.read<PlayerProvider>();
                          if (seedTrack != null) {
                            await provider.playTrackWithNewSession(seedTrack);
                          }
                          await provider.setAutoDJMode(AutoDJMode.shuffleLibrary);
                          final filterName = filter ?? 'no filter';
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'Shuffle Library armed — filter: $filterName',
                              ),
                              duration: const Duration(seconds: 3),
                            ),
                          );
                          return;
                        }
                        Navigator.pop(sheetContext);
                        final provider = sheetContext.read<PlayerProvider>();
                        if (seedTrack != null && mode != AutoDJMode.off) {
                          await provider.playTrackWithNewSession(seedTrack);
                        }
                        final result = await provider.setAutoDJMode(mode);
                        final message = _snackbarFor(mode, result);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(message),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

String _snackbarFor(AutoDJMode mode, ColdStartResult result) {
  switch (result) {
    case ColdStartResult.startedWithTrack:
      return switch (mode) {
        AutoDJMode.off => 'Auto DJ off',
        AutoDJMode.shuffleLibrary =>
          'Shuffle Library armed — 20-track rolling window',
        AutoDJMode.similarSongs =>
          'Similar Songs armed — similarity scoring on',
        AutoDJMode.sameGenre =>
          'Same Genre armed — proximity-graph traversal',
        AutoDJMode.sameArtist =>
          'Same Artist armed — artist filter on',
        AutoDJMode.smartDj =>
          'Smart DJ armed — crossfade engine + Markov chain',
        AutoDJMode.vibeMatch =>
          'Vibe Match armed — seamless tempo & energy matching',
      };
    case ColdStartResult.noLibraryOffline:
      return switch (mode) {
        AutoDJMode.off => 'Auto DJ off',
        _ =>
          'No library found — you\'re offline. Tap any track to start, or connect to the internet for the recommend section.',
      };
    case ColdStartResult.noLibraryOnline:
      return switch (mode) {
        AutoDJMode.off => 'Auto DJ off',
        _ =>
          'Couldn\'t find a track to start. Try again in a moment or pick a song manually.',
      };
    case ColdStartResult.skipped:
      return switch (mode) {
        AutoDJMode.off => 'Auto DJ off',
        AutoDJMode.shuffleLibrary =>
          'Shuffle Library armed — 20-track rolling window',
        AutoDJMode.similarSongs =>
          'Similar Songs armed — similarity scoring on',
        AutoDJMode.sameGenre =>
          'Same Genre armed — proximity-graph traversal',
        AutoDJMode.sameArtist =>
          'Same Artist armed — artist filter on',
        AutoDJMode.smartDj =>
          'Smart DJ armed — crossfade engine + Markov chain',
        AutoDJMode.vibeMatch =>
          'Vibe Match armed — seamless tempo & energy matching',
      };
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.mode,
    required this.isCurrentMode,
    required this.onPick,
  });

  final AutoDJMode mode;
  final bool isCurrentMode;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final iconColor = isCurrentMode
        ? const Color(0xFFEAB308)
        : Theme.of(context).colorScheme.onSurface;
    return ListTile(
      leading: mode.iconBuilder(color: iconColor),
      title: Text(
        mode.label,
        style: TextStyle(
          fontWeight: isCurrentMode ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        mode.description,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 12),
      ),
      trailing: isCurrentMode
          ? const Icon(PhosphorIconsFill.checkCircle, color: Color(0xFFEAB308), size: 18)
          : Icon(PhosphorIconsRegular.circle, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.24), size: 18),
      onTap: onPick,
    );
  }
}

/// Spec 2H: genre-filter sub-menu for the Shuffle Library mode.
class ShuffleLibraryFilterSubMenu {
  static Future<String?> show(BuildContext parentContext) {
    return _showImpl(parentContext);
  }

  @visibleForTesting
  static Future<String?> showForTesting(BuildContext parentContext) {
    return _showImpl(parentContext);
  }

  static Future<String?> _showImpl(BuildContext parentContext) {
    return showModalBottomSheet<String?>(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetContext) {
        final db = sheetContext.read<PlaylistDatabase>();
        return AppleMusicSheet(
          title: 'Filter by Genre',
          child: ShuffleLibraryFilterContent(database: db),
        );
      },
    );
  }
}

class ShuffleLibraryFilterContent extends StatefulWidget {
  const ShuffleLibraryFilterContent({required this.database});

  final PlaylistDatabase database;

  @override
  State<ShuffleLibraryFilterContent> createState() =>
      _ShuffleLibraryFilterContentState();
}

class _ShuffleLibraryFilterContentState
    extends State<ShuffleLibraryFilterContent> {
  Future<Map<String, int>>? _countsFuture;

  @override
  void initState() {
    super.initState();
    _countsFuture = widget.database.getGenreClusterCounts();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Limit the pool to a single genre cluster.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 12),
            ),
          ),
          Divider(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.24)),
          Flexible(
            child: FutureBuilder<Map<String, int>>(
              future: _countsFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFFEAB308),
                        ),
                      ),
                    ),
                  );
                }
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Couldn\'t load genres: ${snap.error}',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.70)),
                    ),
                  );
                }
                final counts = snap.data ?? const <String, int>{};
                if (counts.isEmpty) {
                  return _FilterTile(
                    title: 'No filter',
                    subtitle:
                        'Your library has no enriched tracks yet — play some songs to see genre filters.',
                    onPick: () => Navigator.pop(context, ""),
                  );
                }
                final entries = counts.entries.toList()
                  ..sort((a, b) {
                    final byCount = b.value.compareTo(a.value);
                    return byCount != 0 ? byCount : a.key.compareTo(b.key);
                  });
                return ListView(
                  shrinkWrap: true,
                  children: [
                    _FilterTile(
                      title: 'No filter (all songs)',
                      subtitle: null,
                      onPick: () => Navigator.pop(context, ""),
                    ),
                    for (final e in entries)
                      _FilterTile(
                        title: '${e.key} · ${e.value}',
                        subtitle: e.value == 1 ? '1 track' : '${e.value} tracks',
                        onPick: () => Navigator.pop(context, e.key),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _FilterTile extends StatelessWidget {
  const _FilterTile({
    required this.title,
    required this.subtitle,
    required this.onPick,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        title,
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 12),
            ),
      onTap: onPick,
    );
  }
}
