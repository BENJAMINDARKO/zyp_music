import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
