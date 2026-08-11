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

    final chooser = tester.widget<Container>(
      find.byKey(const ValueKey('task-block-chooser-sheet')),
    );
    expect(chooser.clipBehavior, Clip.antiAlias);
    final decoration = chooser.decoration! as BoxDecoration;
    final radius = decoration.borderRadius as BorderRadius;
    expect(radius.topLeft, const Radius.circular(24));
    expect(radius.topRight, const Radius.circular(24));

    await tester.tap(find.byKey(const ValueKey('add-quantity-block')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('quantity-target-input')), findsOneWidget);
    expect(find.byKey(const ValueKey('quantity-unit-input')), findsOneWidget);
    expect(find.text('Что считаем?'), findsOneWidget);
    expect(find.text('Например: страницы, стаканы или минуты'), findsOneWidget);
    expect(find.text('Раз'), findsOneWidget);
  });

  testWidgets('types a quantity unit directly in the text field', (
    tester,
  ) async {
    final provider = TaskProvider();
    await tester.pumpWidget(createEditorTestApp(provider: provider));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('task-title-input')),
      'Read pages',
    );
    await tester.tap(find.byKey(const ValueKey('add-task-information')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-quantity-block')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('quantity-unit-input')),
      'Страницы',
    );
    await tester.pumpAndSettle();
    final saveButtonFinder = find.byKey(const ValueKey('save-task-editor'));
    final saveButtonElement = saveButtonFinder.evaluate().last;
    await Scrollable.ensureVisible(saveButtonElement, duration: Duration.zero);
    await tester.pump();
    await tester.tap(saveButtonFinder.last, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(provider.tasks.single.infoBlocks.single.unit, 'Страницы');
  });

  testWidgets('allows a custom quantity unit by typing', (tester) async {
    final provider = TaskProvider();
    await tester.pumpWidget(createEditorTestApp(provider: provider));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('task-title-input')),
      'Track books',
    );
    await tester.tap(find.byKey(const ValueKey('add-task-information')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-quantity-block')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('quantity-unit-input')),
      'книги',
    );
    await tester.pumpAndSettle();
    final saveButtonFinder = find.byKey(const ValueKey('save-task-editor'));
    final saveButtonElement = saveButtonFinder.evaluate().last;
    await Scrollable.ensureVisible(saveButtonElement, duration: Duration.zero);
    await tester.pump();
    await tester.tap(saveButtonFinder.last, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(provider.tasks.single.infoBlocks.single.unit, 'книги');
  });

  testWidgets('limits quantity blocks to three per task', (tester) async {
    await tester.pumpWidget(createEditorTestApp());
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    for (var index = 0; index < 3; index++) {
      await tester.tap(find.byKey(const ValueKey('add-task-information')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-quantity-block')));
      await tester.pumpAndSettle();
    }

    expect(
      find.widgetWithText(TextFormField, 'Что считаем?'),
      findsNWidgets(3),
    );
    expect(
      find.text('Можно добавить не больше 3 блоков количества'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('add-task-information')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('add-quantity-block')), findsNothing);
    expect(find.byKey(const ValueKey('add-description-block')), findsOneWidget);
  });

  testWidgets('preserves existing quantity blocks above the new-item limit', (
    tester,
  ) async {
    final task = TaskItem(
      id: 'legacy-quantity-task',
      title: 'Legacy metrics',
      infoBlocks: [
        for (var index = 0; index < 4; index++)
          TaskInfoBlock.quantity(
            id: 'quantity-$index',
            targetValue: index + 1,
            unit: kQuantityUnitTimes,
          ),
      ],
    );

    await tester.pumpWidget(createEditorTestApp(task: task));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextFormField, 'Что считаем?'),
      findsNWidgets(4),
    );
    expect(
      find.text('Можно добавить не больше 3 блоков количества'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('add-task-information')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('add-quantity-block')), findsNothing);
  });

  testWidgets('allows only one description block per task', (tester) async {
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

    await tester.tap(find.byKey(const ValueKey('add-task-information')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('add-description-block')), findsNothing);
    expect(find.byKey(const ValueKey('add-quantity-block')), findsOneWidget);
  });

  testWidgets('shows attachment mention suggestions after typing @', (
    tester,
  ) async {
    final task = TaskItem(
      id: 'mention-task',
      title: 'Mentions',
      infoBlocks: [
        TaskInfoBlock.description(
          id: 'details',
          attachments: const [
            TaskAttachment(
              id: 'contract',
              type: TaskAttachmentType.file,
              name: 'contract.pdf',
              value: '/tmp/task_attachments/contract.pdf',
            ),
            TaskAttachment(
              id: 'photo',
              type: TaskAttachmentType.image,
              name: 'photo.png',
              value: '/tmp/task_attachments/photo.png',
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(createEditorTestApp(task: task));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    final description = find.byKey(const ValueKey('description-text-input'));
    await tester.enterText(description, '@con');
    await tester.pump();

    expect(
      find.byKey(const ValueKey('attachment-mention-suggestions')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('attachment-mention-contract')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('attachment-mention-photo')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('attachment-mention-contract')));
    await tester.pump();
    expect(
      tester.widget<TextFormField>(description).controller!.text,
      '[@contract.pdf](attachment://contract) ',
    );
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
    await tester.tap(find.byKey(const ValueKey('attachment-action-add')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('add-link-sheet')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
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

  testWidgets('adds a valid link from the bottom sheet', (tester) async {
    await tester.pumpWidget(createEditorTestApp());
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-task-information')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-description-block')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('attachment-action-add')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('add-link-sheet')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('add-link-url-input')),
      'https://example.com/docs',
    );
    await tester.tap(find.byKey(const ValueKey('add-link-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('add-link-sheet')), findsNothing);
    expect(find.text('example.com'), findsOneWidget);
  });

  testWidgets('canceling link input closes only the link sheet', (
    tester,
  ) async {
    await tester.pumpWidget(createEditorTestApp());
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-task-information')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-description-block')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('attachment-action-add')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('add-link-sheet')), findsOneWidget);
    await tester.tap(find.text('Отмена').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('add-link-sheet')), findsNothing);
    expect(
      find.byKey(const ValueKey('description-text-input')),
      findsOneWidget,
    );
    expect(find.text('example.com'), findsNothing);
  });

  testWidgets('submitting link input with Done adds a valid link', (
    tester,
  ) async {
    await tester.pumpWidget(createEditorTestApp());
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-task-information')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-description-block')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('attachment-action-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('add-link-url-input')),
      'https://example.com/done',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('add-link-sheet')), findsNothing);
    expect(find.text('example.com'), findsOneWidget);
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
      await tester.tap(
        find.byKey(const ValueKey('attachment-action-selector')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить файл').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('attachment-action-add')));
      await tester.pumpAndSettle();

      expect(pickerCalls, 0);
      expect(find.text('Достигнут лимит в 20 вложений'), findsOneWidget);
    },
  );

  testWidgets(
    'selecting an attachment action does not invoke picker until plus',
    (tester) async {
      var pickerCalls = 0;
      await tester.pumpWidget(
        createEditorTestApp(
          attachmentPicker: (type, count) async {
            pickerCalls++;
            return null;
          },
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-task-information')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-description-block')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('attachment-action-selector')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить файл').last);
      await tester.pumpAndSettle();

      expect(pickerCalls, 0);
      expect(find.text('Добавить файл'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('attachment-action-add')));
      await tester.pumpAndSettle();
      expect(pickerCalls, 1);
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
    final saveButtonFinder = find.byKey(const ValueKey('save-task-editor'));
    final saveButtonElement = saveButtonFinder.evaluate().last;
    await Scrollable.ensureVisible(saveButtonElement, duration: Duration.zero);
    await tester.pump();
    await tester.tap(saveButtonFinder.last, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(provider.tasks, hasLength(1));
    expect(provider.tasks.single.title, 'Drink water');
    expect(provider.tasks.single.folderId, 'folder-1');
    expect(provider.tasks.single.infoBlocks.single.targetValue, 3);
  });
}
