// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'home_widget_channel_mock.dart';
import 'package:asa/core/home_widget_service.dart';
import 'package:asa/main.dart';
import 'package:provider/provider.dart';
import 'package:asa/features/settings/providers/settings_provider.dart';
import 'package:asa/features/tasks/providers/task_provider.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    installHomeWidgetChannelMock();
    HomeWidgetService.instance.debounceDelay = Duration.zero;
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create:
                (_) => SettingsProvider(systemLanguageCodeProvider: () => 'ru'),
          ),
          ChangeNotifierProvider(create: (_) => TaskProvider()),
        ],
        child: const AsaApp(),
      ),
    );
    await tester.pump();
    await HomeWidgetService.resetForTests();
    HomeWidgetService.instance.debounceDelay = const Duration(
      milliseconds: 300,
    );
    removeHomeWidgetChannelMock();

    // Tests specific to the ASA app can be added here
  });
}
