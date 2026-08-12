import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asa/core/home_widget_service.dart';
import 'package:asa/features/settings/providers/settings_provider.dart';
import 'package:asa/features/settings/widgets/avatar_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const imagePickerChannel = MethodChannel('plugins.flutter.io/image_picker');
  late SettingsProvider settings;
  late Completer<Object?> pickerResult;
  var pickerCalls = 0;

  setUp(() {
    timeDilation = 1.0;
    HomeWidgetService.instance.debounceDelay = Duration.zero;
    HomeWidgetService.instance.updateOverride = () async {};
    SharedPreferences.setMockInitialValues({'animationSpeed': 1.0});
    pickerResult = Completer<Object?>();
    pickerCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(imagePickerChannel, (call) async {
          pickerCalls++;
          return pickerResult.future;
        });
  });

  tearDown(() async {
    timeDilation = 1.0;
    await HomeWidgetService.resetForTests();
    HomeWidgetService.instance.debounceDelay = const Duration(
      milliseconds: 300,
    );
    HomeWidgetService.instance.updateOverride = null;
    if (!pickerResult.isCompleted) pickerResult.complete(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(imagePickerChannel, null);
    settings.dispose();
  });

  testWidgets('prevents a second avatar picker while the first is active', (
    tester,
  ) async {
    settings = SettingsProvider(
      deviceNameProvider: () async => 'Test Device',
      systemLanguageCodeProvider: () => 'ru',
    );
    await settings.ready;

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: const MaterialApp(home: Scaffold(body: AvatarSection())),
      ),
    );
    await tester.pump();

    final button = find.byType(ElevatedButton);
    await tester.tap(button);
    await tester.pump();

    expect(pickerCalls, 1);
    expect(tester.widget<ElevatedButton>(button).onPressed, isNull);

    await tester.tap(button);
    expect(pickerCalls, 1);

    // The first picker is still the only active platform call. Completion is
    // covered by the `finally` path in the widget; the regression assertion
    // above is intentionally made while that call is pending.
    pickerResult.complete(null);
    await tester.pump();
    HomeWidgetService.cancelPendingUpdate();
  });
}
