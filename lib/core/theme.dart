import 'package:flutter/material.dart';

enum ColorPalette { base, ocean, custom }

/// Three user-configurable semantic colors: accent, surface and background.
/// Dark-mode variants are derived from the same three-color input so custom
/// palettes never need to store more than three colors.
class AppPalette {
  final Color primary;
  final Color surfaceLight;
  final Color backgroundLight;
  final Color? primaryDark;
  final Color? surfaceDark;
  final Color? backgroundDark;
  final int _customColorCount;

  const AppPalette._({
    required this.primary,
    required this.surfaceLight,
    required this.backgroundLight,
    this.primaryDark,
    this.surfaceDark,
    this.backgroundDark,
    required int customColorCount,
  }) : assert(customColorCount >= 1 && customColorCount <= 3),
       _customColorCount = customColorCount;

  static const base = AppPalette._(
    primary: Color(0xFF24AC09),
    surfaceLight: Color(0xFFFFFFFF),
    backgroundLight: Color(0xFFF2F2F7),
    primaryDark: Color(0xFF24AC09),
    surfaceDark: Color(0xFF2C2C2E),
    backgroundDark: Color(0xFF1C1C1E),
    customColorCount: 3,
  );

  static const ocean = AppPalette._(
    primary: Color(0xFF087EDE),
    surfaceLight: Color(0xFFFFFFFF),
    backgroundLight: Color(0xFFEAF4FF),
    primaryDark: Color(0xFF55B1FF),
    surfaceDark: Color(0xFF17324A),
    backgroundDark: Color(0xFF091A2A),
    customColorCount: 3,
  );

  Color primaryFor(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return primaryDark ?? _deriveDark(primary, brighten: true);
    }
    return primary;
  }

  Color surfaceFor(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return surfaceDark ?? _deriveDark(surfaceLight);
    }
    return surfaceLight;
  }

  Color backgroundFor(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return backgroundDark ?? _deriveDark(backgroundLight);
    }
    return backgroundLight;
  }

  AppPalette copyWith({
    Color? primary,
    Color? surfaceLight,
    Color? backgroundLight,
    Color? primaryDark,
    Color? surfaceDark,
    Color? backgroundDark,
  }) {
    return AppPalette._(
      primary: primary ?? this.primary,
      surfaceLight: surfaceLight ?? this.surfaceLight,
      backgroundLight: backgroundLight ?? this.backgroundLight,
      primaryDark: primaryDark ?? this.primaryDark,
      surfaceDark: surfaceDark ?? this.surfaceDark,
      backgroundDark: backgroundDark ?? this.backgroundDark,
      customColorCount: _customColorCount,
    );
  }

  List<Color> get customColors => [
    primary,
    if (_customColorCount >= 2) surfaceLight,
    if (_customColorCount >= 3) backgroundLight,
  ];

  Color get navigationDark =>
      this == base
          ? const Color(0xFF3A3A3C)
          : Color.lerp(surfaceFor(Brightness.dark), Colors.white, 0.18)!;

  Color get sheetDark =>
      this == base ? const Color(0xFF3A3A3C) : navigationDark;

  Color get surfaceSecondaryLight =>
      this == base
          ? const Color(0xFFE5E5EA)
          : Color.lerp(surfaceLight, backgroundLight, 0.55)!;

  Color get surfaceSecondaryDark =>
      this == base
          ? const Color(0xFF3A3A3C)
          : Color.lerp(surfaceFor(Brightness.dark), Colors.white, 0.12)!;

  /// Creates a palette from one to three opaque RGB colors.
  ///
  /// The first color is the accent, the second is the light surface, and the
  /// third is the light background. Missing semantic colors use the Base
  /// defaults, which keeps the custom palette useful while enforcing the
  /// three-color maximum requested by the profile editor.
  factory AppPalette.fromCustomColors(List<Color> colors) {
    if (colors.isEmpty || colors.length > 3) {
      throw ArgumentError('A custom palette must contain 1 to 3 colors');
    }
    if (colors.any((color) => (color.a * 255).round() != 255)) {
      throw ArgumentError('Custom palette colors must be opaque');
    }
    if (colors.toSet().length != colors.length) {
      throw ArgumentError('Custom palette colors must be unique');
    }

    return AppPalette._(
      primary: colors[0],
      surfaceLight: colors.length > 1 ? colors[1] : base.surfaceLight,
      backgroundLight: colors.length > 2 ? colors[2] : base.backgroundLight,
      customColorCount: colors.length,
    );
  }

  /// Serializes an opaque color as a stable six-digit RGB hex string.
  static String colorToHex(Color color) {
    return color
        .toARGB32()
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2)
        .toUpperCase();
  }

  /// Parses `#RRGGBB` (or `RRGGBB`) without accepting alpha values.
  static Color? tryParseHex(String value) {
    final normalized = value.trim().replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) return null;
    final parsed = int.tryParse(normalized, radix: 16);
    return parsed == null ? null : Color(0xFF000000 | parsed);
  }

  static Color _deriveDark(Color color, {bool brighten = false}) {
    final target = brighten ? Colors.white : Colors.black;
    return Color.lerp(color, target, brighten ? 0.2 : 0.72)!;
  }

  @override
  bool operator ==(Object other) {
    return other is AppPalette &&
        other.primary == primary &&
        other.surfaceLight == surfaceLight &&
        other.backgroundLight == backgroundLight &&
        other.primaryDark == primaryDark &&
        other.surfaceDark == surfaceDark &&
        other.backgroundDark == backgroundDark &&
        other._customColorCount == _customColorCount;
  }

  @override
  int get hashCode => Object.hash(
    primary,
    surfaceLight,
    backgroundLight,
    primaryDark,
    surfaceDark,
    backgroundDark,
    _customColorCount,
  );
}

