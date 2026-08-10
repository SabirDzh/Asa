import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asa/core/home_widget_service.dart';
import 'package:asa/core/notification_service.dart';
import 'package:asa/core/version_service.dart';
import 'package:asa/features/settings/providers/settings_provider.dart';
import 'package:asa/features/settings/screens/whats_new_screen.dart';
import 'home_widget_channel_mock.dart';

Widget _harness(Future<List<UpdateInfo>> Function() fetch) {
  return ChangeNotifierProvider(
    create:
        (_) => SettingsProvider(
          deviceNameProvider: () async => 'Test Device',
          systemLanguageCodeProvider: () => 'ru',
        ),
    child: MaterialApp(home: WhatsNewScreen(fetchHistory: fetch)),
  );
}

Future<void> _pumpAndInit(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  final settings = Provider.of<SettingsProvider>(
    tester.element(find.byType(WhatsNewScreen)),
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

  testWidgets('renders releases newest first with notes and install button', (
    tester,
  ) async {
    await _pumpAndInit(
      tester,
      _harness(
        () async => [
          UpdateInfo(
            version: '1.2.0',
            url: 'https://github.com/SabirDzh/Asa/releases/tag/v1.2.0',
            notes: 'New **bold** feature',
            publishedAt: DateTime.utc(2026, 8, 1),
          ),
          const UpdateInfo(
            version: '1.1.0',
            url: 'https://github.com/SabirDzh/Asa/releases/tag/v1.1.0',
            notes: 'Older release',
          ),
        ],
      ),
    );

    expect(find.text('v1.2.0'), findsOneWidget);
    expect(find.text('v1.1.0'), findsOneWidget);
    expect(find.text('New bold feature', findRichText: true), findsOneWidget);
    expect(find.text('Older release', findRichText: true), findsOneWidget);
    expect(find.text('Установить обновление (v1.2.0)'), findsOneWidget);
  });

  testWidgets('shows check for updates button when up to date', (tester) async {
    await _pumpAndInit(
      tester,
      _harness(
        () async => [
          const UpdateInfo(
            version: '1.1.1',
            url: 'https://github.com/SabirDzh/Asa/releases/tag/v1.1.1',
            notes: 'Current version',
          ),
        ],
      ),
    );

    expect(find.text('Проверить обновления'), findsOneWidget);
  });

  testWidgets('shows empty state', (tester) async {
    await _pumpAndInit(tester, _harness(() async => []));
    expect(find.text('Релизов пока нет'), findsOneWidget);
    expect(find.text('Проверить обновления'), findsOneWidget);
  });

  testWidgets('shows error state and retries', (tester) async {
    var calls = 0;
    await _pumpAndInit(
      tester,
      _harness(() async {
        calls += 1;
        if (calls == 1) throw Exception('network');
        return [
          const UpdateInfo(
            version: '1.2.0',
            url: 'https://github.com/SabirDzh/Asa/releases/tag/v1.2.0',
            notes: 'Recovered',
          ),
        ];
      }),
    );
    expect(find.text('Не удалось загрузить историю версий'), findsOneWidget);

    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Recovered', findRichText: true), findsOneWidget);
    expect(find.text('Установить обновление (v1.2.0)'), findsOneWidget);
  });

  testWidgets('paginates releases 15 at a time with load more button', (
    tester,
  ) async {
    final releases = List.generate(
      20,
      (i) => UpdateInfo(
        version: '1.0.$i',
        url: 'https://github.com/SabirDzh/Asa/releases/tag/v1.0.$i',
        notes: 'Release notes $i',
      ),
    );

    await _pumpAndInit(tester, _harness(() async => releases));

    expect(find.text('v1.0.0'), findsOneWidget);

    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, -2000));
    await tester.pumpAndSettle();

    final loadMore = find.byKey(const ValueKey('whats-new-load-more'));
    expect(loadMore, findsOneWidget);

    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('whats-new-load-more')), findsNothing);
  });
}
