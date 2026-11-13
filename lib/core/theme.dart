import 'package:material_ui/material_ui.dart';

/// Color tokens from UI_UX.md §2.
abstract final class AppColors {
  static const bg = Color(0xFF0E1117);
  static const surface = Color(0xFF161B22);
  static const surfaceAlt = Color(0xFF21262D);
  static const textPrimary = Color(0xFFE6EDF3);
  static const textSecondary = Color(0xFF8B949E);
  static const gain = Color(0xFF22C55E);
  static const loss = Color(0xFFEF4444);
  static const accent = Color(0xFF3B82F6);
  static const warning = Color(0xFFF59E0B);
}

ThemeData buildDarkTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerHighest: AppColors.surfaceAlt,
      outline: AppColors.surfaceAlt,
      error: AppColors.loss,
    ),
    scaffoldBackgroundColor: AppColors.bg,
  );

  return base.copyWith(
    // Typography scale from UI_UX.md §2; other styles keep Material defaults.
    textTheme: base.textTheme
        .merge(
          const TextTheme(
            displaySmall: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            labelMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        )
        .apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.textPrimary,
      scrolledUnderElevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accent.withValues(alpha: 0.25),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.surfaceAlt),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
