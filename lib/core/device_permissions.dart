import 'dart:io';

import 'package:flutter/services.dart';

/// Thin wrapper around Android platform channels that checks and requests
/// device-level permissions required for reliable background notifications.
///
/// All methods are no-ops on non-Android platforms.
class DevicePermissions {
  DevicePermissions._();

  static const _channel = MethodChannel('asa/notifications');

  /// True when the user has granted runtime notification permission.
  /// On Android < 13 this always returns true (no runtime permission needed).
  static Future<bool> areNotificationsGranted() async {
    if (!Platform.isAndroid) return true;
    return (await _channel.invokeMethod<bool>('isNotificationGranted')) ?? true;
  }

  /// True when the app is exempt from battery optimization restrictions.
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    return (await _channel.invokeMethod<bool>(
          'isIgnoringBatteryOptimizations',
        )) ??
        true;
  }

  /// Opens the system dialog to request battery optimization exemption.
  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
  }

  /// Opens the system battery optimization settings screen.
  static Future<void> openBatterySettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openBatterySettings');
  }

  /// True when the OEM exposes an auto-start management page (Xiaomi/HyperOS,
  /// Huawei, Oppo, Vivo, etc.).
  static Future<bool> isAutoStartAvailable() async {
    if (!Platform.isAndroid) return false;
    return (await _channel.invokeMethod<bool>('isAutoStartAvailable')) ?? false;
  }

  /// Opens the OEM auto-start settings page.
  static Future<void> openAutoStartSettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openAutoStartSettings');
  }

  /// Opens the system notification settings for this app.
  static Future<void> openNotificationSettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openNotificationSettings');
  }
}
