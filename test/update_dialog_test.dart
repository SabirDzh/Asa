import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asa/core/update_dialog.dart';
import 'package:asa/core/version_service.dart';
import 'package:asa/features/settings/providers/settings_provider.dart';

Widget _harness(WidgetTester tester, UpdateInstallCallback onInstall) {
  return ChangeNotifierProvider(
    create:
        (_) => SettingsProvider(
          deviceNameProvider: () async => 'Test Device',
          systemLanguageCodeProvider: () => 'ru',
        ),
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            final settings = Provider.of<SettingsProvider>(
              context,
              listen: false,
            );
            return Center(
              child: ElevatedButton(
                onPressed:
                    () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder:
                          (_) => UpdateDialog(
                            settings: settings,
                            info: const UpdateInfo(
                              version: '1.2.0',
                              url:
                                  'https://github.com/SabirDzh/Asa/releases/tag/v1.2.0',
                              notes: 'New stuff',
                              assetUrl:
                                  'https://github.com/SabirDzh/Asa/releases/download/v1.2.0/app-arm64-v8a-release.apk',
                              assetName: 'app-arm64-v8a-release.apk',
                            ),
                            onPostpone: () => Navigator.of(context).pop(),
                            onInstall: onInstall,
                          ),
                    ),
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('install flow shows progress then closes on success', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(tester, (onProgress) async {
        onProgress(50, 100);
        // Let the progress frame render before the install completes.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        onProgress(100, 100);
        return UpdateInstallOutcome.installed;
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Установить'));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);
  });

  testWidgets('failed install shows error and allows retry', (tester) async {
    await tester.pumpWidget(
      _harness(tester, (onProgress) async => UpdateInstallOutcome.failed),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Установить'));
    await tester.pumpAndSettle();

    expect(find.text('Не удалось загрузить обновление'), findsOneWidget);
    expect(find.text('Установить'), findsOneWidget);
  });

  testWidgets('unavailable outcome hides the install button', (tester) async {
    await tester.pumpWidget(
      _harness(tester, (onProgress) async => UpdateInstallOutcome.unavailable),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Установить'));
    await tester.pumpAndSettle();

    expect(find.text('Установить'), findsNothing);
    expect(
      find.text('Автоустановка недоступна на этой платформе'),
      findsOneWidget,
    );
  });
}
