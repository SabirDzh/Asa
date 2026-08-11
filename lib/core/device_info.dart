import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Returns a human-readable device name/model using the platform's device
/// info. Falls back to 'ASA Device' if the info cannot be retrieved.
Future<String> getDefaultDeviceName() async {
  try {
    final deviceInfo = DeviceInfoPlugin();
    if (kIsWeb) return 'ASA Web';
    if (Platform.isAndroid) {
      final android = await deviceInfo.androidInfo;
      final manufacturer = android.manufacturer.trim();
      final model = android.model.trim();
      final parts = <String>[
        if (manufacturer.isNotEmpty &&
            !model.toLowerCase().contains(manufacturer.toLowerCase()))
          manufacturer,
        if (model.isNotEmpty) model,
      ];
      return parts.isNotEmpty ? parts.join(' ') : 'ASA Device';
    }
    if (Platform.isIOS) {
      final ios = await deviceInfo.iosInfo;
      // On iOS 16+ the user-assigned name may be redacted without the
      // com.apple.developer.device-information.user-assigned-device-name
      // entitlement. Use the model as a reliable fallback.
      final name = ios.name.trim();
      if (name.isNotEmpty && name != 'iPhone' && name != 'iPad') {
        return name;
      }
      return ios.model.isNotEmpty ? ios.model : 'ASA Device';
    }
    if (Platform.isMacOS) {
      final mac = await deviceInfo.macOsInfo;
      return mac.computerName.isNotEmpty ? mac.computerName : 'ASA Mac';
    }
    if (Platform.isWindows) {
      final windows = await deviceInfo.windowsInfo;
      return windows.computerName.isNotEmpty
          ? windows.computerName
          : 'ASA Windows';
    }
    if (Platform.isLinux) {
      final linux = await deviceInfo.linuxInfo;
      return linux.prettyName.isNotEmpty ? linux.prettyName : 'ASA Linux';
    }
  } catch (_) {}
  return 'ASA Device';
}

/// Returns only a non-user-assigned platform/model label for diagnostics.
/// This intentionally avoids sending a personal device name from iOS.
Future<String> getDiagnosticDeviceName() async {
  try {
    final deviceInfo = DeviceInfoPlugin();
    if (kIsWeb) return 'Web';
    if (Platform.isAndroid) {
      final android = await deviceInfo.androidInfo;
      final manufacturer = android.manufacturer.trim();
      final model = android.model.trim();
      final parts = <String>[
        if (manufacturer.isNotEmpty) manufacturer,
        if (model.isNotEmpty) model,
      ];
      return parts.join(' ').trim().isNotEmpty
          ? parts.join(' ').trim()
          : 'Android device';
    }
    if (Platform.isIOS) {
      final ios = await deviceInfo.iosInfo;
      return ios.model.trim().isNotEmpty ? ios.model.trim() : 'iOS device';
    }
    if (Platform.isMacOS) {
      final mac = await deviceInfo.macOsInfo;
      return mac.model.trim().isNotEmpty ? mac.model.trim() : 'Mac';
    }
    if (Platform.isWindows) {
      final windows = await deviceInfo.windowsInfo;
      return windows.productName.trim().isNotEmpty
          ? windows.productName.trim()
          : 'Windows device';
    }
    if (Platform.isLinux) {
      final linux = await deviceInfo.linuxInfo;
      return linux.prettyName.trim().isNotEmpty
          ? linux.prettyName.trim()
          : 'Linux device';
    }
  } catch (_) {}
  return 'ASA device';
}
