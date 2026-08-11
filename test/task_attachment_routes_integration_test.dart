import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asa/core/home_widget_service.dart';
import 'home_widget_channel_mock.dart';
import 'package:asa/features/settings/providers/settings_provider.dart';
import 'package:asa/features/tasks/models/task_info_block.dart';
import 'package:asa/features/tasks/models/task_model.dart';
import 'package:asa/features/tasks/providers/task_provider.dart';
import 'package:asa/features/tasks/screens/task_file_viewer_screen.dart';
import 'package:asa/features/tasks/screens/task_image_viewer_screen.dart';
import 'package:asa/features/tasks/screens/task_pdf_viewer_screen.dart';
import 'package:asa/features/tasks/screens/task_text_viewer_screen.dart';
import 'package:asa/features/tasks/widgets/task_detail_sheet.dart';
import 'package:asa/features/tasks/widgets/task_editor_sheet.dart';

const _imageAttachment = TaskAttachment(
  id: 'image',
  type: TaskAttachmentType.image,
  name: 'photo.webp',
  value: '/app/task_attachments/photo.webp',
  mimeType: 'image/webp',
);

const _textAttachment = TaskAttachment(
  id: 'text',
  type: TaskAttachmentType.file,
  name: 'notes.txt',
  value: '/app/task_attachments/notes.txt',
  mimeType: 'text/plain',
);

const _pdfAttachment = TaskAttachment(
  id: 'pdf',
  type: TaskAttachmentType.file,
  name: 'contract.pdf',
  value: '/app/task_attachments/contract.pdf',
  mimeType: 'application/pdf',
);

const _officeAttachment = TaskAttachment(
  id: 'office',
  type: TaskAttachmentType.file,
  name: 'contract.docx',
  value: '/app/task_attachments/contract.docx',
  mimeType:
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
);

const _attachments = <TaskAttachment>[
  _imageAttachment,
  _textAttachment,
  _pdfAttachment,
  _officeAttachment,
];

final _task = TaskItem(
  id: 'attachment-route-task',
  title: 'Attachment routes',
  infoBlocks: [
    TaskInfoBlock.description(id: 'description', attachments: _attachments),
  ],
);

TaskProvider _fixtureProvider() {
  final provider = TaskProvider();
  provider.addTaskRaw(_task);
  return provider;
}

Widget _providers({required Widget child, TaskProvider? provider}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create:
            (_) => SettingsProvider(
              deviceNameProvider: () async => 'Test Device',
              systemLanguageCodeProvider: () => 'ru',
            ),
      ),
      ChangeNotifierProvider<TaskProvider>(
        create: (_) => provider ?? _fixtureProvider(),
      ),
    ],
    child: MaterialApp(home: child),
  );
}

Widget _detailHost(TaskItem task) {
  return Scaffold(
    body: Center(
      child: Builder(
        builder:
            (context) => ElevatedButton(
              key: const ValueKey('open-detail-sheet'),
              onPressed: () => showTaskDetailSheet(context, task),
              child: const Text('Open details'),
            ),
      ),
    ),
  );
}

Widget _editorHost(TaskItem task) {
  return Scaffold(
    body: Center(
      child: Builder(
        builder:
            (context) => ElevatedButton(
              key: const ValueKey('open-editor-sheet'),
              onPressed:
                  () =>
                      showTaskEditorSheet(context, folderId: null, task: task),
              child: const Text('Open editor'),
            ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HomeWidgetService.instance.debounceDelay = Duration.zero;
    installHomeWidgetChannelMock();
  });

  tearDown(() async {
    await HomeWidgetService.resetForTests();
    HomeWidgetService.instance.debounceDelay = const Duration(
      milliseconds: 300,
    );
    removeHomeWidgetChannelMock();
  });

  Future<void> openFromDetail(
    WidgetTester tester,
    TaskAttachment attachment,
    Type expectedViewer,
  ) async {
    await tester.pumpWidget(_providers(child: _detailHost(_task)));
    await tester.tap(find.byKey(const ValueKey('open-detail-sheet')));
    await tester.pumpAndSettle();

    final chip = find.byKey(ValueKey('detail-attachment-${attachment.id}'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(expectedViewer), findsOneWidget);
  }

  Future<void> openFromEditor(
    WidgetTester tester,
    TaskAttachment attachment,
    Type expectedViewer,
  ) async {
    await tester.pumpWidget(_providers(child: _editorHost(_task)));
    await tester.tap(find.byKey(const ValueKey('open-editor-sheet')));
    await tester.pumpAndSettle();

    final chip = find.byKey(ValueKey('attachment-chip-${attachment.id}'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(expectedViewer), findsOneWidget);
  }

  testWidgets('detail routes image attachments to image viewer', (
    tester,
  ) async {
    await openFromDetail(tester, _imageAttachment, TaskImageViewerScreen);
  });

  testWidgets('detail routes text attachments to text viewer', (tester) async {
    await openFromDetail(tester, _textAttachment, TaskTextViewerScreen);
  });

  testWidgets('detail routes PDF attachments to PDF viewer', (tester) async {
    await openFromDetail(tester, _pdfAttachment, TaskPdfViewerScreen);
  });

  testWidgets('detail routes Office attachments to file fallback', (
    tester,
  ) async {
    await openFromDetail(tester, _officeAttachment, TaskFileViewerScreen);
  });

  testWidgets('editor routes image attachments to image viewer', (
    tester,
  ) async {
    await openFromEditor(tester, _imageAttachment, TaskImageViewerScreen);
  });

  testWidgets('editor routes text attachments to text viewer', (tester) async {
    await openFromEditor(tester, _textAttachment, TaskTextViewerScreen);
  });

  testWidgets('editor routes PDF attachments to PDF viewer', (tester) async {
    await openFromEditor(tester, _pdfAttachment, TaskPdfViewerScreen);
  });

  testWidgets('editor routes Office attachments to file fallback', (
    tester,
  ) async {
    await openFromEditor(tester, _officeAttachment, TaskFileViewerScreen);
  });
}
