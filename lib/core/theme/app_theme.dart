import 'package:flutter/material.dart';

/// Shared colour palette, extracted from the colours already used across the
/// app so existing screens look identical. New screens should use these
/// instead of hardcoded `Color(0xFF...)` values; per-cafe branding will build
/// on top of this in the UI phase.
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF141211);
  static const Color surface = Color(0xFF1E1A17);
  static const Color surfaceAlt = Color(0xFF231E1B);
  static const Color border = Color(0xFF2C2520);

  static const Color primary = Color(0xFFE65C00); // flame orange
  static const Color accent = Color(0xFFF7B731); // gold

  static const Color success = Colors.green;
  static const Color danger = Colors.redAccent;
}

class AppTheme {
  AppTheme._();

  /// Identical to the ThemeData previously defined inline in main.dart.
  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          secondary: AppColors.accent,
          surface: AppColors.surface,
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      );
}
