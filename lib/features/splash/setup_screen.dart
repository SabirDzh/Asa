import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/device_permissions.dart';
import '../../core/logger_service.dart';
import '../../core/notification_service.dart';
import '../../core/theme.dart';
import '../settings/providers/settings_provider.dart';

/// Shown when background reliability requirements (notifications, exact alarms,
/// battery optimization exemption, or OEM auto-start where supported) are missing.
class SetupScreen extends StatefulWidget {
  final PermissionState? initialState;
  final Future<void> Function()? onPermissionsResolved;

  const SetupScreen({super.key, this.initialState, this.onPermissionsResolved});

  static const _prefsKey = 'asa_setup_completed';

  /// True if the setup screen has never been completed.
  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefsKey) == true) return false;
    final state = await DevicePermissions.getPermissionState();
    return !state.isComplete;
  }

  /// Marks the setup as completed.
  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> with WidgetsBindingObserver {
  late PermissionState _state;
  bool _notificationBusy = false;
  bool _autoStartSettingsPending = false;
  bool _autoStartSettingsWasBackgrounded = false;
  bool _autoStartConfirmationShowing = false;
  bool _permissionResolutionCallbackSent = false;
  Future<void>? _permissionCheckFuture;
  int _permissionCheckGeneration = 0;
  Timer? _autoStartExpiryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state =
        widget.initialState ??
        const PermissionState(
          notificationsGranted: false,
          exactAlarmGranted: false,
          batteryOptimizationDisabled: false,
          autoStartGranted: false,
          autoStartSupported: false,
        );
    unawaited(_checkPermissions());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoStartExpiryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_autoStartSettingsPending) {
        _autoStartSettingsWasBackgrounded = true;
      }
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    if (_autoStartSettingsPending && _autoStartSettingsWasBackgrounded) {
      _autoStartSettingsPending = false;
      _autoStartSettingsWasBackgrounded = false;
      _autoStartExpiryTimer?.cancel();
      _autoStartExpiryTimer = null;
      unawaited(_confirmAutoStartAfterReturn());
      return;
    }
    unawaited(_checkPermissions());
  }

  Future<void> _checkPermissions() {
    final previous = _permissionCheckFuture ?? Future<void>.value();
    final generation = ++_permissionCheckGeneration;
    final check = previous.then((_) async {
      final newState = await DevicePermissions.getPermissionState();
      if (!mounted || generation != _permissionCheckGeneration) return;
      setState(() {
        _state = newState;
      });
      if (newState.isComplete) {
        await _notifyPermissionsResolved();
      } else {
        _permissionResolutionCallbackSent = false;
      }
    });
    final guarded = check.catchError((Object error, StackTrace stackTrace) {
      LoggerService.instance.w(
        'Setup permission check failed',
        error: error,
        stackTrace: stackTrace,
      );
    });
    _permissionCheckFuture = guarded;
    unawaited(
      guarded.then<void>((_) {
        if (identical(_permissionCheckFuture, guarded)) {
          _permissionCheckFuture = null;
        }
      }),
    );
    return guarded;
  }

  Future<void> _notifyPermissionsResolved() async {
    if (widget.onPermissionsResolved == null ||
        _permissionResolutionCallbackSent) {
      return;
    }
    _permissionResolutionCallbackSent = true;
    try {
      await widget.onPermissionsResolved!();
    } on Object catch (error, stackTrace) {
      // Allow a later retry if the parent gate failed to refresh after the
      // permission callback. The setup screen remains usable in that case.
      _permissionResolutionCallbackSent = false;
      LoggerService.instance.w(
        'Permission resolution callback failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> _finish() async {
    await SetupScreen.markCompleted();
    if (widget.onPermissionsResolved != null) {
      await _notifyPermissionsResolved();
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgDark : AppColors.bgLight;
    final textColor = isDark ? AppColors.textDark : AppColors.textLight;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    final isComplete = _state.isComplete;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 24),
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
                      if (_state.permissionCheckFailed) ...[
                        const SizedBox(height: 16),
                        Text(
                          settings.tr('setup_permission_check_failed'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: secondary, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: _checkPermissions,
                          child: Text(settings.tr('retry')),
                        ),
                      ],
                      const SizedBox(height: 24),
                      _permissionTile(
                        icon: Icons.notifications_outlined,
                        label: settings.tr('notifications'),
                        granted: _state.notificationsGranted,
                        busy: _notificationBusy,
                        onFix: _requestNotificationPermission,
                      ),
                      const SizedBox(height: 12),
                      _permissionTile(
                        icon: Icons.alarm_on_outlined,
                        label: settings.tr('setup_exact_alarm'),
                        subtitle: settings.tr('setup_exact_alarm_subtitle'),
                        granted: _state.exactAlarmGranted,
                        onFix: () async {
                          await DevicePermissions.openExactAlarmSettings();
                          await _checkPermissions();
                        },
                      ),
                      const SizedBox(height: 12),
                      _permissionTile(
                        icon: Icons.battery_5_bar_outlined,
                        label: settings.tr('setup_battery'),
                        subtitle: settings.tr('setup_battery_subtitle'),
                        granted: _state.batteryOptimizationDisabled,
                        onFix: () async {
                          await DevicePermissions.requestIgnoreBatteryOptimizations();
                          await _checkPermissions();
                        },
                      ),
                      if (_state.autoStartSupported) ...[
                        const SizedBox(height: 12),
                        _permissionTile(
                          icon: Icons.restart_alt_outlined,
                          label: settings.tr('setup_autostart'),
                          subtitle: settings.tr('setup_autostart_subtitle'),
                          granted: _state.autoStartGranted,
                          onFix: _openAutoStartSettings,
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isComplete ? _finish : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor:
                        isComplete
                            ? AppColors.primary
                            : secondary.withValues(alpha: 0.2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    isComplete
                        ? settings.tr('setup_continue')
                        : settings.tr('setup_grant_all'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isComplete ? AppColors.textDark : secondary,
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

  Future<void> _requestNotificationPermission() async {
    final settings = context.read<SettingsProvider>();
    setState(() => _notificationBusy = true);
    try {
      var granted = false;
      try {
        // Exact alarms have their own tile below. Keep this request limited
        // to notifications so Android cannot navigate to two system screens
        // in one tap.
        granted = await NotificationService.requestPermission(
          requestExactAlarms: false,
        );
      } on Object catch (error, stackTrace) {
        // A platform/plugin failure must never look like a successful request
        // or leave the screen without feedback.
        LoggerService.instance.w(
          'Notification permission request failed on setup screen',
          error: error,
          stackTrace: stackTrace,
        );
      }
      if (granted) {
        // Enabling the in-app flag also persists it and schedules reminders;
        // without this the runtime permission alone left reminders disabled.
        try {
          await settings.toggleNotifications(true);
        } on Object catch (error, stackTrace) {
          // The runtime permission was already granted; the tile will reflect
          // it. Do not claim the permission was denied.
          LoggerService.instance.w(
            'Failed to enable notifications after grant',
            error: error,
            stackTrace: stackTrace,
          );
        }
      } else {
        final permanentlyDenied =
            await NotificationService.isPermissionPermanentlyDenied();
        if (permanentlyDenied) {
          _showSnack(settings.tr('setup_notification_permanently_denied'));
          await NotificationService.openNotificationSettings();
        } else {
          _showSnack(settings.tr('setup_notification_denied'));
        }
      }
      await _checkPermissions();
    } finally {
      if (mounted) setState(() => _notificationBusy = false);
    }
  }

  Future<void> _openAutoStartSettings() async {
    if (_autoStartSettingsPending) return;
    _autoStartSettingsPending = true;
    _autoStartSettingsWasBackgrounded = false;
    _autoStartExpiryTimer?.cancel();
    _autoStartExpiryTimer = Timer(const Duration(seconds: 30), () {
      _autoStartSettingsPending = false;
      _autoStartSettingsWasBackgrounded = false;
      _autoStartExpiryTimer = null;
    });
    try {
      await DevicePermissions.openAutoStartSettings();
    } on Object catch (error, stackTrace) {
      _autoStartSettingsPending = false;
      _autoStartExpiryTimer?.cancel();
      _autoStartExpiryTimer = null;
      LoggerService.instance.w(
        'Failed to open auto-start settings',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        _showSnack(
          context.read<SettingsProvider>().tr('setup_autostart_failed'),
        );
      }
    }
  }

  Future<void> _confirmAutoStartAfterReturn() async {
    if (!mounted || _autoStartConfirmationShowing) return;
    _autoStartConfirmationShowing = true;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final settings = context.read<SettingsProvider>();
        return AlertDialog(
          title: Text(settings.tr('setup_autostart_confirm_title')),
          content: Text(settings.tr('setup_autostart_confirm_content')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(settings.tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(settings.tr('setup_autostart_confirm')),
            ),
          ],
        );
      },
    );
    _autoStartConfirmationShowing = false;
    if (!mounted) return;
    if (confirmed == true) {
      await DevicePermissions.markAutoStartConfirmed();
    }
    await _checkPermissions();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _permissionTile({
    required IconData icon,
    required String label,
    String? subtitle,
    required bool granted,
    bool busy = false,
    VoidCallback? onFix,
  }) {
    final settings = context.read<SettingsProvider>();
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
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Semantics(
                  label:
                      '$label, ${settings.tr(granted ? 'setup_permission_granted' : 'setup_permission_not_granted')}',
                  image: true,
                  child: Icon(
                    granted ? Icons.check_circle : icon,
                    color: granted ? AppColors.primary : secondary,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
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
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (!granted && onFix != null) ...[
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child:
                  busy
                      ? const SizedBox(
                        width: 32,
                        height: 32,
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                      : TextButton(
                        onPressed: onFix,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: Text(
                          context.watch<SettingsProvider>().tr('setup_enable'),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
            ),
          ],
        ],
      ),
    );
  }
}
