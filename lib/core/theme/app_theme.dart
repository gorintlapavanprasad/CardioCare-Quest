import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.background,

      // Typography: Atkinson Hyperlegible throughout. Designed by the
      // Braille Institute specifically to maximise legibility for
      // readers with low vision — distinct letterforms (especially
      // I/l/1, O/0, b/d, p/q) reduce the misreads our elderly +
      // visually-impaired participants are most likely to make.
      // Hierarchy comes from weight + size; the four TTF files are
      // bundled locally (see pubspec.yaml + assets/fonts/) so the
      // app works fully offline with the chosen typeface.
      fontFamily: 'Atkinson Hyperlegible',
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontFamily: 'Atkinson Hyperlegible',
          fontWeight: FontWeight.w900,
          color: AppColors.title,
          fontSize: 32,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Atkinson Hyperlegible',
          fontWeight: FontWeight.w700,
          color: AppColors.title,
          fontSize: 24,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Atkinson Hyperlegible',
          fontWeight: FontWeight.bold,
          color: AppColors.title,
          fontSize: 18,
        ),
        bodyLarge: TextStyle(
          fontFamily: 'Atkinson Hyperlegible',
          fontSize: 16,
          color: AppColors.body,
          height: 1.6,
          letterSpacing: 0.3,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Atkinson Hyperlegible',
          fontSize: 14,
          color: AppColors.body,
          height: 1.5,
        ),
        labelSmall: TextStyle(
          fontFamily: 'Atkinson Hyperlegible',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.subtitle,
        ),
      ),

      // Card Style: High-fidelity with subtle shadow and border
      cardTheme: CardThemeData(
        color: AppColors.cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.cardBorder, width: 1),
        ),
      ),

      // Button Style: Primary green with white text
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.btnText,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle: const TextStyle(
            fontFamily: 'Atkinson Hyperlegible',
            fontWeight: FontWeight.w800,
            fontSize: 16,
            letterSpacing: 0.8,
          ),
          elevation: 0,
        ),
      ),

      // Text Button Style
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(
            fontFamily: 'Atkinson Hyperlegible',
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),

      // Input Style: Clean, accessible
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        hintStyle: const TextStyle(
          fontFamily: 'Atkinson Hyperlegible',
          color: AppColors.placeholder,
          fontSize: 14,
        ),
        labelStyle: const TextStyle(
          fontFamily: 'Atkinson Hyperlegible',
          color: AppColors.title,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),

      // App Bar Style
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Atkinson Hyperlegible',
          color: AppColors.title,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: AppColors.title),
      ),

      // Colors
      colorScheme: ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        tertiary: AppColors.accent,
        surface: AppColors.cardBg,
        error: AppColors.error,
        onPrimary: Colors.white,
      ),
    );
  }
}
