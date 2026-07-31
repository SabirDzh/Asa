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
