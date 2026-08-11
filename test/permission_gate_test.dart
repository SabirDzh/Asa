import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:asa/core/device_permissions.dart';
import 'package:asa/core/permission_gate.dart';
import 'package:asa/features/settings/providers/settings_provider.dart';
import 'package:asa/features/splash/setup_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'languageCode': 'ru'});
  });

  tearDown(() {
    DevicePermissions.permissionStateOverride = null;
  });

  Widget createTestWidget({required Widget child}) {
    return ChangeNotifierProvider(
      create: (_) => SettingsProvider(),
      child: MaterialApp(home: PermissionGate(child: child)),
    );
  }

  group('PermissionGate Widget', () {
    testWidgets('renders child when all permissions are granted', (
      tester,
    ) async {
      DevicePermissions.permissionStateOverride = const PermissionState(
        notificationsGranted: true,
        exactAlarmGranted: true,
        batteryOptimizationDisabled: true,
        autoStartGranted: true,
        autoStartSupported: true,
      );

      await tester.pumpWidget(
        createTestWidget(child: const Text('Home Screen Content')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Home Screen Content'), findsOneWidget);
    });

    testWidgets('renders SetupScreen when any permission is missing', (
      tester,
    ) async {
      DevicePermissions.permissionStateOverride = const PermissionState(
        notificationsGranted: false,
        exactAlarmGranted: true,
        batteryOptimizationDisabled: true,
        autoStartGranted: true,
        autoStartSupported: true,
      );

      await tester.pumpWidget(
        createTestWidget(child: const Text('Home Screen Content')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Home Screen Content'), findsNothing);
      expect(find.byType(SetupScreen), findsOneWidget);
    });

    testWidgets('updates dynamically when permissions change on resume', (
      tester,
    ) async {
      DevicePermissions.permissionStateOverride = const PermissionState(
        notificationsGranted: false,
        exactAlarmGranted: true,
        batteryOptimizationDisabled: true,
        autoStartGranted: true,
        autoStartSupported: true,
      );

      await tester.pumpWidget(
        createTestWidget(child: const Text('Home Screen Content')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Home Screen Content'), findsNothing);

      // Simulate permissions granted externally
      DevicePermissions.permissionStateOverride = const PermissionState(
        notificationsGranted: true,
        exactAlarmGranted: true,
        batteryOptimizationDisabled: true,
        autoStartGranted: true,
        autoStartSupported: true,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Home Screen Content'), findsOneWidget);
    });
  });
}
