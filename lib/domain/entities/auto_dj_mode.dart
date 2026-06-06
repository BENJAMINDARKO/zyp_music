import 'package:flutter/material.dart';

/// The set of Auto DJ engine modes surfaced through the in-app mode picker.
///
/// Each mode corresponds to a distinct recommendation / queue-extension
/// strategy. The implementations live in `PlayerProvider` (and a future
/// `DJPredictiveEngine`) and are filled in during Phase 1 — for now the
/// mode picker is wired up to set the mode field on [PlayerProvider] but
/// the actual per-mode engine behaviour is a no-op.
///
/// **Phase 0 contract:** setting a non-off mode flips the
/// `QueueManager._isAutoDJEnabled` flag so the miniplayer / fullscreen
/// AUTODJ icon lights up exactly as it did before the refactor. The
/// per-mode engine (the next-track picker) is wired in Phase 1.
enum AutoDJMode {
  /// Engine disengaged. Playback stops when the manual queue ends.
  off(
    label: 'Off',
    icon: Icons.power_settings_new,
    description: 'Playback stops when queue ends',
  ),

  /// Add random songs from the library. Routes through the existing
  /// offline Hive-shuffle pool (so the function works online AND offline
  /// — the offline database is always consulted).
  shuffleLibrary(
    label: 'Shuffle Library',
    icon: Icons.shuffle,
    description: 'Add random songs from your library',
  ),

  /// Add songs similar to what is playing. Phase 1 will swap the
  /// random-shuffle picker for a similarity-scored picker, and chain
  /// into the `SimilarAutoNext` online service for continued similar
  /// songs.
  similarSongs(
    label: 'Similar Songs',
    icon: Icons.queue_music,
    description: 'Add songs similar to what is playing',
  ),

  /// Add songs from the same genre as the currently playing track.
  sameGenre(
    label: 'Same Genre',
    icon: Icons.category_outlined,
    description: 'Add songs from the same genre',
  ),

  /// Add more songs by the same artist as the currently playing track.
  sameArtist(
    label: 'Same Artist',
    icon: Icons.person_outline,
    description: 'Add more songs by the same artist',
  ),

  /// Auto mix tracks. Phase 1 will implement a heuristic that blends
  /// similarity + library shuffle + tempo / mood matching.
  smartDj(
    label: 'Smart DJ',
    icon: Icons.auto_awesome,
    description: 'Auto mixes tracks from across your library',
  );

  const AutoDJMode({
    required this.label,
    required this.icon,
    required this.description,
  });

  /// Human-readable label shown in the picker, miniplayer tooltip, and
  /// fullscreen player tooltip.
  final String label;

  /// Leading icon for the picker ListTile.
  final IconData icon;

  /// One-line subtitle shown beneath the label in the picker. Phrased as
  /// a present-tense statement so the user can scan the menu and pick
  /// the mode they want.
  final String description;

  /// True iff this mode is one of the "engine is armed" modes (i.e. not
  /// the [off] sentinel). Used by the icon visual-state code to
  /// distinguish "disengaged" (white54 / outlined) from "engaged"
  /// (yellow / filled) regardless of which specific mode is active.
  bool get isActive => this != AutoDJMode.off;
}
