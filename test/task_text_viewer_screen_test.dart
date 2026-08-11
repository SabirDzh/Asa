import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asa/features/tasks/models/task_info_block.dart';
import 'package:asa/features/tasks/screens/task_text_viewer_screen.dart';

void main() {
  String? clipboardText;

  setUp(() {
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText =
                (call.arguments as Map<Object?, Object?>?)?['text'] as String?;
          }
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': clipboardText};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  const attachment = TaskAttachment(
    id: 'text-1',
    type: TaskAttachmentType.file,
    name: 'notes.txt',
    value: '/task_attachments/notes.txt',
    mimeType: 'text/plain',
  );

  test('recognizes supported text attachments only', () {
    expect(isTaskTextAttachment(attachment), isTrue);
    expect(
      isTaskTextAttachment(
        const TaskAttachment(
          id: 'pdf',
          type: TaskAttachmentType.file,
          name: 'document.pdf',
          value: '/task_attachments/document.pdf',
          mimeType: 'application/pdf',
        ),
      ),
      isFalse,
    );
  });

  testWidgets('renders text content and copy action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: TaskTextViewerScreen(
          attachment: attachment,
          bytesLoader: (_) async => 'Hello ASA'.codeUnits,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-text-content')), findsOneWidget);
    expect(find.text('Hello ASA'), findsOneWidget);
    final copyButton = find.byKey(const ValueKey('copy-task-text'));
    expect(copyButton, findsOneWidget);
    await tester.tap(copyButton);
    await tester.pump();
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    expect(clipboard?.text, 'Hello ASA');
    expect(find.text('Скопировано'), findsOneWidget);
  });

  testWidgets('pretty prints valid JSON', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: TaskTextViewerScreen(
          attachment: const TaskAttachment(
            id: 'json',
            type: TaskAttachmentType.file,
            name: 'data.json',
            value: '/task_attachments/data.json',
            mimeType: 'application/json',
          ),
          bytesLoader: (_) async => '{"name":"ASA","enabled":true}'.codeUnits,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('"name": "ASA"'), findsOneWidget);
  });

  testWidgets('shows safe error state for oversized text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: TaskTextViewerScreen(
          attachment: attachment,
          bytesLoader:
              (_) async => List<int>.filled(kMaxTaskTextViewerBytes + 1, 0x41),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task-text-content')), findsNothing);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
  });
}
