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

  const PermissionState({
    required this.notificationsGranted,
    required this.exactAlarmGranted,
    required this.batteryOptimizationDisabled,
    required this.autoStartGranted,
    required this.autoStartSupported,
  });

  /// True when all required permissions and settings are satisfied.
  /// OEM Auto-Start is required ONLY if the device supports it.
  bool get isComplete {
    return notificationsGranted &&
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
      final autoStartDone = prefs.getBool('asa_autostart_visited') ?? false;

      final notifications = await areNotificationsGranted();
      final exactAlarm = await isExactAlarmGranted();
      final battery = await isIgnoringBatteryOptimizations();
      final autoStartSupported = await isAutoStartAvailable();

      return PermissionState(
        notificationsGranted: notifications,
        exactAlarmGranted: exactAlarm,
        batteryOptimizationDisabled: battery,
        autoStartGranted: autoStartDone,
        autoStartSupported: autoStartSupported,
      );
    } on Object {
      return const PermissionState(
        notificationsGranted: true,
        exactAlarmGranted: true,
        batteryOptimizationDisabled: true,
        autoStartGranted: true,
        autoStartSupported: false,
      );
    }
  }

  /// True when the user has granted runtime notification permission.
  /// On Android < 13 this always returns true (no runtime permission needed).
  static Future<bool> areNotificationsGranted() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      return (await _channel.invokeMethod<bool>('isNotificationGranted')) ??
          true;
    } on MissingPluginException {
      return true;
    }
  }

  /// True when exact alarm scheduling is granted.
  /// On Android < 12 (API 31-) this always returns true.
  static Future<bool> isExactAlarmGranted() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      return (await _channel.invokeMethod<bool>('isExactAlarmGranted')) ?? true;
    } on MissingPluginException {
      return true;
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
          true;
    } on MissingPluginException {
      return true;
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
  static Future<bool> isAutoStartAvailable() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return (await _channel.invokeMethod<bool>('isAutoStartAvailable')) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the OEM auto-start settings page.
  static Future<void> openAutoStartSettings() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('asa_autostart_visited', true);
      await _channel.invokeMethod<void>('openAutoStartSettings');
    } on MissingPluginException {
      // No-op
    }
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
