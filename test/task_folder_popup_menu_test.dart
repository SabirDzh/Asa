import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asa/core/anchored_popup_menu.dart';
import 'package:asa/core/home_widget_service.dart';
import 'home_widget_channel_mock.dart';
import 'package:asa/core/theme.dart';
import 'package:asa/features/settings/providers/settings_provider.dart';
import 'package:asa/features/tasks/models/task_info_block.dart';
import 'package:asa/features/tasks/models/task_model.dart';
import 'package:asa/features/tasks/providers/task_provider.dart';
import 'package:asa/features/tasks/widgets/folder_card.dart';
import 'package:asa/features/tasks/widgets/task_card.dart';

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

  testWidgets('long press keeps the drag feedback menu spacing compact', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: TaskRow(task: TaskItem(id: 'drag-task', title: 'Drag task')),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Drag task')),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final feedbackMenu = find.byKey(const ValueKey('task-drag-feedback-menu'));
    expect(feedbackMenu, findsOneWidget);
    expect(tester.getSize(feedbackMenu).width, 24 + AppTheme.rowGap);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('task ellipsis opens the task action menu', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: TaskRow(
          task: TaskItem(id: 'task-1', title: 'Test task'),
          enableDrag: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Iconsax.more_square));
    await tester.pumpAndSettle();

    expect(find.text('Редактировать'), findsOneWidget);
    expect(find.text('Удалить'), findsOneWidget);
    _expectMenuBelowAnchor(tester);

    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    expect(find.text('Удаление'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
  });

  testWidgets('task row shows only timer icon while details show time values', (
    tester,
  ) async {
    final task = TaskItem(
      id: 'timed-task',
      title: 'Time task',
      startTime: DateTime(2025, 1, 1, 10, 0),
      endTime: DateTime(2025, 1, 1, 11, 0),
      infoBlocks: [
        TaskInfoBlock.quantity(
          id: 'pages',
          label: 'Страницы',
          currentValue: 12,
          targetValue: 120,
          unit: 'стр.',
        ),
        TaskInfoBlock.description(
          id: 'book',
          text: 'Прочитать первую главу',
          attachments: [
            const TaskAttachment(
              id: 'book-link',
              type: TaskAttachmentType.link,
              name: 'Источник',
              value: 'https://example.com/book',
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _TestApp(child: TaskRow(task: task, enableDrag: false)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task_timer_icon')), findsOneWidget);
    expect(find.text('1:30'), findsNothing);
    expect(find.text('10:00'), findsNothing);
    expect(find.text('11:00'), findsNothing);

    await tester.tap(find.text('Time task'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('detail_timer_icon')), findsOneWidget);
    expect(find.textContaining('Плановая длительность: 1:00'), findsOneWidget);
    expect(find.textContaining('Период: 10:00 – 11:00'), findsOneWidget);
    expect(find.textContaining('Страницы: 12 / 120 стр.'), findsOneWidget);
    expect(find.text('Прочитать первую главу'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('detail-attachment-book-link')),
      findsOneWidget,
    );
    expect(find.text('Источник'), findsOneWidget);
    expect(find.text('Редактировать'), findsNothing);
    expect(find.text('Установить время'), findsNothing);
    expect(find.text('Удалить'), findsNothing);
  });

  testWidgets('time editor opens from the timer icon', (tester) async {
    final task = TaskItem(
      id: 'timer-icon-task',
      title: 'Timer icon task',
      startTime: DateTime(2025, 1, 1, 10, 0),
      endTime: DateTime(2025, 1, 1, 10, 30),
    );

    await tester.pumpWidget(
      _TestApp(child: TaskRow(task: task, enableDrag: false)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('task_timer_icon')));
    await tester.pumpAndSettle();

    expect(find.text('Установить время'), findsOneWidget);
    expect(find.text('Период'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('time editor opens from the task ellipsis menu', (tester) async {
    final task = TaskItem(
      id: 'timer-task',
      title: 'Timer task',
      startTime: DateTime(2025, 1, 1, 10, 0),
      endTime: DateTime(2025, 1, 1, 10, 30),
    );

    await tester.pumpWidget(
      _TestApp(child: TaskRow(task: task, enableDrag: false)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Iconsax.more_square));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Установить время'));
    await tester.pumpAndSettle();

    expect(find.text('Установить время'), findsOneWidget);
    expect(find.text('Период'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('task edit action opens the information editor', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: TaskRow(
          task: TaskItem(id: 'editable-task', title: 'Editable task'),
          enableDrag: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Iconsax.more_square));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Редактировать'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task-title-input')), findsOneWidget);
    expect(find.byKey(const ValueKey('add-task-information')), findsOneWidget);
  });

  testWidgets('folder ellipsis opens the folder action menu', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: FolderRow(
          folder: FolderItem(id: 'folder-1', name: 'Test folder'),
          enableDrag: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Iconsax.more_square));
    await tester.pumpAndSettle();

    expect(find.text('Редактировать'), findsOneWidget);
    expect(find.text('Удалить'), findsOneWidget);
    _expectMenuBelowAnchor(tester);

    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    expect(find.text('Удаление'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
  });
}

void _expectMenuBelowAnchor(WidgetTester tester) {
  final anchor =
      find
          .ancestor(
            of: find.byIcon(Iconsax.more_square),
            matching: find.byType(GestureDetector),
          )
          .first;
  final menu =
      find
          .ancestor(
            of: find.byType(AnchoredPopupMenuItem<String>),
            matching: find.byType(Material),
          )
          .first;
  final anchorRect = tester.getRect(anchor);
  final menuRect = tester.getRect(menu);
  expect(menuRect.top - anchorRect.bottom, closeTo(6, 0.01));
}

class _TestApp extends StatelessWidget {
  final Widget child;

  const _TestApp({required this.child});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create:
              (_) => SettingsProvider(
                deviceNameProvider: () async => 'Test Device',
                systemLanguageCodeProvider: () => 'ru',
              ),
        ),
        ChangeNotifierProvider(create: (_) => TaskProvider()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(width: AppTheme.rowWidth, child: child)),
        ),
      ),
    );
  }
}
