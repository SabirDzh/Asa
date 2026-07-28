import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../../../core/theme.dart';

void showWidgetModeSheet(BuildContext context) {
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
            settings.tr('widget_mode'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _modeTile(ctx, settings, WidgetDisplayMode.streak),
          _modeTile(ctx, settings, WidgetDisplayMode.activeTasks),
          _modeTile(ctx, settings, WidgetDisplayMode.lastFolder),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Widget _modeTile(
  BuildContext ctx,
  SettingsProvider settings,
  WidgetDisplayMode mode,
) {
  final isSelected = settings.widgetDisplayMode == mode;
  return Material(
    color: Colors.transparent,
    child: ListTile(
      title: Text(
        settings.widgetModeLabel(mode),
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      trailing: isSelected
          ? const Icon(Icons.check, color: AppColors.primary)
          : null,
      onTap: () {
        settings.setWidgetDisplayMode(mode);
        Navigator.pop(ctx);
      },
    ),
  );
}
