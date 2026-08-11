import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:asa/features/tasks/models/task_info_block.dart';
import 'package:asa/features/tasks/screens/task_pdf_viewer_screen.dart';

void main() {
  const pdf = TaskAttachment(
    id: 'pdf-1',
    type: TaskAttachmentType.file,
    name: 'contract.pdf',
    value: '/task_attachments/contract.pdf',
    mimeType: 'application/pdf',
  );

  test('recognizes PDF attachments only', () {
    expect(isTaskPdfAttachment(pdf), isTrue);
    expect(
      isTaskPdfAttachment(
        const TaskAttachment(
          id: 'text',
          type: TaskAttachmentType.file,
          name: 'notes.txt',
          value: '/task_attachments/notes.txt',
          mimeType: 'text/plain',
        ),
      ),
      isFalse,
    );
  });

  testWidgets('reports a failed PDF share action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: TaskPdfViewerScreen(
          attachment: pdf,
          bytesLoader: (_) async => const [1, 2, 3],
          shareFile: (_) async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('share-task-pdf')));
    await tester.pump();

    expect(find.text('Не удалось поделиться файлом'), findsOneWidget);
  });

  testWidgets('shows a safe state for missing or invalid PDF data', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: TaskPdfViewerScreen(
          attachment: pdf,
          bytesLoader: (_) async => const [1, 2, 3],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('contract.pdf'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-pdf-content')), findsNothing);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    expect(find.byKey(const ValueKey('close-task-pdf-viewer')), findsOneWidget);
  });

  testWidgets('rejects oversized PDF data before opening the renderer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: TaskPdfViewerScreen(
          attachment: pdf,
          bytesLoader:
              (_) async => List<int>.filled(kMaxTaskPdfViewerBytes + 1, 0x41),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task-pdf-content')), findsNothing);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
  });
}
