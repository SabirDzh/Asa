import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/device_permissions.dart';
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
import '../widgets/color_palette_bottom_sheet.dart';
import '../../../core/sync_service.dart';
import '../widgets/sync_bottom_sheet.dart' show showSyncBottomSheet;
import '../widgets/notification_settings_bottom_sheet.dart';
import 'whats_new_screen.dart';

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

class SettingsScreen extends StatefulWidget {
  final bool standalone;
  const SettingsScreen({super.key, this.standalone = true});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    if (widget.standalone) {
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void dispose() {
    if (widget.standalone) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  bool _syncBusy = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.standalone && state == AppLifecycleState.resumed && mounted) {
      unawaited(context.read<SettingsProvider>().syncNotificationPermission());
    }
  }

  Future<void> _toggleSync(bool value) async {
    if (_syncBusy) return;
    setState(() => _syncBusy = true);
    try {
      final settings = context.read<SettingsProvider>();
      final tasks = context.read<TaskProvider>();

      if (value) {
        final localNetworkGranted =
            await DevicePermissions.requestLocalNetworkPermission();
        if (!localNetworkGranted) {
          await settings.setSyncEnabled(false);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(settings.tr('sync_permission_denied'))),
          );
          return;
        }
      }

      await settings.setSyncEnabled(value);
      if (!mounted) return;
      if (value) {
        final deviceId = await settings.ensureSyncDeviceId();
        if (!mounted) return;
        SyncService.instance.setProvider(tasks);
        SyncService.instance.setDeviceName(settings.syncDeviceName);
        SyncService.instance.setDeviceId(deviceId);
        SyncService.instance.setSecret(settings.syncSecret);
        final started = await SyncService.instance.start();
        if (!started) {
          await settings.setSyncEnabled(false);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(settings.tr('sync_start_failed'))),
          );
        }
      } else {
        await SyncService.instance.stop();
      }
    } finally {
      if (mounted) setState(() => _syncBusy = false);
    }
  }

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
                  icon: Iconsax.colorfilter,
                  label:
                      '${settings.tr('color_palette')}: ${colorPaletteLabel(settings)}',
                  onTap: () => showColorPaletteSheet(context),
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
                  iconWidget: Icon(
                    Iconsax.timer_1,
                    key: const ValueKey('animation_speed_timer_icon'),
                    color: textSecondary,
                    size: 24,
                  ),
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
                    onChanged: _syncBusy ? null : _toggleSync,
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
                    onChanged:
                        settings.notificationOperationPending
                            ? null
                            : (value) async {
                              final enabled = await settings
                                  .toggleNotifications(value);
                              if (!context.mounted) return;
                              if (value &&
                                  !enabled &&
                                  settings.notificationsBlockedBySystem) {
                                showOpenNotificationSettingsSheet(
                                  context,
                                  settings,
                                );
                              }
                            },
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
                  icon: Iconsax.star,
                  label: settings.tr('whats_new'),
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const WhatsNewScreen(),
                        ),
                      ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: textSecondary,
                    size: 22,
                  ),
                ),
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
