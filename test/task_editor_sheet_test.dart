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
import 'package:asa/features/tasks/widgets/task_editor_sheet.dart';

Widget createEditorTestApp({
  TaskProvider? provider,
  TaskItem? task,
  TaskAttachmentPicker? attachmentPicker,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create:
            (_) => SettingsProvider(
              deviceNameProvider: () async => 'Test Device',
              systemLanguageCodeProvider: () => 'ru',
            ),
      ),
      ChangeNotifierProvider<TaskProvider>.value(
        value: provider ?? TaskProvider(),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder:
              (context) => Center(
                child: ElevatedButton(
                  onPressed:
                      () => showTaskEditorSheet(
                        context,
                        folderId: 'folder-1',
                        task: task,
                        attachmentPicker: attachmentPicker,
                      ),
                  child: const Text('Open editor'),
                ),
              ),
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

  testWidgets('shows add information control below the task title', (
    tester,
  ) async {
    await tester.pumpWidget(createEditorTestApp());
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task-title-input')), findsOneWidget);
    expect(find.byKey(const ValueKey('add-task-information')), findsOneWidget);
  });

  testWidgets('adds a quantity block to the draft', (tester) async {
    await tester.pumpWidget(createEditorTestApp());
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-task-information')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-quantity-block')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('quantity-target-input')), findsOneWidget);
    expect(find.byKey(const ValueKey('quantity-unit-input')), findsOneWidget);
  });

  testWidgets('adds a description block and rejects an unsafe link', (
    tester,
  ) async {
    await tester.pumpWidget(createEditorTestApp());
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-task-information')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-description-block')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('description-text-input')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('add-description-link')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('add-link-url-input')),
      'javascript:alert(1)',
    );
    await tester.tap(find.byKey(const ValueKey('add-link-confirm')));
    await tester.pumpAndSettle();

    expect(
      find.text('Введите корректную ссылку http или https'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('add-link-url-input')), findsOneWidget);
  });

  testWidgets('canceling the editor does not create a task', (tester) async {
    final provider = TaskProvider();
    await tester.pumpWidget(createEditorTestApp(provider: provider));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('task-title-input')),
      'Read a book',
    );
    await tester.tap(find.byKey(const ValueKey('cancel-task-editor')));
    await tester.pumpAndSettle();

    expect(provider.tasks, isEmpty);
  });

  testWidgets(
    'does not invoke the picker after reaching the attachment limit',
    (tester) async {
      final attachments = List.generate(
        kMaxTaskAttachmentsPerTask,
        (index) => TaskAttachment(
          id: 'attachment-$index',
          type: TaskAttachmentType.file,
          name: 'file-$index.pdf',
          value: '/app/task_attachments/file-$index.pdf',
        ),
      );
      final task = TaskItem(
        id: 'full-task',
        title: 'Task with references',
        infoBlocks: [
          TaskInfoBlock.description(id: 'details', attachments: attachments),
        ],
      );
      var pickerCalls = 0;

      await tester.pumpWidget(
        createEditorTestApp(
          task: task,
          attachmentPicker: (type, count) async {
            pickerCalls++;
            return null;
          },
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-description-file')));
      await tester.pumpAndSettle();

      expect(pickerCalls, 0);
      expect(find.text('Достигнут лимит в 20 вложений'), findsOneWidget);
    },
  );

  testWidgets('saving a title and quantity block creates the task', (
    tester,
  ) async {
    final provider = TaskProvider();
    await tester.pumpWidget(createEditorTestApp(provider: provider));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('task-title-input')),
      'Drink water',
    );
    await tester.tap(find.byKey(const ValueKey('add-task-information')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-quantity-block')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('quantity-target-input')),
      '3',
    );
    await tester.enterText(
      find.byKey(const ValueKey('quantity-unit-input')),
      'glasses',
    );
    await tester.tap(find.byKey(const ValueKey('save-task-editor')));
    await tester.pumpAndSettle();

    expect(provider.tasks, hasLength(1));
    expect(provider.tasks.single.title, 'Drink water');
    expect(provider.tasks.single.folderId, 'folder-1');
    expect(provider.tasks.single.infoBlocks.single.targetValue, 3);
  });
}
