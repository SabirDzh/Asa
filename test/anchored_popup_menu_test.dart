import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asa/core/anchored_popup_menu.dart';

void main() {
  testWidgets('opens below the anchor with a six pixel gap', (tester) async {
    final anchorKey = GlobalKey();
    final menuKey = GlobalKey();

    await tester.pumpWidget(
      _TestApp(
        anchorKey: anchorKey,
        menuKey: menuKey,
        anchorAlignment: Alignment.topCenter,
      ),
    );

    await tester.tap(find.byKey(anchorKey));
    await tester.pumpAndSettle();

    final anchorRect = tester.getRect(find.byKey(anchorKey));
    final menuRect = tester.getRect(find.byKey(menuKey));
    expect(menuRect.top - anchorRect.bottom, closeTo(6, 0.01));
    expect(menuRect.top, greaterThan(anchorRect.bottom));
    expect(menuRect.right, closeTo(anchorRect.right, 0.01));
  });

  testWidgets(
    'opens above the anchor with a six pixel gap when below does not fit',
    (tester) async {
      final anchorKey = GlobalKey();
      final menuKey = GlobalKey();

      await tester.pumpWidget(
        _TestApp(
          anchorKey: anchorKey,
          menuKey: menuKey,
          anchorAlignment: Alignment.bottomCenter,
        ),
      );

      await tester.tap(find.byKey(anchorKey));
      await tester.pumpAndSettle();

      final anchorRect = tester.getRect(find.byKey(anchorKey));
      final menuRect = tester.getRect(find.byKey(menuKey));
      expect(anchorRect.top - menuRect.bottom, closeTo(6, 0.01));
      expect(menuRect.bottom, lessThan(anchorRect.top));
      expect(menuRect.right, closeTo(anchorRect.right, 0.01));
    },
  );
}

class _TestApp extends StatelessWidget {
  final GlobalKey anchorKey;
  final GlobalKey menuKey;
  final Alignment anchorAlignment;

  const _TestApp({
    required this.anchorKey,
    required this.menuKey,
    required this.anchorAlignment,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: anchorAlignment,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: GestureDetector(
              key: anchorKey,
              onTap: () {
                showAnchoredPopupMenu<String>(
                  context: context,
                  anchorContext: anchorKey.currentContext!,
                  menuKey: menuKey,
                  color: Colors.white,
                  shape: const RoundedRectangleBorder(),
                  items: const [
                    AnchoredPopupMenuItem<String>(
                      value: 'one',
                      child: Text('One'),
                    ),
                    AnchoredPopupMenuItem<String>(
                      value: 'two',
                      child: Text('Two'),
                    ),
                  ],
                );
              },
              child: const SizedBox(
                width: 48,
                height: 48,
                child: ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
