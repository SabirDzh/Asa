import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asa/features/tasks/widgets/description_editor.dart';

void main() {
  test('wrapSelection preserves selected text and cursor range', () {
    final value = TextEditingValue(
      text: 'hello world',
      selection: const TextSelection(baseOffset: 6, extentOffset: 11),
    );

    final result = wrapSelection(value, '**', '**');

    expect(result.text, 'hello **world**');
    expect(result.selection.start, 8);
    expect(result.selection.end, 13);
  });

  test('wrapSelection places the cursor inside an empty pair', () {
    final result = wrapSelection(
      const TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 5),
      ),
      '`',
      '`',
    );

    expect(result.text, 'hello``');
    expect(result.selection, const TextSelection.collapsed(offset: 6));
  });

  test('prefixSelectedLines formats every selected line', () {
    final value = TextEditingValue(
      text: 'one\ntwo\nthree',
      selection: const TextSelection(baseOffset: 2, extentOffset: 9),
    );

    final result = prefixSelectedLines(value, '- ');

    expect(result.text, '- one\n- two\n- three');
    expect(result.selection.start, 4);
    expect(result.selection.end, 15);
  });

  testWidgets('switches between source and preview without changing source', (
    tester,
  ) async {
    final controller = TextEditingController(text: '**hello**');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DescriptionEditor(
            controller: controller,
            fieldKey: const ValueKey('description-field'),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('description-field')), findsOneWidget);
    expect(find.text('hello'), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('description-editor-preview')),
      findsOneWidget,
    );
    expect(find.text('hello'), findsOneWidget);
    expect(controller.text, '**hello**');

    controller.text = '**updated**';
    await tester.pump();
    expect(find.text('updated'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.code));
    await tester.pump();
    expect(find.byKey(const ValueKey('description-field')), findsOneWidget);
  });

  testWidgets('toolbar wraps the current selection', (tester) async {
    final controller = TextEditingController(text: 'hello');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DescriptionEditor(
            controller: controller,
            fieldKey: const ValueKey('description-field'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('description-field')));
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.tap(
      find.byKey(const ValueKey('description-toolbar-description_bold')),
    );
    await tester.pump();

    expect(controller.text, '**hello**');
    expect(find.byKey(const ValueKey('description-field')), findsOneWidget);
  });

  testWidgets('source editor remains usable at 320 dp', (tester) async {
    final controller = TextEditingController(text: 'A long description');
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: SizedBox(
            width: 320,
            height: 640,
            child: Scaffold(
              body: DescriptionEditor(
                controller: controller,
                fieldKey: const ValueKey('description-field'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('description-field')), findsOneWidget);
  });
}
