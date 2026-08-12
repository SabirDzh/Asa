import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:asa/core/device_permissions.dart';
import 'package:asa/core/notification_service.dart';
import 'package:asa/features/settings/providers/settings_provider.dart';
import 'package:asa/features/splash/setup_screen.dart';

void main() {
  setUp(() {
    timeDilation = 1.0;
    SharedPreferences.setMockInitialValues({
      'languageCode': 'ru',
      // Keep SettingsProvider from mutating the global timeDilation.
      'animationSpeed': 1.0,
    });
  });

  tearDown(() {
    timeDilation = 1.0;
    DevicePermissions.permissionStateOverride = null;
    DevicePermissions.localNetworkPermissionOverride = null;
    DevicePermissions.openAutoStartSettingsOverride = null;
    NotificationService.requestPermissionOverride = null;
    NotificationService.permanentlyDeniedOverride = null;
    NotificationService.openNotificationSettingsOverride = null;
    NotificationService.notificationPermissionStateOverride = null;
    NotificationService.initializedOverride = null;
  });

  Widget createSetupScreenWidget({SettingsProvider? settings}) {
    return ChangeNotifierProvider(
      create: (_) => settings ?? SettingsProvider(),
      child: const MaterialApp(home: SetupScreen()),
    );
  }

  const incompleteState = PermissionState(
    notificationsGranted: false,
    exactAlarmGranted: true,
    batteryOptimizationDisabled: true,
    autoStartGranted: true,
    autoStartSupported: false,
  );

  const completeState = PermissionState(
    notificationsGranted: true,
    exactAlarmGranted: true,
    batteryOptimizationDisabled: true,
    autoStartGranted: true,
    autoStartSupported: true,
  );

  const autoStartIncompleteState = PermissionState(
    notificationsGranted: true,
    exactAlarmGranted: true,
    batteryOptimizationDisabled: true,
    autoStartGranted: false,
    autoStartSupported: true,
  );

  group('SetupScreen State & UI', () {
    test('markCompleted sets preference', () async {
      await SetupScreen.markCompleted();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('asa_setup_completed'), isTrue);
    });

    testWidgets('renders all tiles when all permissions granted', (
      tester,
    ) async {
      DevicePermissions.permissionStateOverride = completeState;

      await tester.pumpWidget(createSetupScreenWidget());
      await tester.pumpAndSettle();

      expect(find.byType(SetupScreen), findsOneWidget);
      expect(find.text('Продолжить'), findsOneWidget);
      expect(
        find.text(
          'После завершения настройки разрешения можно изменить в разделе «Уведомления и данные»',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows disabled button label when permissions incomplete', (
      tester,
    ) async {
      DevicePermissions.permissionStateOverride = incompleteState;

      await tester.pumpWidget(createSetupScreenWidget());
      await tester.pumpAndSettle();

      expect(
        find.text('Выдайте все разрешения для продолжения'),
        findsOneWidget,
      );
    });

    testWidgets(
      'permission action is below text with an accessible tap target',
      (tester) async {
        DevicePermissions.permissionStateOverride = incompleteState;

        await tester.pumpWidget(createSetupScreenWidget());
        await tester.pumpAndSettle();

        final labelFinder = find.text('Уведомления');
        final actionTextFinder = find.text('Включить');
        final actionButtonFinder = find.ancestor(
          of: actionTextFinder,
          matching: find.byType(TextButton),
        );
        expect(labelFinder, findsOneWidget);
        expect(actionTextFinder, findsOneWidget);
        expect(actionButtonFinder, findsOneWidget);
        expect(
          tester.getTopLeft(actionButtonFinder).dy,
          greaterThan(tester.getBottomLeft(labelFinder).dy),
        );
        expect(
          tester.getSize(actionButtonFinder).height,
          greaterThanOrEqualTo(48),
        );
      },
    );

    testWidgets('notification enable action requests permission', (
      tester,
    ) async {
      var requestCalled = false;
      DevicePermissions.permissionStateOverride = incompleteState;
      NotificationService.requestPermissionOverride = ({
        required requestExactAlarms,
      }) async {
        requestCalled = true;
        expect(requestExactAlarms, isFalse);
        return false;
      };
      NotificationService.permanentlyDeniedOverride = () async => false;

      await tester.pumpWidget(createSetupScreenWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Включить'));
      await tester.pumpAndSettle();

      expect(requestCalled, isTrue);
      expect(
        find.text('Разрешение на уведомления не выдано — повторите попытку'),
        findsOneWidget,
      );
    });

    testWidgets(
      'auto-start requires explicit confirmation after returning from settings',
      (tester) async {
        var settingsOpened = false;
        DevicePermissions.permissionStateOverride = autoStartIncompleteState;
        DevicePermissions.openAutoStartSettingsOverride = () async {
          settingsOpened = true;
        };

        await tester.pumpWidget(createSetupScreenWidget());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Включить'));
        await tester.pump();
        expect(settingsOpened, isTrue);
        expect(
          (await SharedPreferences.getInstance()).getBool(
            'asa_autostart_confirmed',
          ),
          isNull,
        );

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(find.text('Автозапуск включён?'), findsOneWidget);

        DevicePermissions.permissionStateOverride = completeState;
        await tester.tap(find.text('Я включил автозапуск'));
        await tester.pumpAndSettle();

        expect(
          (await SharedPreferences.getInstance()).getBool(
            'asa_autostart_confirmed',
          ),
          isTrue,
        );
        expect(find.text('Продолжить'), findsOneWidget);
      },
    );

    testWidgets('granting permission enables the notifications setting', (
      tester,
    ) async {
      // The startup sync turns the default-on toggle off while the runtime
      // permission is still missing; granting from setup must turn it back on.
      SharedPreferences.setMockInitialValues({
        'languageCode': 'ru',
        'animationSpeed': 1.0,
        'notificationsEnabled': false,
      });
      final settings = SettingsProvider();
      DevicePermissions.permissionStateOverride = incompleteState;
      NotificationService.initializedOverride = true;
      NotificationService.requestPermissionOverride =
          ({required requestExactAlarms}) async => true;
      NotificationService.permanentlyDeniedOverride = () async => false;

      await tester.pumpWidget(createSetupScreenWidget(settings: settings));
      await tester.pumpAndSettle();

      expect(settings.notificationsEnabled, isFalse);
      await tester.tap(find.text('Включить'));
      await tester.pumpAndSettle();

      expect(settings.notificationsEnabled, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('notificationsEnabled'), isTrue);
    });

    testWidgets('permanently denied opens settings and shows hint', (
      tester,
    ) async {
      var settingsOpened = false;
      DevicePermissions.permissionStateOverride = incompleteState;
      NotificationService.requestPermissionOverride =
          ({required requestExactAlarms}) async => false;
      NotificationService.permanentlyDeniedOverride = () async => true;
      NotificationService.openNotificationSettingsOverride = () async {
        settingsOpened = true;
      };

      await tester.pumpWidget(createSetupScreenWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Включить'));
      await tester.pumpAndSettle();

      expect(settingsOpened, isTrue);
      expect(
        find.text(
          'Уведомления отключены в системе. Включите их в настройках приложения',
        ),
        findsOneWidget,
      );
    });
  });
}
