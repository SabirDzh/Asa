import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Structured snapshot of all background-reliability permissions and settings.
class PermissionState {
  final bool notificationsGranted;
  final bool exactAlarmGranted;
  final bool batteryOptimizationDisabled;
  final bool autoStartGranted;
  final bool autoStartSupported;

  /// True when the platform could not reliably read the permission state.
  /// A failed check is deliberately not treated as granted.
  final bool permissionCheckFailed;

  /// True when the OEM auto-start capability probe failed. This is separate
  /// from `autoStartSupported == false`, which means the probe completed and
  /// the device genuinely does not expose that setting.
  final bool autoStartCheckFailed;

  const PermissionState({
    required this.notificationsGranted,
    required this.exactAlarmGranted,
    required this.batteryOptimizationDisabled,
    required this.autoStartGranted,
    required this.autoStartSupported,
    this.permissionCheckFailed = false,
    this.autoStartCheckFailed = false,
  });

  /// True when all required permissions and settings are satisfied.
  /// OEM Auto-Start is required ONLY if the device supports it.
  bool get isComplete {
    return !permissionCheckFailed &&
        !autoStartCheckFailed &&
        notificationsGranted &&
        exactAlarmGranted &&
        batteryOptimizationDisabled &&
        (!autoStartSupported || autoStartGranted);
  }
}

/// Thin wrapper around Android platform channels that checks and requests
/// device-level permissions required for reliable background notifications.
///
/// All methods are no-ops on non-Android platforms.
class DevicePermissions {
  DevicePermissions._();

  static const _channel = MethodChannel('asa/notifications');

  @visibleForTesting
  static PermissionState? permissionStateOverride;

  @visibleForTesting
  static Future<bool> Function()? localNetworkPermissionOverride;

  @visibleForTesting
  static Future<void> Function()? openAutoStartSettingsOverride;

  static const _autoStartConfirmedKey = 'asa_autostart_confirmed';

  /// Requests the Android permission needed by the mDNS sync transport.
  ///
  /// Android 13+ uses NEARBY_WIFI_DEVICES; older supported Android versions
  /// use ACCESS_FINE_LOCATION because Wi-Fi/mDNS discovery is location-gated.
  /// The permission is requested only when the user enables sync. It is not a
  /// mandatory startup permission because sync itself is optional.
  static Future<bool> requestLocalNetworkPermission() async {
    final override = localNetworkPermissionOverride;
    if (override != null) return override();
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      return (await _channel.invokeMethod<bool>(
            'requestLocalNetworkPermission',
          )) ??
          false;
    } on MissingPluginException {
      // A missing native method means this build cannot support local-network
      // discovery. Do not enable sync while the transport is unavailable.
      return false;
    } on Object {
      return false;
    }
  }

  /// Opens the app's page in system settings. Used for permission recovery
  /// flows where the platform no longer shows a runtime dialog.
  static Future<void> openAppSettings() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } on MissingPluginException {
      // No-op in unsupported/test environments.
    } on Object {
      // A settings activity may be unavailable on a restricted OEM build.
    }
  }

  /// Returns the comprehensive permission state for this device.
  static Future<PermissionState> getPermissionState() async {
    final override = permissionStateOverride;
    if (override != null) return override;

    if (kIsWeb || !Platform.isAndroid) {
      final notifications = await areNotificationsGranted();
      return PermissionState(
        notificationsGranted: notifications,
        exactAlarmGranted: true,
        batteryOptimizationDisabled: true,
        autoStartGranted: true,
        autoStartSupported: false,
      );
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      // `asa_autostart_visited` was written merely by opening OEM settings in
      // older builds. Ignore it so an update cannot treat an unverified visit
      // as a real permission grant.
      final autoStartDone = prefs.getBool(_autoStartConfirmedKey) ?? false;

      final notifications = await areNotificationsGranted();
      final exactAlarm = await isExactAlarmGranted();
      final battery = await isIgnoringBatteryOptimizations();
      final autoStartProbe = await _probeAutoStartAvailability();
      if (autoStartProbe == null) {
        return const PermissionState(
          notificationsGranted: false,
          exactAlarmGranted: false,
          batteryOptimizationDisabled: false,
          autoStartGranted: false,
          autoStartSupported: false,
          permissionCheckFailed: true,
          autoStartCheckFailed: true,
        );
      }

      return PermissionState(
        notificationsGranted: notifications,
        exactAlarmGranted: exactAlarm,
        batteryOptimizationDisabled: battery,
        autoStartGranted: autoStartDone,
        autoStartSupported: autoStartProbe,
      );
    } on Object {
      // A failed platform/preference read is an unknown state, never a grant.
      // Keep the setup gate visible so the user can retry or inspect settings.
      return const PermissionState(
        notificationsGranted: false,
        exactAlarmGranted: false,
        batteryOptimizationDisabled: false,
        autoStartGranted: false,
        autoStartSupported: false,
        permissionCheckFailed: true,
      );
    }
  }

  /// True when the user has granted runtime notification permission.
  /// On Android < 13 this always returns true (no runtime permission needed).
  static Future<bool> areNotificationsGranted() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      return (await _channel.invokeMethod<bool>('isNotificationGranted')) ??
          false;
    } on MissingPluginException {
      return false;
    } on Object {
      return false;
    }
  }

  /// True when exact alarm scheduling is granted.
  /// On Android < 12 (API 31-) this always returns true.
  static Future<bool> isExactAlarmGranted() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      return (await _channel.invokeMethod<bool>('isExactAlarmGranted')) ??
          false;
    } on MissingPluginException {
      return false;
    } on Object {
      return false;
    }
  }

  /// Opens the system exact alarm settings screen.
  static Future<void> openExactAlarmSettings() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openExactAlarmSettings');
    } on MissingPluginException {
      // No-op in unsupported environments.
    }
  }

  /// True when the app is exempt from battery optimization restrictions.
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      return (await _channel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          )) ??
          false;
    } on MissingPluginException {
      return false;
    } on Object {
      return false;
    }
  }

  /// Opens the system dialog to request battery optimization exemption.
  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
    } on MissingPluginException {
      // No-op
    }
  }

  /// Opens the system battery optimization settings screen.
  static Future<void> openBatterySettings() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openBatterySettings');
    } on MissingPluginException {
      // No-op
    }
  }

  /// True when the OEM exposes an auto-start management page (Xiaomi/HyperOS,
  /// Huawei, Oppo, Vivo, etc.).
  static Future<bool?> _probeAutoStartAvailability() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isAutoStartAvailable');
      return result;
    } on Object {
      // A probe failure is unknown, not proof that the OEM setting is absent.
      return null;
    }
  }

  static Future<bool> isAutoStartAvailable() async {
    return (await _probeAutoStartAvailability()) ?? false;
  }

  /// Opens the OEM auto-start settings page without claiming that the user
  /// enabled anything. The caller must obtain explicit confirmation after the
  /// user returns from system settings.
  static Future<void> openAutoStartSettings() async {
    final override = openAutoStartSettingsOverride;
    if (override != null) {
      await override();
      return;
    }
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openAutoStartSettings');
    } on MissingPluginException {
      // No-op
    }
  }

  /// Records an explicit in-app confirmation that auto-start was enabled.
  /// OEM settings do not expose a portable read API, so this is intentionally
  /// separate from [openAutoStartSettings] and is never written automatically.
  static Future<void> markAutoStartConfirmed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoStartConfirmedKey, true);
  }

  /// Opens the system notification settings for this app.
  static Future<void> openNotificationSettings() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openNotificationSettings');
    } on MissingPluginException {
      // No-op
    }
  }
}
