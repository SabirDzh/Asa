import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asa/features/tasks/widgets/description_toolbar.dart';

void main() {
  testWidgets('toolbar exposes localized actions and a formatting group', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: DescriptionToolbar(
            onBold: () {},
            onItalic: () {},
            onCode: () {},
            onBulletedList: () {},
            onQuote: () {},
            onLink: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Bold'), findsOneWidget);
    expect(find.byTooltip('Bulleted list'), findsOneWidget);
    expect(find.bySemanticsLabel('Markdown formatting'), findsOneWidget);
  });

  testWidgets('toolbar remains bounded at narrow width and large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 160),
            textScaler: TextScaler.linear(2),
          ),
          child: const Scaffold(
            body: SingleChildScrollView(child: _ToolbarHarness()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Link'), findsOneWidget);
  });
}

class _ToolbarHarness extends StatelessWidget {
  const _ToolbarHarness();

  @override
  Widget build(BuildContext context) {
    return DescriptionToolbar(
      onBold: () {},
      onItalic: () {},
      onCode: () {},
      onBulletedList: () {},
      onQuote: () {},
      onLink: () {},
    );
  }
}
