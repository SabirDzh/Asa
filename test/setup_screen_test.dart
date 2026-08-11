import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:asa/core/device_permissions.dart';
import 'package:asa/features/settings/providers/settings_provider.dart';
import 'package:asa/features/splash/setup_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'languageCode': 'ru'});
  });

  tearDown(() {
    DevicePermissions.permissionStateOverride = null;
  });

  Widget createSetupScreenWidget() {
    return ChangeNotifierProvider(
      create: (_) => SettingsProvider(),
      child: const MaterialApp(home: SetupScreen()),
    );
  }

  group('SetupScreen State & UI', () {
    test('markCompleted sets preference', () async {
      await SetupScreen.markCompleted();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('asa_setup_completed'), isTrue);
    });

    testWidgets('renders all tiles when all permissions granted', (
      tester,
    ) async {
      DevicePermissions.permissionStateOverride = const PermissionState(
        notificationsGranted: true,
        exactAlarmGranted: true,
        batteryOptimizationDisabled: true,
        autoStartGranted: true,
        autoStartSupported: true,
      );

      await tester.pumpWidget(createSetupScreenWidget());
      await tester.pumpAndSettle();

      expect(find.byType(SetupScreen), findsOneWidget);
      expect(find.text('Продолжить'), findsOneWidget);
    });

    testWidgets('shows disabled button label when permissions incomplete', (
      tester,
    ) async {
      DevicePermissions.permissionStateOverride = const PermissionState(
        notificationsGranted: false,
        exactAlarmGranted: true,
        batteryOptimizationDisabled: true,
        autoStartGranted: false,
        autoStartSupported: true,
      );

      await tester.pumpWidget(createSetupScreenWidget());
      await tester.pumpAndSettle();

      expect(
        find.text('Выдайте все разрешения для продолжения'),
        findsOneWidget,
      );
    });
  });
}
