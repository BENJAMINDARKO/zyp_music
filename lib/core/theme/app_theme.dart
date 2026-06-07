import 'package:flutter/material.dart';
import 'theme_config.dart';

/// Builds [ThemeData] from a [ThemePalette].
///
/// Usage:
/// ```dart
/// final theme = AppTheme.fromPalette(paletteFor('Ocean'));
/// ```
class AppTheme {
  AppTheme._();

  /// Build a full [ThemeData] from a palette definition.
  static ThemeData fromPalette(ThemePalette p) {
    final isDark = p.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      primaryColor: p.primary,
      scaffoldBackgroundColor: p.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: p.primary,
        brightness: p.brightness,
        surface: p.surface,
        error: p.error,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: isDark ? Colors.white : Colors.black87,
      ),
      cardTheme: CardThemeData(
        color: p.card,
        elevation: 2,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      iconTheme: IconThemeData(
        color: isDark ? Colors.white : Colors.black87,
      ),
      textTheme: TextTheme(
        titleLarge: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
        titleMedium: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
        bodyLarge: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontSize: 16,
        ),
        bodyMedium: TextStyle(
          color: isDark ? Colors.white70 : Colors.black54,
          fontSize: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        hintStyle: TextStyle(
          color: isDark ? Colors.grey : Colors.grey[600],
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white24 : Colors.black12,
        thickness: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.grey[200],
        selectedColor: p.accent,
        labelStyle: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
        ),
        secondaryLabelStyle: TextStyle(
          color: isDark ? Colors.white54 : Colors.black54,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accent,
        inactiveTrackColor: isDark ? Colors.white24 : Colors.black12,
        thumbColor: p.accent,
        valueIndicatorColor: p.accent,
        valueIndicatorTextStyle: const TextStyle(color: Colors.black),
        overlayColor: p.accent.withOpacity(0.15),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.accent;
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return p.accent.withOpacity(0.5);
          }
          return isDark ? Colors.white24 : Colors.black12;
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.grey[800],
        contentTextStyle: TextStyle(
          color: isDark ? Colors.white : Colors.white,
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: p.accent,
        labelColor: isDark ? Colors.white : Colors.black87,
        unselectedLabelColor: isDark ? Colors.white54 : Colors.black54,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.accent,
        foregroundColor: Colors.black,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: isDark ? Colors.white24 : Colors.black12,
      ),
    );
  }
}
