import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asa/features/settings/providers/settings_provider.dart';
import 'package:asa/features/tasks/providers/task_provider.dart';
import 'package:asa/features/tasks/models/task_model.dart';
import 'package:asa/features/tasks/screens/folder_detail_screen.dart';
import 'package:asa/core/home_widget_service.dart';
import 'home_widget_channel_mock.dart';

Widget createTestApp(FolderItem folder, {TaskProvider? provider}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (_) => SettingsProvider(systemLanguageCodeProvider: () => 'ru'),
      ),
      ChangeNotifierProvider(create: (_) => provider ?? TaskProvider()),
    ],
    child: MaterialApp(home: FolderDetailScreen(folder: folder)),
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

  testWidgets('renders empty folder state', (tester) async {
    final folder = FolderItem(id: 'test', name: 'Test Folder');
    await tester.pumpWidget(createTestApp(folder));
    await tester.pumpAndSettle();

    expect(find.text('Test Folder'), findsOneWidget);
    expect(find.text('В этой папке пока нет задач'), findsOneWidget);
  });

  testWidgets('shows streak folder icon', (tester) async {
    final folder = FolderItem(
      id: 'streak_5',
      name: 'День 5',
      isSystemStreak: true,
    );
    await tester.pumpWidget(createTestApp(folder));
    await tester.pumpAndSettle();

    expect(find.text('День 5'), findsOneWidget);
    expect(find.byIcon(Iconsax.calendar_1), findsOneWidget);
  });

  testWidgets('shows reorder handles for subfolders and tasks', (tester) async {
    final provider = TaskProvider();
    provider.addFolder('Work');
    final folder = provider.folders.firstWhere((item) => item.name == 'Work');
    provider.addFolder('Subfolder', parentFolderId: folder.id);
    provider.addTask('First task', folderId: folder.id);
    provider.addTask('Second task', folderId: folder.id);

    await tester.pumpWidget(createTestApp(folder, provider: provider));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('folder-reorder-handle')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-reorder-handle')), findsNWidgets(2));
  });

  testWidgets('swiping a nested task left moves it to the parent folder', (
    tester,
  ) async {
    final provider = TaskProvider();
    provider.addFolder('Parent');
    final parent = provider.folders.firstWhere((item) => item.name == 'Parent');
    provider.addFolder('Child', parentFolderId: parent.id);
    final child = provider.folders.firstWhere((item) => item.name == 'Child');
    provider.addTask('Nested task', folderId: child.id);

    await tester.pumpWidget(createTestApp(child, provider: provider));
    await tester.pumpAndSettle();

    await tester.drag(find.text('Nested task'), const Offset(-350, 0));
    await tester.pumpAndSettle();

    expect(provider.getFolderTasks(child.id), isEmpty);
    expect(provider.getFolderTasks(parent.id).single.title, 'Nested task');
  });

  testWidgets(
    'swiping a task in a root-level folder moves it to the visible root',
    (tester) async {
      final provider = TaskProvider();
      provider.addFolder('Root folder');
      final rootFolder = provider.folders.firstWhere(
        (item) => item.name == 'Root folder',
      );
      provider.addTask('Root-level task', folderId: rootFolder.id);

      await tester.pumpWidget(createTestApp(rootFolder, provider: provider));
      await tester.pumpAndSettle();

      await tester.drag(find.text('Root-level task'), const Offset(-350, 0));
      await tester.pumpAndSettle();

      expect(
        find.text('Задачу нельзя перенести на главный экран'),
        findsNothing,
      );
      expect(provider.getFolderTasks(rootFolder.id), isEmpty);
      expect(provider.filteredRootTasks.single.title, 'Root-level task');
      expect(provider.allTasks.single.folderId, isNull);
    },
  );

  testWidgets('swiping a nested folder left moves it to the parent folder', (
    tester,
  ) async {
    final provider = TaskProvider();
    provider.addFolder('Grandparent');
    final grandparent = provider.folders.firstWhere(
      (item) => item.name == 'Grandparent',
    );
    provider.addFolder('Parent', parentFolderId: grandparent.id);
    final parent = provider.folders.firstWhere((item) => item.name == 'Parent');
    provider.addFolder('Child', parentFolderId: parent.id);
    final child = provider.folders.firstWhere((item) => item.name == 'Child');

    await tester.pumpWidget(createTestApp(parent, provider: provider));
    await tester.pumpAndSettle();

    await tester.drag(find.text('Child'), const Offset(-350, 0));
    await tester.pumpAndSettle();

    expect(
      provider.folders
          .firstWhere((folder) => folder.id == child.id)
          .parentFolderId,
      grandparent.id,
    );
  });

  testWidgets('shows tasks inside folder', (tester) async {
    final taskProvider = TaskProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create:
                (_) => SettingsProvider(systemLanguageCodeProvider: () => 'ru'),
          ),
          ChangeNotifierProvider.value(value: taskProvider),
        ],
        child: MaterialApp(
          home: FolderDetailScreen(
            folder: FolderItem(id: 'test_folder', name: 'Work'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('В этой папке пока нет задач'), findsOneWidget);
  });

  testWidgets(
    'shows a notice instead of opening folder creation in streak folder',
    (tester) async {
      final folder = FolderItem(
        id: 'system_streak_folder',
        name: 'День 1',
        isSystemStreak: true,
      );
      await tester.pumpWidget(createTestApp(folder));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Создать папку'));
      await tester.pumpAndSettle();

      expect(
        find.text('В системной папке нельзя создавать подпапки'),
        findsOneWidget,
      );
      expect(find.text('новая папка...'), findsNothing);
    },
  );

  testWidgets('creating a task opens the full editor with add-information', (
    tester,
  ) async {
    final folder = FolderItem(id: 'test_folder', name: 'Work');
    await tester.pumpWidget(createTestApp(folder));
    await tester.pumpAndSettle();

    // Open the floating menu and choose task creation.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Создать задачу'));
    await tester.pumpAndSettle();

    // The full editor (not the generic one-line input) must appear.
    expect(find.byKey(const ValueKey('task-title-input')), findsOneWidget);
    expect(find.byKey(const ValueKey('add-task-information')), findsOneWidget);
    expect(find.byKey(const ValueKey('save-task-editor')), findsOneWidget);
  });
}
