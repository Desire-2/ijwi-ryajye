import 'package:flutter/material.dart';

/// Ijwi Ryajye design system - green agricultural palette, rounded cards,
/// high-contrast text for outdoor readability.
class IjwiColors {
  static const green = Color(0xFF1B7A43);
  static const greenDark = Color(0xFF0F5A2F);
  static const greenLight = Color(0xFFE6F4EB);
  static const amber = Color(0xFFF5A623);
  static const red = Color(0xFFC0392B);
  static const blue = Color(0xFF2563EB);
  static const ink = Color(0xFF17251D);
  static const muted = Color(0xFF5B6B61);
  static const surface = Color(0xFFF7FAF8);
  static const card = Colors.white;
}

class IjwiRadius {
  static const sm = 8.0;
  static const md = 14.0;
  static const lg = 22.0;
}

ThemeData buildIjwiTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: IjwiColors.green,
      primary: IjwiColors.green,
      secondary: IjwiColors.amber,
      error: IjwiColors.red,
      surface: IjwiColors.surface,
    ),
    scaffoldBackgroundColor: IjwiColors.surface,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: IjwiColors.green,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: IjwiColors.card,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IjwiRadius.md),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: IjwiColors.green,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(IjwiRadius.md),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: IjwiColors.green,
        side: const BorderSide(color: IjwiColors.green),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(IjwiRadius.md),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(IjwiRadius.md),
        borderSide: const BorderSide(color: Color(0xFFD7E2DA)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(IjwiRadius.md),
        borderSide: const BorderSide(color: Color(0xFFD7E2DA)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(IjwiRadius.md),
        borderSide: const BorderSide(color: IjwiColors.green, width: 1.6),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IjwiRadius.sm),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
    ),
  );
}
