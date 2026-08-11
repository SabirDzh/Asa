import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asa/features/tasks/widgets/attachment_action_menu.dart';

void main() {
  testWidgets('opens below and right-aligns to the selector', (tester) async {
    final anchorKey = GlobalKey();
    await tester.pumpWidget(
      _TestApp(anchorKey: anchorKey, alignment: Alignment.topCenter),
    );

    await tester.tap(find.byKey(anchorKey));
    await tester.pumpAndSettle();

    final anchorRect = tester.getRect(
      find.byKey(const ValueKey('attachment-action-selector')),
    );
    final menuRect = tester.getRect(
      find.byKey(const ValueKey('attachment-action-dropdown')),
    );
    expect(menuRect.top - anchorRect.bottom, closeTo(6, 0.01));
    expect(menuRect.right, closeTo(anchorRect.right, 0.01));
    expect(menuRect.width, closeTo(anchorRect.width, 0.01));
  });

  testWidgets('opens above and right-aligns when below does not fit', (
    tester,
  ) async {
    final anchorKey = GlobalKey();
    await tester.pumpWidget(
      _TestApp(anchorKey: anchorKey, alignment: Alignment.bottomCenter),
    );

    await tester.tap(find.byKey(anchorKey));
    await tester.pumpAndSettle();

    final anchorRect = tester.getRect(
      find.byKey(const ValueKey('attachment-action-selector')),
    );
    final menuRect = tester.getRect(
      find.byKey(const ValueKey('attachment-action-dropdown')),
    );
    expect(anchorRect.top - menuRect.bottom, closeTo(6, 0.01));
    expect(menuRect.right, closeTo(anchorRect.right, 0.01));
  });

  testWidgets('opens with a live keyboard inset and keeps selector width', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpWidget(
      _TestApp(anchorKey: GlobalKey(), alignment: Alignment.topCenter),
    );

    await tester.tap(find.byKey(const ValueKey('attachment-action-selector')));
    await tester.pumpAndSettle();

    final anchorRect = tester.getRect(
      find.byKey(const ValueKey('attachment-action-selector')),
    );
    final menuRect = tester.getRect(
      find.byKey(const ValueKey('attachment-action-dropdown')),
    );
    expect(menuRect.width, closeTo(anchorRect.width, 0.01));
    expect(menuRect.top - anchorRect.bottom, closeTo(6, 0.01));
  });

  testWidgets('selecting an option updates the selected action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(anchorKey: GlobalKey(), alignment: Alignment.topCenter),
    );

    final selector = find.byKey(const ValueKey('attachment-action-selector'));
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('attachment-action-option-image')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Добавить изображение'), findsOneWidget);
  });
}

class _TestApp extends StatefulWidget {
  final GlobalKey anchorKey;
  final Alignment alignment;

  const _TestApp({required this.anchorKey, required this.alignment});

  @override
  State<_TestApp> createState() => _TestAppState();
}

class _TestAppState extends State<_TestApp> {
  AttachmentAction _selectedAction = AttachmentAction.link;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: widget.alignment,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AttachmentActionMenu(
              key: widget.anchorKey,
              selectedAction: _selectedAction,
              onActionChanged: (action) {
                setState(() => _selectedAction = action);
              },
              onAdd: () {},
              linkLabel: 'Добавить ссылку',
              imageLabel: 'Добавить изображение',
              fileLabel: 'Добавить файл',
              addLabel: 'Добавить',
            ),
          ),
        ),
      ),
    );
  }
}
