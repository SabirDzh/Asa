import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/device_permissions.dart';
import '../../core/notification_service.dart';
import '../../core/theme.dart';
import '../settings/providers/settings_provider.dart';

/// Shown once after the first app launch to guide the user through the
/// permissions required for reliable background notifications.
///
/// Checks notification permission, battery optimization exemption, and
/// (on Xiaomi/HyperOS) auto-start access. Each unmet requirement shows a
/// button that opens the relevant system settings page.
///
/// The user can skip this screen at any time.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  static const _prefsKey = 'asa_setup_completed';

  /// True if the setup screen has never been completed.
  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) != true;
  }

  /// Marks the setup as completed so it is not shown again.
  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool _notificationsGranted = true;
  bool _batteryOptimized = true;
  bool _autoStartAvailable = false;

  @override
  void initState() {
    super.initState();
    unawaited(_checkPermissions());
  }

  Future<void> _checkPermissions() async {
    final results = await Future.wait([
      DevicePermissions.areNotificationsGranted(),
      DevicePermissions.isIgnoringBatteryOptimizations(),
      DevicePermissions.isAutoStartAvailable(),
    ]);
    if (!mounted) return;
    setState(() {
      _notificationsGranted = results[0];
      _batteryOptimized = results[1];
      _autoStartAvailable = results[2];
    });
  }

  Future<void> _finish() async {
    await SetupScreen.markCompleted();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgDark : AppColors.bgLight;
    final textColor = isDark ? AppColors.textDark : AppColors.textLight;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    final allResolved = _notificationsGranted && _batteryOptimized;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 1),
              Text(
                'ASA',
                style: TextStyle(
                  color: textColor,
                  fontSize: 48,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                settings.tr('setup_title'),
                style: TextStyle(color: secondary, fontSize: 16),
              ),
              const SizedBox(height: 40),
              _permissionTile(
                icon: Icons.notifications_outlined,
                label: settings.tr('notifications'),
                granted: _notificationsGranted,
                onFix:
                    _notificationsGranted
                        ? null
                        : () async {
                          await NotificationService.requestPermission(
                            requestExactAlarms: true,
                          );
                          await _checkPermissions();
                        },
              ),
              const SizedBox(height: 12),
              _permissionTile(
                icon: Icons.battery_5_bar_outlined,
                label: settings.tr('setup_battery'),
                subtitle: settings.tr('setup_battery_subtitle'),
                granted: _batteryOptimized,
                onFix:
                    _batteryOptimized
                        ? null
                        : () async {
                          await DevicePermissions.requestIgnoreBatteryOptimizations();
                          await _checkPermissions();
                        },
              ),
              if (_autoStartAvailable) ...[
                const SizedBox(height: 12),
                _permissionTile(
                  icon: Icons.restart_alt_outlined,
                  label: settings.tr('setup_autostart'),
                  subtitle: settings.tr('setup_autostart_subtitle'),
                  granted: true,
                  trailing: TextButton(
                    onPressed: () => DevicePermissions.openAutoStartSettings(),
                    child: Text(
                      settings.tr('open_settings'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _finish,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    allResolved
                        ? settings.tr('setup_continue')
                        : settings.tr('setup_skip'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                settings.tr('setup_footer'),
                textAlign: TextAlign.center,
                style: TextStyle(color: secondary, fontSize: 12),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _permissionTile({
    required IconData icon,
    required String label,
    String? subtitle,
    required bool granted,
    VoidCallback? onFix,
    Widget? trailing,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.textDark : AppColors.textLight;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(
            granted ? Icons.check_circle : icon,
            color: granted ? AppColors.primary : secondary,
            size: 28,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: secondary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null)
            trailing
          else if (!granted && onFix != null)
            TextButton(
              onPressed: onFix,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(
                context.read<SettingsProvider>().tr('setup_enable'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}
