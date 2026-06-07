import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/auto_dj_routing_service.dart';
import '../../data/datasources/local/playlist_database.dart';
import '../../domain/entities/auto_dj_mode.dart';
import '../../presentation/providers/player_provider.dart';

/// Phase 0 modal bottom sheet that lets the user pick one of the six
/// [AutoDJMode]s. Surfaced from three entry points — all of which now
/// open this same picker so the user has a single, consistent UI for
/// arming / disarming / switching the Auto DJ engine:
///
/// 1. The "Start Auto DJ" ListTile in [TrackContextMenu].
/// 2. The "Start Auto DJ" ListTile in [AlbumContextMenu].
/// 3. The AUTODJ icon in the miniplayer ([BottomPlayer]).
/// 4. The AUTODJ icon in the fullscreen player ([PlayingScreen]).
///
/// **Phase 0 contract:** tapping a mode in the picker calls
/// [PlayerProvider.setAutoDJMode] (which records the choice and flips
/// the legacy [QueueManager] flag for the icon visual state) and shows
/// a `Phase 1 placeholder` snackbar. The actual per-mode engine logic
/// (what each mode appends to the queue) is wired in Phase 1.
class AutoDJModePicker {
  /// Convenience entry point used by all four call sites above.
  /// Captures the caller-provided [BuildContext] (typically the icon
  /// or tile that was tapped) and the [ScaffoldMessenger] handle so
  /// the post-pick feedback snackbar can fire even after the picker
  /// itself is dismissed.
  static void show(BuildContext context) {
    // Capture the messenger BEFORE showing the sheet so the snackbar
    // can fire after the sheet's own `Navigator.pop` (which would
    // otherwise leave us with an unmounted context to read from).
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        // Read the current mode once at sheet-open time so the
        // "active mode" indicator next to each option reflects the
        // picker state, not the field that may flip mid-build.
        final currentMode = sheetContext.read<PlayerProvider>().autoDJMode;
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      color: Color(0xFFEAB308),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Auto DJ',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    Text(
                      'Current: ${currentMode.label}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Pick a mode — engine implementations land in Phase 1',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              const Divider(color: Colors.white24),
              for (final mode in AutoDJMode.values)
                _ModeTile(
                  mode: mode,
                  isCurrentMode: mode == currentMode,
                  onPick: () async {
                    // Spec 2H: Shuffle Library opens a sub-menu
                    // for genre-filter selection. Other modes
                    // arm directly via the existing path.
                    if (mode == AutoDJMode.shuffleLibrary) {
                      // Open the sub-menu on top of the current
                      // sheet. We do NOT pop the parent sheet —
                      // dismissing it here would leave the sub-menu
                      // unattached to the modal stack. The sub-menu
                      // returns a future that completes with the
                      // chosen genre (or null for "No filter").
                      final picked = await ShuffleLibraryFilterSubMenu
                          .show(sheetContext);
                      if (picked == null) {
                        // User dismissed the sub-menu without
                        // picking — keep the current mode intact.
                        return;
                      }
                      Navigator.pop(sheetContext);
                      // Apply the filter, then arm the mode. The
                      // routing service stores the filter key so
                      // the next resolveNext pass narrows the pool.
                      final routing = sheetContext
                          .read<AutoDjRoutingService?>();
                      if (routing != null) {
                        routing.setShuffleLibraryGenreFilter(picked);
                      }
                      final provider = sheetContext.read<PlayerProvider>();
                      final result =
                          await provider.setAutoDJMode(AutoDJMode.shuffleLibrary);
                      final filterName = picked ?? 'no filter';
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
                    // Dismiss the sheet first so the snackbar lands on
                    // the parent surface (miniplayer / fullscreen /
                    // context menu's parent), not on top of the sheet.
                    Navigator.pop(sheetContext);
                    final provider = sheetContext.read<PlayerProvider>();
                    final result = await provider.setAutoDJMode(mode);
                    // Per-mode armed message. The cold-start path
                    // (when the player is in cold-idle state)
                    // augments the message with the actual track
                    // title; the no-library paths surface a clear
                    // "pick a song" prompt so the user knows why
                    // nothing played.
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
        ),);
      },
    );
  }
}

/// Maps the (mode, cold-start-result) tuple to the right
/// snackbar message. The user-facing copy uses the real
/// per-mode engine behaviour now that all five active modes
/// are wired (Phase 5). The cold-start paths add detail
/// about whether a track actually started playing.
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
    // Highlight the currently-selected mode with a brighter leading
    // icon and a subtle "Active" trailing label. Tapping it again is a
    // no-op (setAutoDJMode early-returns on the same value), but the
    // user gets visual confirmation that the option is the one
    // currently armed.
    final iconColor = isCurrentMode
        ? const Color(0xFFEAB308)
        : Colors.white;
    return ListTile(
      leading: Icon(mode.icon, color: iconColor),
      title: Text(
        mode.label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: isCurrentMode ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        mode.description,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: isCurrentMode
          ? const Icon(Icons.check_circle, color: Color(0xFFEAB308), size: 18)
          : const Icon(Icons.radio_button_unchecked, color: Colors.white24, size: 18),
      onTap: onPick,
    );
  }
}

/// Spec 2H: genre-filter sub-menu for the Shuffle Library mode.
///
/// Modal bottom sheet that shows a ranked list of genre
/// clusters present in the user's downloaded library, with
/// track counts. The top entry is "No filter (all songs)".
/// Returning [null] (tap-outside / back button) keeps the
/// parent mode picker intact; the user must explicitly tap
/// a genre or the top entry to confirm a selection.
class ShuffleLibraryFilterSubMenu {
  /// Opens the sub-menu over the existing modal stack and
  /// resolves with the chosen filter key, or [null] if the
  /// user dismissed the sheet without picking.
  ///
  /// `key` semantics match the proximity-matrix schema:
  ///   * `null` → "No filter" (existing behaviour).
  ///   * non-null → canonical matrix key, e.g. "Afrobeats".
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
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final db = sheetContext.read<PlaylistDatabase>();
        return SafeArea(
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: const [
              Icon(Icons.filter_list, color: Color(0xFFEAB308), size: 24),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Shuffle Library — Filter',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Limit the pool to a single genre cluster.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
        const Divider(color: Colors.white24),
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
                    style: const TextStyle(color: Colors.white70),
                  ),
                );
              }
              final counts = snap.data ?? const <String, int>{};
              if (counts.isEmpty) {
                return _FilterTile(
                  title: 'No filter',
                  subtitle:
                      'Your library has no enriched tracks yet — play some songs to see genre filters.',
                  onPick: () => Navigator.pop(context, null),
                );
              }
              // Sort descending by count; alphabetical tiebreak
              // keeps the order deterministic for tests.
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
                    onPick: () => Navigator.pop(context, null),
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
        style: const TextStyle(color: Colors.white),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
      onTap: onPick,
    );
  }
}
