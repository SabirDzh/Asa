import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asa/core/task_attachment_service.dart';
import 'package:asa/features/browser/screens/in_app_browser_screen.dart';

void main() {
  setUp(() {
    InAppBrowserScreen.resetFaviconFailureCache();
  });

  tearDown(() {
    InAppBrowserScreen.resetFaviconFailureCache();
  });

  test('favicon policy stays on the same HTTPS host', () {
    expect(
      InAppBrowserScreen.faviconUriFor(
        Uri.parse('https://example.com/docs?token=secret'),
      ),
      Uri.parse('https://example.com/favicon.ico'),
    );
    expect(
      InAppBrowserScreen.faviconUriFor(Uri.parse('https://example.com:8443/a')),
      Uri.parse('https://example.com:8443/favicon.ico'),
    );
    expect(
      InAppBrowserScreen.faviconUriFor(Uri.parse('http://example.com')),
      isNull,
    );
  });

  test('in-app browser accepts only web URLs', () {
    expect(isAllowedTaskLink('https://example.com/path'), isTrue);
    expect(isAllowedTaskLink('http://localhost:8080'), isTrue);
    expect(isAllowedTaskLink('mailto:test@example.com'), isFalse);
    expect(isAllowedTaskLink('javascript:alert(1)'), isFalse);
    expect(isAllowedTaskLink('https:///missing-host'), isFalse);
  });

  test('favicon failure cache is bounded', () {
    for (var i = 0; i < 30; i++) {
      InAppBrowserScreen.rememberFaviconFailureForTesting(
        Uri.parse('https://$i.example.com/favicon.ico'),
      );
    }
    expect(InAppBrowserScreen.faviconFailureCacheSize, 24);
  });

  testWidgets('shows the page title, domain and favicon request', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: InAppBrowserScreen(
          url: Uri.parse('https://example.com/docs'),
          title: 'Example',
          forceExternal: true,
        ),
      ),
    );

    expect(find.text('Example'), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget);
    expect(find.byKey(const ValueKey('browser-favicon')), findsOneWidget);
    expect(find.textContaining('Встроенный'), findsOneWidget);
    expect(find.text('Открыть во внешнем браузере'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('uses the globe fallback for non-HTTPS external links', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: InAppBrowserScreen(
          url: Uri.parse('http://example.com'),
          title: 'Example',
          forceExternal: true,
        ),
      ),
    );

    expect(find.text('example.com'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('browser-favicon-fallback')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('browser-favicon')), findsNothing);
  });
}
