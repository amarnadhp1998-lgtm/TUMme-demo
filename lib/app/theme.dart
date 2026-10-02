import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const ink = Color(0xFF16312B);
  static const canvas = Color(0xFFF7FAF6);
  static const accent = Color(0xFF216B4E);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
      surface: canvas,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: canvas,
      appBarTheme: const AppBarTheme(backgroundColor: canvas),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(vertical: 8)),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
    );
  }
}
