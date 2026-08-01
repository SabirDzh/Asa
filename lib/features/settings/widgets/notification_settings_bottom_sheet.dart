import 'package:flutter/material.dart';

import '../../../core/notification_service.dart';
import '../../../core/theme.dart';
import '../providers/settings_provider.dart';

/// Explains that the notification permission is disabled at the system level
/// and offers to open the system settings, because the permission dialog will
/// never be shown again (Android "don't ask again").
void showOpenNotificationSettingsSheet(
  BuildContext context,
  SettingsProvider settings,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final sheetBg = isDark ? AppColors.sheetDark : AppColors.sheetLight;
  final textColor = isDark ? AppColors.textDark : AppColors.textLight;
  final textSecondary =
      isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder:
        (ctx) => Container(
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
                settings.tr('notifications_permission_needed'),
                style: TextStyle(
                  color: textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                settings.tr('notifications_permission_hint'),
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(settings.tr('cancel')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      NotificationService.openNotificationSettings();
                    },
                    child: Text(settings.tr('open_settings')),
                  ),
                ],
              ),
            ],
          ),
        ),
  );
}
