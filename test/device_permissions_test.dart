import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:asa/core/device_permissions.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DevicePermissions.permissionStateOverride = null;
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
  });
}
