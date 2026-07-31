import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../providers/settings_provider.dart';
import '../../tasks/providers/task_provider.dart';
import '../widgets/setting_row.dart';
import '../widgets/setting_group.dart';
import '../widgets/avatar_section.dart';
import '../widgets/language_bottom_sheet.dart';
import '../widgets/animation_speed_bottom_sheet.dart';
import '../widgets/data_management_bottom_sheet.dart';
import '../widgets/about_bottom_sheet.dart';
import '../widgets/widget_mode_bottom_sheet.dart';
import '../widgets/app_scale_bottom_sheet.dart';
import '../widgets/theme_mode_bottom_sheet.dart';
import '../../../core/sync_service.dart';
import '../widgets/sync_bottom_sheet.dart' show showSyncBottomSheet;

IconData _themeModeIcon(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return Iconsax.sun_1;
    case ThemeMode.dark:
      return Iconsax.moon;
    case ThemeMode.system:
      return Iconsax.magicpen;
  }
}

class SettingsScreen extends StatelessWidget {
  final bool standalone;
  const SettingsScreen({super.key, this.standalone = true});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgDark : AppColors.bgLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.screenPad,
            vertical: 24,
          ),
          children: [
            const SizedBox(height: 24),
            const AvatarSection(),
            const SizedBox(height: 32),
            SettingGroup(
              title: settings.tr('appearance'),
              children: [
                SettingRow(
                  icon: _themeModeIcon(settings.themeMode),
                  label: '${settings.tr('theme')}: ${themeModeLabel(settings)}',
                  onTap: () => showThemeModeSheet(context),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: textSecondary,
                    size: 22,
                  ),
                ),
                SettingRow(
                  icon: Iconsax.size,
                  label:
                      '${settings.tr('app_scale')}: ${appScaleLabel(context, settings)}',
                  onTap: () => showAppScaleSheet(context),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: textSecondary,
                    size: 22,
                  ),
                ),
                SettingRow(
                  icon: Iconsax.timer_1,
                  label:
                      '${settings.tr('animation_speed')}: ${animationSpeedLabel(settings)}',
                  onTap: () => showAnimationSpeedSheet(context),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: textSecondary,
                    size: 22,
                  ),
                ),
                SettingRow(
                  icon: Iconsax.language_square,
                  label:
                      '${settings.tr('language')}: ${settings.tr('lang_name')}',
                  onTap: () => showLanguageSheet(context),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: textSecondary,
                    size: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SettingGroup(
              title: settings.tr('widgets'),
              children: [
                SettingRow(
                  icon: Iconsax.category,
                  label: settings.tr('show_in_widget'),
                  trailing: Switch(
                    value: settings.showInWidget,
                    onChanged: settings.setShowInWidget,
                    activeThumbColor: AppColors.primary,
                    trackOutlineColor: WidgetStateProperty.all(
                      Colors.transparent,
                    ),
                  ),
                ),
                SettingRow(
                  icon: Iconsax.candle,
                  label:
                      '${settings.tr('widget_mode')}: ${settings.widgetModeLabel(settings.widgetDisplayMode)}',
                  onTap:
                      settings.showInWidget
                          ? () => showWidgetModeSheet(context)
                          : null,
                  enabled: settings.showInWidget,
                  trailing: Icon(
                    Icons.chevron_right,
                    color: textSecondary,
                    size: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SettingGroup(
              title: settings.tr('sync_and_share'),
              children: [
                SettingRow(
                  icon: Iconsax.refresh,
                  label: settings.tr('sync'),
                  trailing: Switch(
                    value: settings.syncEnabled,
                    onChanged: (value) async {
                      final tasks = Provider.of<TaskProvider>(
                        context,
                        listen: false,
                      );
                      await settings.setSyncEnabled(value);
                      if (!context.mounted) return;
                      if (value) {
                        final deviceId = await settings.ensureSyncDeviceId();
                        if (!context.mounted) return;
                        SyncService.instance.setProvider(tasks);
                        SyncService.instance.setDeviceName(
                          settings.syncDeviceName,
                        );
                        SyncService.instance.setDeviceId(deviceId);
                        SyncService.instance.setSecret(settings.syncSecret);
                        final started = await SyncService.instance.start();
                        if (!started) {
                          await settings.setSyncEnabled(false);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(settings.tr('sync_start_failed')),
                            ),
                          );
                        }
                      } else {
                        await SyncService.instance.stop();
                      }
                    },
                    activeThumbColor: AppColors.primary,
                    trackOutlineColor: WidgetStateProperty.all(
                      Colors.transparent,
                    ),
                  ),
                ),
                SettingRow(
                  icon: Iconsax.profile_2user,
                  label:
                      '${settings.tr('sync_device_name')}: ${settings.syncDeviceName}',
                  onTap:
                      settings.syncEnabled
                          ? () => showSyncBottomSheet(context)
                          : null,
                  enabled: settings.syncEnabled,
                  trailing: Icon(
                    Icons.chevron_right,
                    color: textSecondary,
                    size: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SettingGroup(
              title: settings.tr('notifications_and_data'),
              children: [
                SettingRow(
                  icon: Iconsax.notification,
                  label: settings.tr('notifications'),
                  trailing: Switch(
                    value: settings.notificationsEnabled,
                    onChanged: settings.toggleNotifications,
                    activeThumbColor: AppColors.primary,
                    trackOutlineColor: WidgetStateProperty.all(
                      Colors.transparent,
                    ),
                  ),
                ),
                SettingRow(
                  icon: Iconsax.data,
                  label: settings.tr('data_management'),
                  onTap: () => showDataManagementSheet(context),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: textSecondary,
                    size: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SettingGroup(
              title: settings.tr('other'),
              children: [
                SettingRow(
                  icon: Iconsax.info_circle,
                  label: settings.tr('about'),
                  onTap: () => showAboutSheet(context),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: textSecondary,
                    size: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}
