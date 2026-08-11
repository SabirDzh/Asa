import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asa/core/drag_close_sheet.dart';

/// Performs a slow, finger-like drag (no fling velocity) so the gesture arena
/// resolves like a real touch drag rather than an instant fling.
Future<void> slowDrag(
  WidgetTester tester,
  Offset start,
  Offset offset, {
  Duration duration = const Duration(milliseconds: 800),
}) async {
  final gesture = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 50));
  const steps = 20;
  for (var i = 1; i <= steps; i++) {
    await gesture.moveBy(
      Offset(offset.dx / steps, offset.dy / steps),
      timeStamp: Duration(milliseconds: (50 + 800 * i / steps).round()),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

Widget buildHarness(Widget sheetContent, {bool trackScrollableDrag = false}) {
  return MaterialApp(
    home: Builder(
      builder:
          (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed:
                    () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      enableDrag: false,
                      builder:
                          (ctx) => DragToCloseSheet(
                            trackScrollableDrag: trackScrollableDrag,
                            child: sheetContent,
                          ),
                    ),
                child: const Text('open'),
              ),
            ),
          ),
    ),
  );
}

/// Tall content that fills the screen and scrolls vertically.
Widget tallScrollable() {
  final viewSize =
      MediaQueryData.fromView(
        WidgetsBinding.instance.platformDispatcher.views.first,
      ).size;
  return Container(
    width: viewSize.width,
    height: viewSize.height,
    color: Colors.white,
    child: SingleChildScrollView(
      key: const ValueKey('tall-scroll'),
      child: Column(
        children: [
          for (var i = 0; i < 40; i++)
            Padding(padding: const EdgeInsets.all(12), child: Text('row $i')),
        ],
      ),
    ),
  );
}

/// Short content that fits on screen and does not scroll.
Widget shortContent() {
  return Container(
    height: 220,
    color: Colors.white,
    child: const Center(child: Text('short content')),
  );
}

Widget nestedScrollableContent() {
  return Container(
    height: 420,
    color: Colors.white,
    child: Column(
      children: [
        const Text('description block'),
        Expanded(
          child: ListView.builder(
            key: const ValueKey('nested-description-scroll'),
            itemCount: 40,
            itemBuilder:
                (context, index) =>
                    SizedBox(height: 48, child: Text('attachment row $index')),
          ),
        ),
      ],
    ),
  );
}

void main() {
  testWidgets('slow drag down closes a tall scrollable sheet', (tester) async {
    await tester.pumpWidget(
      buildHarness(tallScrollable(), trackScrollableDrag: true),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tall-scroll')), findsOneWidget);

    final start =
        tester.getTopLeft(find.byKey(const ValueKey('tall-scroll'))) +
        const Offset(200, 40);
    await slowDrag(tester, start, const Offset(0, 300));

    expect(find.byKey(const ValueKey('tall-scroll')), findsNothing);
  });

  testWidgets('slow drag down closes a short non-scrollable sheet', (
    tester,
  ) async {
    await tester.pumpWidget(buildHarness(shortContent()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('short content'), findsOneWidget);

    final center = tester.getCenter(find.text('short content'));
    await slowDrag(tester, center, const Offset(0, 300));

    expect(find.text('short content'), findsNothing);
  });

  testWidgets('small pull springs back without closing', (tester) async {
    await tester.pumpWidget(buildHarness(shortContent()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('short content'), findsOneWidget);

    // A short pull below the threshold must animate back and keep the sheet.
    final center = tester.getCenter(find.text('short content'));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('short content'), findsOneWidget);
  });

  testWidgets('dragging up inside the sheet scrolls instead of closing', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildHarness(tallScrollable(), trackScrollableDrag: true),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tall-scroll')), findsOneWidget);

    // Fling upward (scroll down through the list) must not close the sheet.
    await tester.fling(
      find.byKey(const ValueKey('tall-scroll')),
      const Offset(0, -400),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tall-scroll')), findsOneWidget);
  });

  testWidgets('nested description scrolling does not move or close the sheet', (
    tester,
  ) async {
    await tester.pumpWidget(buildHarness(nestedScrollableContent()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('nested-description-scroll'));
    expect(list, findsOneWidget);
    final before = tester.getTopLeft(list).dy;
    final scrollable = find.byType(Scrollable).last;

    await tester.fling(list, const Offset(0, -500), 1200);
    await tester.pumpAndSettle();

    expect(list, findsOneWidget);
    expect(tester.getTopLeft(list).dy, before);
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      greaterThan(0),
    );
  });

  testWidgets('small pull on a tall scrollable springs back without closing', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildHarness(tallScrollable(), trackScrollableDrag: true),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tall-scroll')), findsOneWidget);

    // A short pull (below the 120 px threshold) must animate back.
    final start =
        tester.getTopLeft(find.byKey(const ValueKey('tall-scroll'))) +
        const Offset(200, 40);
    await slowDrag(tester, start, const Offset(0, 60));

    expect(find.byKey(const ValueKey('tall-scroll')), findsOneWidget);
  });

  testWidgets('tapping the barrier still dismisses the sheet', (tester) async {
    await tester.pumpWidget(buildHarness(shortContent()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('short content'), findsOneWidget);

    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();

    expect(find.text('short content'), findsNothing);
  });

  testWidgets('system back button still dismisses the sheet', (tester) async {
    await tester.pumpWidget(
      buildHarness(tallScrollable(), trackScrollableDrag: true),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tall-scroll')), findsOneWidget);

    await WidgetsBinding.instance.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tall-scroll')), findsNothing);
  });
}
