import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../settings/providers/settings_provider.dart';

/// Asks whether the user wants to keep a task event that overlaps an existing
/// calendar event. Returning false also covers dialog dismissal.
Future<bool> showCalendarConflictDialog(
  BuildContext context,
  SettingsProvider settings,
) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final background = isDark ? AppColors.navDark : AppColors.navLight;
  final textColor = isDark ? AppColors.textDark : AppColors.textLight;
  final secondary =
      isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

  return await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              backgroundColor: background,
              title: Text(
                settings.tr('calendar_conflict_title'),
                style: TextStyle(color: textColor),
              ),
              content: Text(
                settings.tr('calendar_conflict_content'),
                style: TextStyle(color: secondary),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(
                    settings.tr('cancel'),
                    style: TextStyle(color: secondary),
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(settings.tr('calendar_conflict_continue')),
                ),
              ],
            ),
      ) ??
      false;
}

void showCalendarOperationError(
  BuildContext context,
  SettingsProvider settings,
) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(settings.tr('calendar_update_failed'))),
  );
}
