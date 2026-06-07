import 'package:flutter/material.dart';

/// Color palette for one theme variant.
///
/// Every theme defines these 8 values. The engine maps
/// them into a full [ThemeData] object. New themes are
/// added by defining a new static const here and adding
/// the name to [all].
class ThemePalette {
  const ThemePalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.card,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.error,
  });

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color card;
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color error;
}

// ---------------------------------------------------------------------------
// Palette definitions
// ---------------------------------------------------------------------------

const _systemDark = ThemePalette(
  brightness: Brightness.dark,
  background: Color(0xFF121212),
  surface: Color(0xFF1E1E1E),
  card: Color(0xFF282828),
  primary: Color(0xFF1DB954),
  secondary: Color(0xFF1DB954),
  accent: Color(0xFFEAB308),
  error: Color(0xFFEF4444),
);

const _systemLight = ThemePalette(
  brightness: Brightness.light,
  background: Color(0xFFF5F5F5),
  surface: Color(0xFFFFFFFF),
  card: Color(0xFFE8E8E8),
  primary: Color(0xFF1DB954),
  secondary: Color(0xFF1DB954),
  accent: Color(0xFFD97706),
  error: Color(0xFFDC2626),
);

const _black = ThemePalette(
  brightness: Brightness.dark,
  background: Color(0xFF000000),
  surface: Color(0xFF0A0A0A),
  card: Color(0xFF141414),
  primary: Color(0xFF1DB954),
  secondary: Color(0xFF1DB954),
  accent: Color(0xFFEAB308),
  error: Color(0xFFEF4444),
);

const _white = ThemePalette(
  brightness: Brightness.light,
  background: Color(0xFFF9FAFB),
  surface: Color(0xFFFFFFFF),
  card: Color(0xFFF3F4F6),
  primary: Color(0xFF1DB954),
  secondary: Color(0xFF1DB954),
  accent: Color(0xFFD97706),
  error: Color(0xFFDC2626),
);

const _dark = ThemePalette(
  brightness: Brightness.dark,
  background: Color(0xFF121212),
  surface: Color(0xFF1E1E1E),
  card: Color(0xFF282828),
  primary: Color(0xFF1DB954),
  secondary: Color(0xFF1DB954),
  accent: Color(0xFFEAB308),
  error: Color(0xFFEF4444),
);

const _ocean = ThemePalette(
  brightness: Brightness.dark,
  background: Color(0xFF0D1B2A),
  surface: Color(0xFF1B2838),
  card: Color(0xFF243447),
  primary: Color(0xFF60A5FA),
  secondary: Color(0xFF38BDF8),
  accent: Color(0xFF22D3EE),
  error: Color(0xFFF87171),
);

const _purple = ThemePalette(
  brightness: Brightness.dark,
  background: Color(0xFF1A0A2E),
  surface: Color(0xFF2D1B4E),
  card: Color(0xFF3B2A5E),
  primary: Color(0xFFA78BFA),
  secondary: Color(0xFFC084FC),
  accent: Color(0xFFE879F9),
  error: Color(0xFFFCA5A5),
);

const _forest = ThemePalette(
  brightness: Brightness.dark,
  background: Color(0xFF0F1F0F),
  surface: Color(0xFF1A2E1A),
  card: Color(0xFF243D24),
  primary: Color(0xFF4ADE80),
  secondary: Color(0xFF22C55E),
  accent: Color(0xFFFBBF24),
  error: Color(0xFFEF4444),
);

const _mocha = ThemePalette(
  brightness: Brightness.dark,
  background: Color(0xFF1C1411),
  surface: Color(0xFF2A1F1B),
  card: Color(0xFF382B26),
  primary: Color(0xFFD4A574),
  secondary: Color(0xFFC4916C),
  accent: Color(0xFFF5C698),
  error: Color(0xFFE57373),
);

const _machiatto = ThemePalette(
  brightness: Brightness.light,
  background: Color(0xFFFEF7E9),
  surface: Color(0xFFFFFBF2),
  card: Color(0xFFF5EDD6),
  primary: Color(0xFF8B5E3C),
  secondary: Color(0xFFA67B5B),
  accent: Color(0xFFC9956B),
  error: Color(0xFFC0392B),
);

const _frappe = ThemePalette(
  brightness: Brightness.light,
  background: Color(0xFFEEF2F7),
  surface: Color(0xFFF8FAFC),
  card: Color(0xFFE2E8F0),
  primary: Color(0xFF5B6C8B),
  secondary: Color(0xFF7C8DB5),
  accent: Color(0xFF8DA3D6),
  error: Color(0xFFB91C1C),
);

// ---------------------------------------------------------------------------
// Lookup
// ---------------------------------------------------------------------------

const _themeMap = <String, ThemePalette>{
  'System': _systemDark,
  'Black': _black,
  'White': _white,
  'Dark': _dark,
  'Ocean': _ocean,
  'Purple': _purple,
  'Forest': _forest,
  'Mocha': _mocha,
  'Machiatto': _machiatto,
  'Frappé': _frappe,
};

/// Returns the palette for [name], defaulting to Dark.
ThemePalette paletteFor(String name) =>
    _themeMap[name] ?? _dark;

/// The 10 themed names in display order.
List<String> get themeNames => _themeMap.keys.toList(growable: false);

/// Whether the palette with [name] uses [Brightness.light].
bool isLightTheme(String name) =>
    _themeMap[name]?.brightness == Brightness.light;

/// Resolves the stored theme string to a [ThemeMode].
///
/// 'System' → ThemeMode.system, 'White'/'Machiatto'/'Frappé' →
/// ThemeMode.light, everything else → ThemeMode.dark.
ThemeMode themeModeFor(String name) {
  if (name == 'System') return ThemeMode.system;
  if (isLightTheme(name)) return ThemeMode.light;
  return ThemeMode.dark;
}
