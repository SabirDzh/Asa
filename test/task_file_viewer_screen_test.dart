import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asa/features/tasks/models/task_info_block.dart';
import 'package:asa/features/tasks/screens/task_file_viewer_screen.dart';

void main() {
  Widget app(
    TaskAttachment attachment, {
    Future<bool> Function(TaskAttachment attachment)? openExternal,
    Future<bool> Function(TaskAttachment attachment)? shareFile,
  }) {
    return MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: TaskFileViewerScreen(
        attachment: attachment,
        openExternal: openExternal,
        shareFile: shareFile,
      ),
    );
  }

  test('classifies Office, archive, and generic files', () {
    expect(
      taskFileViewerKind(
        const TaskAttachment(
          id: 'doc',
          type: TaskAttachmentType.file,
          name: 'contract.docx',
          value: '/task_attachments/contract.docx',
        ),
      ),
      'office',
    );
    expect(
      taskFileViewerKind(
        const TaskAttachment(
          id: 'zip',
          type: TaskAttachmentType.file,
          name: 'backup.zip',
          value: '/task_attachments/backup.zip',
        ),
      ),
      'archive',
    );
  });

  testWidgets('renders external open and share actions', (tester) async {
    await tester.pumpWidget(
      app(
        const TaskAttachment(
          id: 'doc',
          type: TaskAttachmentType.file,
          name: 'contract.docx',
          value: '/task_attachments/contract.docx',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Откройте документ в установленном приложении Office'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('open-task-file-external')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('share-task-file')), findsOneWidget);
  });

  testWidgets('shows a safe error when the file is unavailable', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      app(
        const TaskAttachment(
          id: 'missing',
          type: TaskAttachmentType.file,
          name: 'backup.zip',
          value: '/missing/task_attachments/backup.zip',
        ),
        openExternal: (_) async {
          opened = true;
          return false;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-task-file-external')));
    await tester.pump();

    expect(opened, isTrue);
    expect(
      find.text('Не удалось открыть файл во внешнем приложении'),
      findsOneWidget,
    );
  });
}
