import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asa/core/version_service.dart';
import 'package:asa/features/settings/screens/settings_screen.dart';
import 'package:asa/features/settings/screens/whats_new_screen.dart';
import 'package:asa/features/settings/providers/settings_provider.dart';
import 'package:asa/features/settings/widgets/setting_row.dart';
import 'package:asa/features/tasks/providers/task_provider.dart';
import 'package:asa/core/home_widget_service.dart';
import 'package:asa/core/notification_service.dart';
import 'package:asa/core/theme.dart';
import 'home_widget_channel_mock.dart';

Widget createTestApp({bool standalone = true}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create:
            (_) => SettingsProvider(
              deviceNameProvider: () async => 'Test Device',
              systemLanguageCodeProvider: () => 'ru',
            ),
      ),
      ChangeNotifierProvider(create: (_) => TaskProvider()),
    ],
    child: MaterialApp(
      home: Scaffold(body: SettingsScreen(standalone: standalone)),
    ),
  );
}

Future<void> pumpAndInit(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  final settings = Provider.of<SettingsProvider>(
    tester.element(find.byType(SettingsScreen)),
    listen: false,
  );
  await settings.ready;
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HomeWidgetService.instance.debounceDelay = Duration.zero;
    installHomeWidgetChannelMock();
    NotificationService.initializedOverride = null;
    NotificationService.requestPermissionOverride = null;
    NotificationService.permanentlyDeniedOverride = null;
  });

  tearDown(() async {
    await HomeWidgetService.resetForTests();
    HomeWidgetService.instance.debounceDelay = const Duration(
      milliseconds: 300,
    );
    removeHomeWidgetChannelMock();
    NotificationService.initializedOverride = null;
    NotificationService.requestPermissionOverride = null;
    NotificationService.permanentlyDeniedOverride = null;
  });

  testWidgets('renders all setting groups', (tester) async {
    await pumpAndInit(tester, createTestApp());

    final scrollable = find.byType(Scrollable).first;
    Future<void> expectVisible(String text) async {
      final finder = find.text(text);
      await tester.scrollUntilVisible(finder, 60, scrollable: scrollable);
      await tester.pumpAndSettle();
      expect(finder, findsOneWidget);
    }

    await expectVisible('ВНЕШНИЙ ВИД');
    await expectVisible('СИНХРОНИЗАЦИЯ И ОБМЕН');
    await expectVisible('УВЕДОМЛЕНИЯ И ДАННЫЕ');
    await expectVisible('ДРУГОЕ');
    expect(find.byType(SettingRow), findsWidgets);
  });

  testWidgets('uses the timer icon for animation speed setting', (
    tester,
  ) async {
    await pumpAndInit(tester, createTestApp());

    expect(
      find.byKey(const ValueKey('animation_speed_timer_icon')),
      findsOneWidget,
    );
  });

  testWidgets('renders avatar section', (tester) async {
    await pumpAndInit(tester, createTestApp());

    expect(find.text('Сменить аватар'), findsOneWidget);
    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testWidgets('shows language sheet on tap', (tester) async {
    await pumpAndInit(tester, createTestApp());

    await tester.tap(find.text('Язык: русский'));
    await tester.pumpAndSettle();

    expect(find.text('Язык'), findsOneWidget);
    expect(find.text('Русский'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
  });

  testWidgets('selects the ocean palette from the profile', (tester) async {
    await pumpAndInit(tester, createTestApp());

    final paletteRow = find.text('Палитра: Базовая');
    expect(paletteRow, findsOneWidget);
    await tester.tap(paletteRow);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('palette-sheet')), findsOneWidget);
    expect(find.text('Ocean'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('palette-ocean-option')));
    await tester.pumpAndSettle();

    final settings = Provider.of<SettingsProvider>(
      tester.element(find.byType(SettingsScreen)),
      listen: false,
    );
    expect(settings.colorPalette, ColorPalette.ocean);
    expect(find.text('Палитра: Ocean'), findsOneWidget);
  });

  testWidgets('custom palette editor never allows more than three colors', (
    tester,
  ) async {
    await pumpAndInit(tester, createTestApp());

    await tester.tap(find.text('Палитра: Базовая'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-custom-palette')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('custom-palette-editor')), findsOneWidget);
    expect(find.byKey(const ValueKey('custom-color-input-0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add-custom-color')));
    await tester.tap(find.byKey(const ValueKey('add-custom-color')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('custom-color-input-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('custom-color-input-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('custom-color-input-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('add-custom-color')), findsNothing);
  });

  testWidgets('returns to a saved custom palette after selecting ocean', (
    tester,
  ) async {
    await pumpAndInit(tester, createTestApp());

    await tester.tap(find.text('Палитра: Базовая'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-custom-palette')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('custom-color-input-0')),
      '#123456',
    );
    await tester.tap(find.byKey(const ValueKey('save-custom-palette')));
    await tester.pumpAndSettle();
    expect(find.text('Палитра: Своя палитра'), findsOneWidget);

    await tester.tap(find.text('Палитра: Своя палитра'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('palette-ocean-option')));
    await tester.pumpAndSettle();
    expect(find.text('Палитра: Ocean'), findsOneWidget);

    await tester.tap(find.text('Палитра: Ocean'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('palette-custom-option')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('palette-custom-option')));
    await tester.pumpAndSettle();
    expect(find.text('Палитра: Своя палитра'), findsOneWidget);
  });

  testWidgets('opens the what-is-new screen from the other group', (
    tester,
  ) async {
    await pumpAndInit(tester, createTestApp());

    final row = find.text('Что нового');
    await tester.scrollUntilVisible(
      row,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(WhatsNewScreen), findsOneWidget);
  });

  testWidgets('shows about sheet on tap', (tester) async {
    await pumpAndInit(tester, createTestApp());

    final aboutFinder = find.text('О приложении');
    await tester.scrollUntilVisible(
      aboutFinder,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(aboutFinder);
    await tester.pumpAndSettle();

    expect(find.text('О приложении ASA'), findsOneWidget);
    expect(find.textContaining(VersionService.currentVersion), findsOneWidget);
  });

  testWidgets(
    'shows open-settings sheet when notifications are permanently denied',
    (tester) async {
      // The switch starts off, matching the state after the system revoked
      // the permission behind the app's back.
      SharedPreferences.setMockInitialValues({'notificationsEnabled': false});
      NotificationService.initializedOverride = true;
      NotificationService.requestPermissionOverride =
          ({required bool requestExactAlarms}) async => false;
      NotificationService.permanentlyDeniedOverride = () async => true;
      await pumpAndInit(tester, createTestApp());

      final notificationsRow = find.text('Уведомления');
      await tester.scrollUntilVisible(
        notificationsRow,
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      final row = find.ancestor(
        of: notificationsRow,
        matching: find.byType(SettingRow),
      );
      await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
      await tester.pumpAndSettle();

      expect(find.text('Уведомления отключены'), findsOneWidget);
      expect(find.text('Открыть настройки'), findsOneWidget);
    },
  );

  testWidgets('shows data management sheet on tap', (tester) async {
    await pumpAndInit(tester, createTestApp());

    final dataFinder = find.text('Управление данными');
    await tester.scrollUntilVisible(
      dataFinder,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(dataFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Экспорт данных'), findsOneWidget);
    expect(find.text('Импорт данных'), findsOneWidget);
    expect(find.text('Отправить логи разработчику'), findsOneWidget);
    expect(find.text('Очистить все задачи'), findsOneWidget);
    expect(find.text('Очистить все папки'), findsOneWidget);
    expect(find.text('Сбросить все данные'), findsOneWidget);
  });
}
