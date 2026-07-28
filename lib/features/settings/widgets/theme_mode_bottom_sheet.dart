import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../providers/settings_provider.dart';

String themeModeLabel(SettingsProvider settings) {
  switch (settings.themeMode) {
    case ThemeMode.light:
      return settings.tr('theme_light');
    case ThemeMode.dark:
      return settings.tr('theme_dark');
    case ThemeMode.system:
      return settings.tr('theme_system');
  }
}

void showThemeModeSheet(BuildContext context) {
  final settings = Provider.of<SettingsProvider>(context, listen: false);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final sheetBg = isDark ? AppColors.sheetDark : AppColors.sheetLight;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            settings.tr('theme'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _themeTile(ctx, settings, ThemeMode.light, 'theme_light', Iconsax.sun_1),
          _themeTile(ctx, settings, ThemeMode.dark, 'theme_dark', Iconsax.moon),
          _themeTile(ctx, settings, ThemeMode.system, 'theme_system', Iconsax.magicpen),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Widget _themeTile(
  BuildContext ctx,
  SettingsProvider settings,
  ThemeMode mode,
  String labelKey,
  IconData icon,
) {
  final isSelected = settings.themeMode == mode;
  return Material(
    color: Colors.transparent,
    child: ListTile(
      leading: Icon(icon, color: Colors.white, size: 24),
      title: Text(
        settings.tr(labelKey),
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      trailing: isSelected
          ? const Icon(Icons.check, color: AppColors.primary)
          : null,
      onTap: () {
        settings.setThemeMode(mode);
        Navigator.pop(ctx);
      },
    ),
  );
}
