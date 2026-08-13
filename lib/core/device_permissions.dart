import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin wrapper around the Android platform channel for optional device-level
/// permissions.
///
/// All methods are no-ops on non-Android platforms.
class DevicePermissions {
  DevicePermissions._();

  static const _channel = MethodChannel('asa/notifications');

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
}
