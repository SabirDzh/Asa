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
      dueDate: DateTime(2025, 1, 2),
      startTime: DateTime(2025, 1, 1, 10, 0),
      endTime: DateTime(2025, 1, 1, 11, 0),
      timerElapsedSeconds: 30,
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
    expect(
      find.byKey(const ValueKey('detail-time-line-Плановая длительность')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('detail-time-line-Период')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('detail-time-line-Фактическое время')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('detail-time-block')), findsOneWidget);
    final actualTime = tester.widget<RichText>(
      find.byKey(const ValueKey('detail-actual-time-value')),
    );
    expect(actualTime.text.toPlainText(), 'Фактическое время: 0:00');
    expect(find.text('Дата: 02.01.2025'), findsOneWidget);
    expect(find.text('Страницы'), findsOneWidget);
    expect(find.textContaining('12 / 120 стр.'), findsOneWidget);
    expect(find.text('Прочитать первую главу'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('detail-attachment-book-link')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('detail-attachment-names')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('detail-attachment-book-link')),
      findsOneWidget,
    );
    expect(find.text('Добавить информацию'), findsNothing);
    expect(find.text('Дополнительная информация'), findsOneWidget);
    expect(find.text('Редактировать'), findsNothing);
    expect(find.text('Установить время'), findsNothing);
    expect(find.text('Удалить'), findsNothing);
  });

  testWidgets('calendar icon takes priority over time icon in task row', (
    tester,
  ) async {
    final task = TaskItem(
      id: 'calendar-and-time-task',
      title: 'Calendar and time',
      calendarEventId: 'event-1',
      calendarId: 'calendar-1',
      startTime: DateTime(2025, 1, 1, 10, 0),
      endTime: DateTime(2025, 1, 1, 11, 0),
    );

    await tester.pumpWidget(
      _TestApp(child: TaskRow(task: task, enableDrag: false)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task_calendar_icon')), findsOneWidget);
    expect(find.byKey(const ValueKey('task_timer_icon')), findsNothing);
  });

  testWidgets('time icon is used when task has no calendar event', (
    tester,
  ) async {
    final task = TaskItem(
      id: 'time-only-task',
      title: 'Time only',
      startTime: DateTime(2025, 1, 1, 10, 0),
      endTime: DateTime(2025, 1, 1, 11, 0),
    );

    await tester.pumpWidget(
      _TestApp(child: TaskRow(task: task, enableDrag: false)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task_timer_icon')), findsOneWidget);
    expect(find.byKey(const ValueKey('task_calendar_icon')), findsNothing);
  });

  testWidgets('calendar icon takes priority over time icon in task details', (
    tester,
  ) async {
    final task = TaskItem(
      id: 'calendar-detail-task',
      title: 'Calendar detail',
      calendarEventId: 'event-1',
      calendarId: 'calendar-1',
      startTime: DateTime(2025, 1, 1, 10, 0),
      endTime: DateTime(2025, 1, 1, 11, 0),
    );

    await tester.pumpWidget(
      _TestApp(child: TaskRow(task: task, enableDrag: false)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calendar detail'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('detail_calendar_icon')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail_timer_icon')), findsNothing);
  });

  testWidgets('streak task keeps time icon when calendar id is stale', (
    tester,
  ) async {
    final task = TaskItem(
      id: 'streak-calendar-task',
      title: 'Streak task',
      folderId: 'system_streak_folder',
      calendarEventId: 'stale-event',
      calendarId: 'stale-calendar',
      startTime: DateTime(2025, 1, 1, 10, 0),
      endTime: DateTime(2025, 1, 1, 11, 0),
    );

    await tester.pumpWidget(
      _TestApp(child: TaskRow(task: task, enableDrag: false)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task_timer_icon')), findsOneWidget);
    expect(find.byKey(const ValueKey('task_calendar_icon')), findsNothing);

    await tester.tap(find.text('Streak task'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('detail_timer_icon')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail_calendar_icon')), findsNothing);
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

  testWidgets('task row updates localized semantics when language changes', (
    tester,
  ) async {
    final settings = SettingsProvider(
      deviceNameProvider: () async => 'Test Device',
      systemLanguageCodeProvider: () => 'ru',
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider(create: (_) => TaskProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TaskRow(
              task: TaskItem(id: 'localized-task', title: 'Localized task'),
              enableDrag: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Дополнительные действия'), findsOneWidget);
    await settings.setLanguage('en');
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('More options'), findsOneWidget);
  });
  testWidgets(
    'task completion update does not restart row entrance animation',
    (tester) async {
      final activeTask = TaskItem(
        id: 'animation-task',
        title: 'Animation task',
      );
      final rowKey = GlobalKey();
      await tester.pumpWidget(
        _TestApp(
          child: TaskRow(key: rowKey, task: activeTask, enableDrag: false),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final rowState = tester.state<State>(find.byKey(rowKey));
      final animationFinder = find.byType(TweenAnimationBuilder<double>);
      final initialAnimationState = tester.state<State>(animationFinder);

      await tester.pumpWidget(
        _TestApp(
          child: TaskRow(
            key: rowKey,
            task: activeTask.copyWith(isCompleted: true),
            enableDrag: false,
          ),
        ),
      );
      await tester.pump();

      final updatedRowState = tester.state<State>(find.byKey(rowKey));
      final updatedAnimationState = tester.state<State>(animationFinder);
      expect(identical(updatedRowState, rowState), isTrue);
      expect(identical(updatedAnimationState, initialAnimationState), isTrue);
    },
  );

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

  testWidgets('dropping a folder onto the streak folder shows a denial', (
    tester,
  ) async {
    final provider = TaskProvider();
    provider.addFolder('Root');
    final root = provider.folders.firstWhere((f) => f.name == 'Root');

    await tester.pumpWidget(
      _DropTestApp(
        provider: provider,
        source: root,
        target: FolderItem(
          id: 'system_streak_folder',
          name: 'День 1',
          isSystemStreak: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Root')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(find.text('День 1')));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Сюда переместить нельзя'), findsOneWidget);
    expect(find.textContaining('Папка перенесена'), findsNothing);
    expect(
      provider.folders.firstWhere((f) => f.id == root.id).parentFolderId,
      isNull,
    );
  });

  testWidgets('dropping a folder onto a regular folder moves it', (
    tester,
  ) async {
    final provider = TaskProvider();
    provider.addFolder('Root');
    provider.addFolder('Target');
    final root = provider.folders.firstWhere((f) => f.name == 'Root');
    final target = provider.folders.firstWhere((f) => f.name == 'Target');

    await tester.pumpWidget(
      _DropTestApp(provider: provider, source: root, target: target),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Root')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(find.text('Target')));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.textContaining('Папка перенесена в Target'), findsOneWidget);
    expect(
      provider.folders.firstWhere((f) => f.id == root.id).parentFolderId,
      target.id,
    );
  });

  testWidgets('dropping a task onto the streak folder shows a denial', (
    tester,
  ) async {
    final provider = TaskProvider();
    provider.addTask('Task');

    await tester.pumpWidget(
      _DropTestApp(
        provider: provider,
        taskSource: true,
        target: FolderItem(
          id: 'system_streak_folder',
          name: 'День 1',
          isSystemStreak: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Task')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(find.text('День 1')));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Сюда переместить нельзя'), findsOneWidget);
    expect(find.textContaining('Задача перенесена'), findsNothing);
    expect(provider.allTasks.single.folderId, isNot('system_streak_folder'));
  });
}

class _DropTestApp extends StatelessWidget {
  final TaskProvider provider;
  final FolderItem? source;
  final FolderItem target;
  final bool taskSource;

  const _DropTestApp({
    required this.provider,
    required this.target,
    this.source,
    this.taskSource = false,
  });

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
        ChangeNotifierProvider.value(value: provider),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: AppTheme.rowWidth,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (taskSource)
                    TaskRow(task: provider.allTasks.single, enableDrag: true)
                  else
                    FolderRow(folder: source!, enableDrag: true),
                  const SizedBox(height: 12),
                  FolderRow(folder: target, enableDrag: false),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _expectMenuBelowAnchor(WidgetTester tester) {
  final icon = find.byIcon(Iconsax.more_square);
  final card =
      find
          .ancestor(
            of: icon,
            matching: find.byWidgetPredicate(
              (w) => w is Container || w is AnimatedContainer,
            ),
          )
          .first;
  final menu =
      find
          .ancestor(
            of: find.byType(AnchoredPopupMenuItem<String>),
            matching: find.byType(Material),
          )
          .first;
  final cardRect = tester.getRect(card);
  final menuRect = tester.getRect(menu);
  // The menu must sit 6 px below the task/folder card and be pinned to its right edge.
  expect(menuRect.top - cardRect.bottom, closeTo(6, 0.01));
  expect(menuRect.right, closeTo(cardRect.right, 0.01));
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
