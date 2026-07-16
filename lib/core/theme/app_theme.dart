import 'package:flutter/material.dart';

class ZypAuroraColors {
  static const ink = Color(0xFF05040B);
  static const ink2 = Color(0xFF111129);

  static const cyan = Color(0xFF5EEAD4);
  static const violet = Color(0xFF9F7AEA);
  static const pink = Color(0xFFFF5CC8);
  static const peach = Color(0xFFF6B17A);
  static const lime = Color(0xFFE0FD7D);

  static const success = Color(0xFF20D676);
  static const error = Color(0xFFFF4F4F);

  static const glass = Color(0x8512142C);
  static const glassSoft = Color(0x12FFFFFF);
  static const stroke = Color(0x26FFFFFF);
}

class AppTheme {
  // Dark mode constants — UNCHANGED
  static const _primaryColor = Color(0xFF1DB954);
  static const _darkBg = Color(0xFF121212);
  static const _darkSurface = Color(0xFF1E1E1E);
  static const _darkCard = Color(0xFF282828);

  // Shared semantic colors (accessibility-tuned)
  static const _errorColor = Color(0xFFCF6679);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: ZypAuroraColors.cyan,
      scaffoldBackgroundColor: Colors.transparent,
      fontFamily: 'Inter',
      colorScheme: const ColorScheme.dark(
        primary: ZypAuroraColors.cyan,
        secondary: ZypAuroraColors.violet,
        surface: ZypAuroraColors.ink,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: Colors.white,
        error: ZypAuroraColors.error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: const CardThemeData(
        color: ZypAuroraColors.glass,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      iconTheme: const IconThemeData(color: Colors.white),
      textTheme: const TextTheme(
        titleLarge: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
        titleMedium: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
        bodyLarge: TextStyle(color: Colors.white, fontSize: 16),
        bodyMedium: TextStyle(color: Colors.white70, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ZypAuroraColors.cyan,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ZypAuroraColors.glassSoft,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: Colors.grey),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
