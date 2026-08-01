import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asa/features/settings/providers/settings_provider.dart';
import 'package:asa/features/tasks/providers/task_provider.dart';
import 'package:asa/features/tasks/screens/home_screen.dart';
import 'package:asa/core/home_widget_service.dart';
import 'home_widget_channel_mock.dart';

Widget createTestApp() {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (_) => SettingsProvider(systemLanguageCodeProvider: () => 'ru'),
      ),
      ChangeNotifierProvider(create: (_) => TaskProvider()),
    ],
    child: const MaterialApp(home: HomeScreen()),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HomeWidgetService.instance.debounceDelay = Duration.zero;
    installHomeWidgetChannelMock();
  });

  tearDown(() async {
    await HomeWidgetService.resetForTests();
    HomeWidgetService.instance.debounceDelay = const Duration(
      milliseconds: 300,
    );
    removeHomeWidgetChannelMock();
  });

  testWidgets('renders home screen with streak folder and search bar', (
    tester,
  ) async {
    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('opens create folder sheet on FAB tap', (tester) async {
    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('новая папка...'), findsOneWidget);
  });

  testWidgets('shows filter menu on filter icon tap', (tester) async {
    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Iconsax.filter_square));
    await tester.pumpAndSettle();

    expect(find.text('Фильтры'), findsOneWidget);
    expect(find.text('Все'), findsOneWidget);
    expect(find.text('Только папки'), findsOneWidget);
  });
}
