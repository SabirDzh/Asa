import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../core/theme_switcher.dart';
import '../providers/settings_provider.dart';
import '../widgets/setting_row.dart';
import '../widgets/avatar_section.dart';
import '../widgets/language_bottom_sheet.dart';
import '../widgets/animation_speed_bottom_sheet.dart';
import '../widgets/data_management_bottom_sheet.dart';
import '../widgets/about_bottom_sheet.dart';
import '../widgets/widget_mode_bottom_sheet.dart';
import '../widgets/app_scale_bottom_sheet.dart';

class SettingsScreen extends StatelessWidget {
  final bool standalone;
  const SettingsScreen({super.key, this.standalone = true});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgDark : AppColors.bgLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const SizedBox(height: 40),
            const AvatarSection(),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.screenPad),
              child: Column(
                children: [
                  SettingRow(
                    surface: surface,
                    icon: Iconsax.notification,
                    label: settings.tr('notifications'),
                    textColor: textSecondary,
                    trailing: Switch(
                      value: settings.notificationsEnabled,
                      onChanged: settings.toggleNotifications,
                      activeThumbColor: AppColors.primary,
                      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SettingRow(
                    surface: surface,
                    icon: Iconsax.sun_1,
                    label: settings.tr('theme'),
                    textColor: textSecondary,
                    trailing: Builder(
                      builder: (switchCtx) {
                        return Switch(
                          value: settings.isDarkMode,
                          onChanged: (_) {
                            final box = switchCtx.findRenderObject() as RenderBox?;
                            final center = box != null
                                ? box.localToGlobal(box.size.center(Offset.zero))
                                : Offset(
                                    MediaQuery.of(switchCtx).size.width / 2,
                                    MediaQuery.of(switchCtx).size.height / 2,
                                  );
                            ThemeSwitcher.switchTheme(
                              context: switchCtx,
                              center: center,
                              onToggle: () => settings.toggleTheme(),
                              animationSpeed: settings.animationSpeed,
                            );
                          },
                          activeThumbColor: AppColors.primary,
                          trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  SettingRow(
                    surface: surface,
                    icon: Iconsax.category,
                    label: settings.tr('show_in_widget'),
                    textColor: textSecondary,
                    trailing: Switch(
                      value: settings.showInWidget,
                      onChanged: settings.setShowInWidget,
                      activeThumbColor: AppColors.primary,
                      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SettingRow(
                    surface: surface,
                    icon: Iconsax.candle,
                    label: '${settings.tr('widget_mode')}: ${settings.widgetModeLabel(settings.widgetDisplayMode)}',
                    textColor: textSecondary,
                    onTap: settings.showInWidget ? () => showWidgetModeSheet(context) : null,
                    trailing: Icon(Icons.chevron_right, color: textSecondary, size: 22),
                  ),
                  const SizedBox(height: 8),
                  SettingRow(
                    surface: surface,
                    icon: Iconsax.data,
                    label: settings.tr('data_management'),
                    textColor: textSecondary,
                    onTap: () => showDataManagementSheet(context),
                    trailing: Icon(Icons.chevron_right, color: textSecondary, size: 22),
                  ),
                  const SizedBox(height: 8),
                  SettingRow(
                    surface: surface,
                    icon: Iconsax.language_square,
                    label: '${settings.tr('language')}: ${settings.tr('lang_name')}',
                    textColor: textSecondary,
                    onTap: () => showLanguageSheet(context),
                    trailing: Icon(Icons.chevron_right, color: textSecondary, size: 22),
                  ),
                  const SizedBox(height: 8),
                  SettingRow(
                    surface: surface,
                    icon: Iconsax.timer_1,
                    label: '${settings.tr('animation_speed')}: ${animationSpeedLabel(settings)}',
                    textColor: textSecondary,
                    onTap: () => showAnimationSpeedSheet(context),
                    trailing: Icon(Icons.chevron_right, color: textSecondary, size: 22),
                  ),
                  const SizedBox(height: 8),
                  SettingRow(
                    surface: surface,
                    icon: Iconsax.size,
                    label: '${settings.tr('app_scale')}: ${appScaleLabel(context, settings)}',
                    textColor: textSecondary,
                    onTap: () => showAppScaleSheet(context),
                    trailing: Icon(Icons.chevron_right, color: textSecondary, size: 22),
                  ),
                  const SizedBox(height: 8),
                  SettingRow(
                    surface: surface,
                    icon: Iconsax.info_circle,
                    label: settings.tr('about'),
                    textColor: textSecondary,
                    onTap: () => showAboutSheet(context),
                    trailing: Icon(Icons.chevron_right, color: textSecondary, size: 22),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

