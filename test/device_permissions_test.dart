import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:asa/core/device_permissions.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DevicePermissions.permissionStateOverride = null;
    DevicePermissions.localNetworkPermissionOverride = null;
    DevicePermissions.openAutoStartSettingsOverride = null;
  });

  group('PermissionState Matrix', () {
    test('isComplete is true when all items are granted', () {
      const state = PermissionState(
        notificationsGranted: true,
        exactAlarmGranted: true,
        batteryOptimizationDisabled: true,
        autoStartGranted: true,
        autoStartSupported: true,
      );
      expect(state.isComplete, isTrue);
    });

    test(
      'isComplete is true when auto-start is unsupported and others granted',
      () {
        const state = PermissionState(
          notificationsGranted: true,
          exactAlarmGranted: true,
          batteryOptimizationDisabled: true,
          autoStartGranted: false,
          autoStartSupported: false,
        );
        expect(state.isComplete, isTrue);
      },
    );

    test('isComplete is false when notifications are missing', () {
      const state = PermissionState(
        notificationsGranted: false,
        exactAlarmGranted: true,
        batteryOptimizationDisabled: true,
        autoStartGranted: true,
        autoStartSupported: true,
      );
      expect(state.isComplete, isFalse);
    });

    test('isComplete is false when exact alarms are missing', () {
      const state = PermissionState(
        notificationsGranted: true,
        exactAlarmGranted: false,
        batteryOptimizationDisabled: true,
        autoStartGranted: true,
        autoStartSupported: true,
      );
      expect(state.isComplete, isFalse);
    });

    test('isComplete is false when battery optimization is enabled', () {
      const state = PermissionState(
        notificationsGranted: true,
        exactAlarmGranted: true,
        batteryOptimizationDisabled: false,
        autoStartGranted: true,
        autoStartSupported: true,
      );
      expect(state.isComplete, isFalse);
    });

    test(
      'isComplete is false when auto-start is supported but not granted',
      () {
        const state = PermissionState(
          notificationsGranted: true,
          exactAlarmGranted: true,
          batteryOptimizationDisabled: true,
          autoStartGranted: false,
          autoStartSupported: true,
        );
        expect(state.isComplete, isFalse);
      },
    );

    test('isComplete is false when auto-start capability probing failed', () {
      const state = PermissionState(
        notificationsGranted: true,
        exactAlarmGranted: true,
        batteryOptimizationDisabled: true,
        autoStartGranted: false,
        autoStartSupported: false,
        autoStartCheckFailed: true,
      );
      expect(state.isComplete, isFalse);
    });
  });

  group('DevicePermissions.getPermissionState', () {
    test('respects permissionStateOverride', () async {
      const override = PermissionState(
        notificationsGranted: false,
        exactAlarmGranted: false,
        batteryOptimizationDisabled: false,
        autoStartGranted: false,
        autoStartSupported: true,
      );
      DevicePermissions.permissionStateOverride = override;
      final result = await DevicePermissions.getPermissionState();
      expect(result.isComplete, isFalse);
      expect(result.notificationsGranted, isFalse);
    });

    test(
      'requests local network permission through the platform hook',
      () async {
        DevicePermissions.localNetworkPermissionOverride = () async => false;

        expect(
          await DevicePermissions.requestLocalNetworkPermission(),
          isFalse,
        );
      },
    );

    test('opening auto-start settings does not grant auto-start', () async {
      var opened = false;
      DevicePermissions.openAutoStartSettingsOverride = () async {
        opened = true;
      };

      await DevicePermissions.openAutoStartSettings();

      final prefs = await SharedPreferences.getInstance();
      expect(opened, isTrue);
      expect(prefs.getBool('asa_autostart_confirmed'), isNull);
      expect(prefs.getBool('asa_autostart_visited'), isNull);
    });

    test('auto-start is persisted only by explicit confirmation', () async {
      await DevicePermissions.markAutoStartConfirmed();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('asa_autostart_confirmed'), isTrue);
    });
  });
}
