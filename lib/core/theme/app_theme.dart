import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Primary & Accent Colors ──────────────────────────────────────────
  static const Color primaryColor = Color(0xFF2E88F6); // Vibrant Blue
  static const Color dangerColor = Color(0xFFFF5959); // Red / Delete
  static const Color warningColor = Color(0xFFFF9F43); // Orange
  static const Color successColor = Color(0xFF4CAF50); // Green
  static const Color purpleAccent = Color(0xFF6C5DD3); // Theme toggle icon

  // ── Dark Palette ─────────────────────────────────────────────────────
  static const Color scaffoldBgDark = Color(0xFF0B111D); // Dark Navy
  static const Color surfaceDark = Color(0xFF151C29); // Lighter Navy Card
  static const Color textPrimaryDark = Colors.white;
  static const Color textSecondaryDark = Color(0xFF9E9E9E); // Grey 500
  static const Color cardBorderDark = Color(0x0DFFFFFF); // white 5%
  static const Color dividerDark = Color(0x1AFFFFFF); // white 10%
  static const Color disabledTextDark = Color(0x8AFFFFFF); // white 54%
  static const Color shortfallBgDark = Color(0xFF2A1215);

  // ── Light Palette ────────────────────────────────────────────────────
  static const Color scaffoldBgLight = Color(0xFFF5F7FA);
  static const Color surfaceLight = Colors.white;
  static const Color textPrimaryLight = Color(0xFF1A1A2E);
  static const Color textSecondaryLight = Color(0xFF757575); // Grey 600
  static const Color cardBorderLight = Color(0x14000000); // black 8%
  static const Color dividerLight = Color(0x14000000); // black 8%
  static const Color disabledTextLight = Color(0x8A000000); // black 54%
  static const Color shortfallBgLight = Color(0xFFFDE8E8);

  // ── Gradient Colors ──────────────────────────────────────────────────
  static const Color logGradientStart = Color(0xFF137FEC);
  static const Color logGradientEnd = Color(0xFF0F65BD);
  static const Color deleteGradientStart = Color(0xFFFF5959);
  static const Color deleteGradientEnd = Color(0xFFCC4444);

  // ── Badge / Chip Background (dark-mode specific) ─────────────────────
  static const Color blueBadgeBgDark = Color(0xFF1A2C42);
  static const Color blueBadgeBgLight = Color(0xFFDCEEFF);
  static const Color chipBgDark = Color(0xFF1A2230);
  static const Color chipBgLight = Color(0xFFE8F0FE);

  static final TextTheme _textTheme = GoogleFonts.interTextTheme();

  // ═══════════════════════════════════════════════════════════════════════
  // DARK THEME
  // ═══════════════════════════════════════════════════════════════════════
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.dark,
        primary: primaryColor,
        surface: surfaceDark,
        onSurface: textPrimaryDark,
      ),
      primaryColor: primaryColor,
      scaffoldBackgroundColor: scaffoldBgDark,
      dividerColor: dividerDark,
      textTheme: _textTheme.apply(
        bodyColor: textPrimaryDark,
        displayColor: textPrimaryDark,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: scaffoldBgDark,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimaryDark,
        ),
        iconTheme: IconThemeData(color: textPrimaryDark),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceDark,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        hintStyle: const TextStyle(color: disabledTextDark),
      ),
      cardTheme: CardThemeData(
        color: surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: cardBorderDark),
        ),
        margin: EdgeInsets.zero,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // LIGHT THEME
  // ═══════════════════════════════════════════════════════════════════════
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.light,
        primary: primaryColor,
        surface: surfaceLight,
        onSurface: textPrimaryLight,
      ),
      primaryColor: primaryColor,
      scaffoldBackgroundColor: scaffoldBgLight,
      dividerColor: dividerLight,
      textTheme: _textTheme.apply(
        bodyColor: textPrimaryLight,
        displayColor: textPrimaryLight,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: scaffoldBgLight,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimaryLight,
        ),
        iconTheme: IconThemeData(color: textPrimaryLight),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLight,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cardBorderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cardBorderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        hintStyle: const TextStyle(color: disabledTextLight),
      ),
      cardTheme: CardThemeData(
        color: surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: cardBorderLight),
        ),
        margin: EdgeInsets.zero,
      ),
    );
  }
}
