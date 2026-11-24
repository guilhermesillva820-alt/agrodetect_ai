import 'package:flutter/material.dart';

class AppColors {
  static const forest = Color(0xFF0F241D);
  static const forestLight = Color(0xFF17352B);
  static const leaf = Color(0xFF4CAF50);
  static const orange = Color(0xFFFF9800);
  static const amber = Color(0xFFFFC107);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.leaf,
    brightness: Brightness.dark,
  ).copyWith(primary: AppColors.leaf, surface: AppColors.forest);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.forest,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.forest,
      foregroundColor: Colors.white,
      centerTitle: true,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.forestLight,
      indicatorColor: AppColors.leaf.withOpacity(0.3),
    ),
  );
}
