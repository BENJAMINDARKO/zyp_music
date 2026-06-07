import 'package:flutter/material.dart';
import 'theme_config.dart';

/// Semantic colors surfaced from the active [ThemePalette].
///
/// Usage:
/// ```dart
/// final tc = context.themeColors;
/// Container(color: tc.surface)
/// ```
///
/// Every color in this extension resolves through the theme's
/// [ThemePalette], so switching themes propagates everywhere
/// that uses these names instead of raw hex values.
extension ThemeColors on BuildContext {
  ThemePalette get _palette => paletteFor(
        Theme.of(this).brightness == Brightness.dark ? 'Dark' : 'White',
      );

  // ---- Backgrounds -------------------------------------------------------

  Color get bgBackground => _palette.background;
  Color get bgSurface => _palette.surface;
  Color get bgCard => _palette.card;

  // ---- Accent / brand ----------------------------------------------------

  Color get accent => _palette.accent;
  Color get primary => _palette.primary;
  Color get secondary => _palette.secondary;
  Color get error => _palette.error;

  // ---- Convenience helpers -----------------------------------------------

  /// True when the active theme is dark.
  bool get isDark => _palette.brightness == Brightness.dark;

  /// Returns surface if dark, card if light (useful for
  /// secondary backgrounds).
  Color get surfaceAlt => isDark ? _palette.card : _palette.surface;

  /// Foreground white — adjusted brightness for white/light themes.
  Color get textPrimary => isDark ? Colors.white : Colors.black87;
  Color get textSecondary => isDark ? Colors.white54 : Colors.black54;
  Color get textHint => isDark ? Colors.grey : Colors.grey[600]!;
  Color get border => isDark ? const Color(0xFF2A2A2A) : Colors.grey[300]!;
  Color get chipBg => isDark ? const Color(0xFF1F1F1F) : Colors.grey[200]!;
  Color get divider => isDark ? Colors.white24 : Colors.black12;

  /// Themed icon colours.
  Color get iconActive => isDark ? Colors.white : Colors.black87;
  Color get iconInactive => isDark ? Colors.white54 : Colors.black54;
}