/// App color system — three semantic colors, Material 3 compliant.
///
/// The getters intentionally remain source-compatible with existing widgets.
/// [applyPalette] updates them before SettingsProvider notifies listeners.
class AppColors {
  static AppPalette _palette = AppPalette.base;

  static AppPalette get palette => _palette;

  static void applyPalette(AppPalette palette) {
    _palette = palette;
  }

  static Color get primary => _palette.primary;
  static Color get surfaceLight => _palette.surfaceLight;
  static Color get surfaceDark => _palette.surfaceFor(Brightness.dark);
  static Color get bgLight => _palette.backgroundLight;
  static Color get bgDark => _palette.backgroundFor(Brightness.dark);

  static Color get navLight => surfaceLight;
  static Color get navDark => _palette.navigationDark;
  static Color get sheetLight => surfaceLight;
  static Color get sheetDark => _palette.sheetDark;
  static Color get surfaceSecondaryLight => _palette.surfaceSecondaryLight;
  static Color get surfaceSecondaryDark => _palette.surfaceSecondaryDark;

  static const Color textLight = Color(0xFF000000);
  static const Color textDark = Color(0xFFFFFFFF);
  static const Color textSecondaryLight = Color(0xFF6B7280);
  static const Color textSecondaryDark = Color(0xFF8E8E93);
}

class AppTheme {
  // ── Figma exact spacing constants ─────────────────────────
  static const double pillRadius = 28.0;
  static const double fabRadius = 16.0;
  static const double menuRadius = 16.0;
  static const double checkRadius = 8.0;
  static const double checkRadiusDone = 6.0;
  static const double sheetHandleRadius = 2.0;

  // ── Figma exact padding/gap constants ─────────────────────
  static const double rowPadH = 20.0;
  static const double rowPadV = 15.0;
  static const double rowGap = 10.0;
  static const double rowHeight = 56.0;
  static const double rowWidth = 328.0;
  static const double screenPad = 16.0;

  static const double navHeight = 100.0;
  static const double navPadTop = 14.0;
  static const double navPadBottom = 24.0;

  static const double fabSize = 56.0;
  static const double scrollHideThreshold = 2.0;

  static const double sheetGap = 72.0;
  static const double sheetPadH = 16.0;
  static const double sheetPadTop = 20.0;

  static const double menuItemGap = 6.0;
  static const double menuItemPad = 10.0;
  static const double menuItemGapInner = 10.0;
  static const double popupMenuGap = 6.0;

  static ThemeData get lightTheme =>
      _build(Brightness.light, AppColors.palette);
  static ThemeData get darkTheme => _build(Brightness.dark, AppColors.palette);

  static ThemeData lightThemeFor(AppPalette palette) =>
      _build(Brightness.light, palette);

  static ThemeData darkThemeFor(AppPalette palette) =>
      _build(Brightness.dark, palette);

  static ThemeData _build(Brightness brightness, AppPalette palette) {
    final isDark = brightness == Brightness.dark;
    final bg = palette.backgroundFor(brightness);
    final surface = palette.surfaceFor(brightness);
    final primary = palette.primaryFor(brightness);
    final onSurface = isDark ? AppColors.textDark : AppColors.textLight;
    final baseTypography = Typography.material2021();

    return ThemeData(
      brightness: brightness,
      primaryColor: primary,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary:
            primary.computeLuminance() > 0.5 ? Colors.black : Colors.white,
        secondary: isDark ? palette.navigationDark : palette.surfaceLight,
        onSecondary: isDark ? Colors.white : Colors.black,
        surface: surface,
        onSurface: onSurface,
        error: Colors.redAccent,
        onError: Colors.white,
      ),
      textTheme: (isDark ? baseTypography.white : baseTypography.black).apply(
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
        backgroundColor: isDark ? surface : bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: InputBorder.none,
        hintStyle: TextStyle(
          color:
              isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
          fontSize: 16,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? surface : const Color(0xFF323232),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
