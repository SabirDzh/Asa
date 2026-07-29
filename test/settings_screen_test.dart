import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asa/features/settings/screens/settings_screen.dart';
import 'package:asa/features/settings/providers/settings_provider.dart';
import 'package:asa/features/settings/widgets/setting_row.dart';
import 'package:asa/features/tasks/providers/task_provider.dart';

Widget createTestApp({bool standalone = true}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ChangeNotifierProvider(create: (_) => TaskProvider()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SettingsScreen(standalone: standalone),
      ),
    ),
  );
}

Future<void> pumpAndInit(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  final settings = Provider.of<SettingsProvider>(tester.element(find.byType(SettingsScreen)), listen: false);
  await settings.ready;
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
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

    expect(find.text('Настройки'), findsOneWidget);
    await expectVisible('ВНЕШНИЙ ВИД');
    await expectVisible('СИНХРОНИЗАЦИЯ И ОБМЕН');
    await expectVisible('УВЕДОМЛЕНИЯ И ДАННЫЕ');
    await expectVisible('ДРУГОЕ');
    expect(find.byType(SettingRow), findsWidgets);
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

  testWidgets('shows about sheet on tap', (tester) async {
    await pumpAndInit(tester, createTestApp());

    final aboutFinder = find.text('О приложении');
    await tester.scrollUntilVisible(aboutFinder, 100, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(aboutFinder);
    await tester.pumpAndSettle();

    expect(find.text('О приложении ASA'), findsOneWidget);
    expect(find.text('Версия 1.1.0'), findsOneWidget);
  });

  testWidgets('shows data management sheet on tap', (tester) async {
    await pumpAndInit(tester, createTestApp());

    final dataFinder = find.text('Управление данными');
    await tester.scrollUntilVisible(dataFinder, 100, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(dataFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Очистить все задачи'), findsOneWidget);
    expect(find.text('Очистить все папки'), findsOneWidget);
    expect(find.text('Сбросить все данные'), findsOneWidget);
  });
}
