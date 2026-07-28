import 'package:flutter/material.dart';

/// App color system — 3 semantic colors, Material 3 compliant
class AppColors {
  // ── Palette ──────────────────────────────────────────────
  // Color 1: Primary action / checked state (green from Figma)
  static const Color primary = Color(0xFF24AC09);

  // Color 2: Surface / neutral containers
  // Light: clean white  |  Dark: elevated surface
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF2C2C2E);  // iOS-style dark surface

  // Color 3: Background
  static const Color bgLight = Color(0xFFF2F2F7);
  static const Color bgDark = Color(0xFF1C1C1E); // iOS dark bg

  // ── Derived ──────────────────────────────────────────────
  // Bottom nav & sheet background
  static const Color navLight = Color(0xFFFFFFFF); // white bottom bar
  static const Color navDark = Color(0xFF3A3A3C);

  // Bottom sheets use a dark surface in both themes so white text is readable
  static const Color sheetLight = Color(0xFF2C2C2E);
  static const Color sheetDark = Color(0xFF3A3A3C);

  // Secondary surface (slightly lighter/darker)
  static const Color surfaceSecondaryLight = Color(0xFFE5E5EA);
  static const Color surfaceSecondaryDark = Color(0xFF3A3A3C);

  // Text
  static const Color textLight = Color(0xFF000000);
  static const Color textDark = Color(0xFFFFFFFF);
  static const Color textSecondaryLight = Color(0xFF6B7280);
  static const Color textSecondaryDark = Color(0xFF8E8E93);
}

class AppTheme {
  // ── Figma exact spacing constants ─────────────────────────
  static const double pillRadius = 28.0; // cr:28 on task rows
  static const double fabRadius = 16.0;  // cr:16 on FAB
  static const double menuRadius = 16.0; // cr:16 on context menus
  static const double checkRadius = 8.0; // cr:8 on empty checkbox
  static const double checkRadiusDone = 6.0; // cr:6 on done checkbox
  static const double sheetHandleRadius = 2.0;

  // ── Figma exact padding/gap constants ─────────────────────
  static const double rowPadH = 20.0;   // left/right inside pill row
  static const double rowPadV = 15.0;   // top/bottom inside pill row
  static const double rowGap = 10.0;    // gap between row children
  static const double rowHeight = 56.0; // h of every row/pill
  static const double rowWidth = 328.0; // 360 - 16 - 16
  static const double screenPad = 16.0; // outer horizontal padding

  static const double navHeight = 100.0; // Figma nav bar h
  static const double navPadTop = 14.0;
  static const double navPadBottom = 24.0;

  static const double fabSize = 56.0;

  static const double sheetGap = 72.0;  // gap inside bottom sheet
  static const double sheetPadH = 16.0;
  static const double sheetPadTop = 20.0;

  static const double menuItemGap = 6.0;  // gap between menu items
  static const double menuItemPad = 10.0; // padding inside menu item
  static const double menuItemGapInner = 10.0; // gap icon–label in menu item

  // ── Themes ────────────────────────────────────────────────
  static ThemeData get lightTheme => _build(Brightness.light);
  static ThemeData get darkTheme => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgDark : AppColors.bgLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final onSurface = isDark ? AppColors.textDark : AppColors.textLight;
    final baseTypography = Typography.material2021();

    return ThemeData(
      brightness: brightness,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.navLight,
        onSecondary: Colors.white,
        surface: surface,
        onSurface: onSurface,
        error: Colors.redAccent,
        onError: Colors.white,
      ),
      textTheme: (isDark ? baseTypography.white : baseTypography.black)
          .apply(
            fontFamily: 'Inter',
            bodyColor: onSurface,
            displayColor: onSurface,
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        iconTheme: IconThemeData(color: onSurface),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: onSurface,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.bgLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: InputBorder.none,
        hintStyle: TextStyle(
          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
          fontSize: 16,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppColors.surfaceDark : const Color(0xFF323232),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
