import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asa/features/settings/screens/settings_screen.dart';
import 'package:asa/features/settings/providers/settings_provider.dart';
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders all setting rows', (tester) async {
    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();

    expect(find.text('Уведомления'), findsOneWidget);
    expect(find.textContaining('Тема приложения'), findsOneWidget);
    expect(find.text('Показывать задачи в виджете'), findsOneWidget);
    expect(find.textContaining('Что отображать'), findsOneWidget);
    expect(find.textContaining('Масштаб интерфейса'), findsOneWidget);
    expect(find.text('Управление данными'), findsOneWidget);
    expect(find.text('Язык: русский'), findsOneWidget);
    expect(find.textContaining('Плавность анимации'), findsOneWidget);
    expect(find.text('О приложении'), findsOneWidget);
  });

  testWidgets('renders avatar section', (tester) async {
    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();

    expect(find.text('Сменить аватар'), findsOneWidget);
    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testWidgets('shows language sheet on tap', (tester) async {
    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Язык: русский'));
    await tester.pumpAndSettle();

    expect(find.text('Язык'), findsOneWidget);
    expect(find.text('Русский'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
  });

  testWidgets('shows about sheet on tap', (tester) async {
    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('О приложении'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('О приложении'));
    await tester.pumpAndSettle();

    expect(find.text('О приложении ASA'), findsOneWidget);
    expect(find.text('Версия 1.1.0'), findsOneWidget);
  });

  testWidgets('shows data management sheet on tap', (tester) async {
    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Управление данными'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Очистить все задачи'), findsOneWidget);
    expect(find.text('Очистить все папки'), findsOneWidget);
    expect(find.text('Сбросить все данные'), findsOneWidget);
  });
}
