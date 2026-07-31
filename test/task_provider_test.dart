import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:asa/features/tasks/models/task_model.dart';
import 'package:asa/features/tasks/providers/task_provider.dart';

void main() {
  group('TaskProvider', () {
    late TaskProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = TaskProvider();
    });

    String addTaskForTest(String title, {String? folderId}) {
      provider.addTask(title, folderId: folderId);
      return provider.allTasks.last.id;
    }

    test('starts with empty tasks and folders', () {
      expect(provider.filteredFolders, isEmpty);
    });

    test('addTask creates a task', () {
      addTaskForTest('Test task');
      expect(provider.allTasks.length, 1);
      expect(provider.allTasks[0].title, 'Test task');
    });

    test('addFolder creates a folder', () {
      provider.addFolder('Work');
      expect(provider.filteredFolders.length, 1);
      expect(provider.filteredFolders[0].name, 'Work');
    });

    test('addFolder stores iconAsset', () {
      provider.addFolder('Work', iconAsset: 'assets/icons/work.svg');
      expect(provider.filteredFolders.first.iconAsset, 'assets/icons/work.svg');
    });

    test('toggleTask flips isCompleted', () {
      final taskId = addTaskForTest('Test');
      expect(provider.allTasks.first.isCompleted, false);

      provider.toggleTask(taskId);
      expect(provider.allTasks.first.isCompleted, true);

      provider.toggleTask(taskId);
      expect(provider.allTasks.first.isCompleted, false);
    });

    test('updateTask changes title', () {
      final taskId = addTaskForTest('Old title');

      provider.updateTask(taskId, 'New title');
      expect(provider.allTasks.first.title, 'New title');
    });

    test('updateTask throws on >250 chars', () {
      final taskId = addTaskForTest('Test');

      expect(
        () => provider.updateTask(taskId, 'a' * 251),
        throwsA(isA<Exception>()),
      );
    });

    test('removeTask soft-deletes the task', () {
      final taskId = addTaskForTest('Test');

      provider.removeTask(taskId);
      expect(provider.tasks, isEmpty);
      expect(provider.allTasks.length, 1);
      expect(provider.allTasks.first.isDeleted, true);
    });

    test('removeFolder soft-deletes folder and its tasks', () {
      provider.addFolder('Work');
      final folderId = provider.filteredFolders.first.id;
      addTaskForTest('Task 1', folderId: folderId);
      addTaskForTest('Task 2', folderId: folderId);

      provider.removeFolder(folderId);
      expect(provider.filteredFolders, isEmpty);
      expect(provider.tasks, isEmpty);
      expect(provider.allTasks.length, 2);
      expect(provider.allTasks.every((t) => t.isDeleted), true);
    });

    test('clearAllTasks removes all tasks', () {
      addTaskForTest('Task 1');
      addTaskForTest('Task 2');
      provider.clearAllTasks();
      expect(provider.tasks, isEmpty);
    });

    test('clearAllData removes everything', () {
      provider.addFolder('Work');
      addTaskForTest('Task');
      provider.clearAllData();
      expect(provider.filteredFolders, isEmpty);
      expect(provider.tasks, isEmpty);
    });

    test('setTaskTime updates start, end and expectedDuration', () {
      final taskId = addTaskForTest('Time task');
      final start = DateTime(2025, 1, 1, 16, 0);
      final end = DateTime(2025, 1, 1, 17, 0);

      provider.setTaskTime(
        taskId,
        startTime: start,
        endTime: end,
        expectedDuration: 90,
      );

      final task = provider.tasks.first;
      expect(task.startTime?.isAtSameMomentAs(start), true);
      expect(task.endTime?.isAtSameMomentAs(end), true);
      expect(task.expectedDuration, 90);
    });

    test('setFilter changes filter', () {
      provider.setFilter(TaskFilter.foldersOnly);
      expect(provider.filter, TaskFilter.foldersOnly);

      provider.setFilter(TaskFilter.all);
      expect(provider.filter, TaskFilter.all);
    });

    test('setSearchQuery filters folders', () {
      provider.addFolder('Work Projects');
      provider.addFolder('Personal');
      provider.setSearchQuery('work');
      expect(provider.filteredFolders.length, 1);
      expect(provider.filteredFolders[0].name, 'Work Projects');
    });

    test('moveTaskToFolder moves task between folders', () {
      provider.addFolder('Work');
      final folderId = provider.filteredFolders.first.id;
      final taskId = addTaskForTest('Test task');

      provider.moveTaskToFolder(taskId, folderId);
      final folderTasks = provider.getFolderTasks(folderId);
      expect(folderTasks.length, 1);
      expect(folderTasks[0].id, taskId);
    });

    test('moveFolderToFolder rejects moving a folder into its descendant', () {
      provider.addFolder('Parent');
      final parentId = provider.filteredFolders.first.id;
      provider.addFolder('Child', parentFolderId: parentId);
      final childId = provider.getSubfolders(parentId).first.id;

      provider.moveFolderToFolder(parentId, childId);

      expect(provider.folders.firstWhere((f) => f.id == parentId).parentFolderId, null);
      expect(provider.folders.firstWhere((f) => f.id == childId).parentFolderId, parentId);
    });

    test('moveFolderToFolder ignores missing target parent', () {
      provider.addFolder('Parent');
      final parentId = provider.filteredFolders.first.id;

      provider.moveFolderToFolder(parentId, 'missing');

      expect(provider.folders.first.parentFolderId, null);
    });

    test('clearAllFolders soft-deletes folders and their tasks', () {
      provider.addFolder('Work');
      final folderId = provider.filteredFolders.first.id;
      final taskId = addTaskForTest('Task', folderId: folderId);

      provider.clearAllFolders();

      expect(provider.folders, isEmpty);
      expect(provider.tasks, isEmpty);
      expect(provider.allTasks.firstWhere((t) => t.id == taskId).isDeleted, true);
      expect(provider.allTasks.firstWhere((t) => t.id == taskId).folderId, folderId);
    });

    test('serializes the latest task state to preferences', () async {
      provider.addTask('First');
      provider.addTask('Second');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final prefs = await SharedPreferences.getInstance();
      final savedTasks = prefs.getString('saved_tasks');

      expect(savedTasks, isNotNull);
      expect(savedTasks, contains('First'));
      expect(savedTasks, contains('Second'));
    });

    group('upsertTask / upsertFolder', () {
      test('upsertTask adds a new task', () {
        final task = TaskItem(id: 't1', title: 'New');
        final changed = provider.upsertTask(task);

        expect(changed, true);
        expect(provider.tasks.length, 1);
        expect(provider.tasks.first.id, 't1');
      });

      test('upsertTask overwrites with newer updatedAt', () {
        provider.addTask('Old');
        final id = provider.tasks.first.id;
        final newer = TaskItem(id: id, title: 'Newer', updatedAt: DateTime.now().add(const Duration(days: 1)));

        final changed = provider.upsertTask(newer);

        expect(changed, true);
        expect(provider.tasks.first.title, 'Newer');
      });

      test('upsertTask keeps newer local task', () {
        provider.addTask('Local');
        final id = provider.tasks.first.id;
        final older = TaskItem(id: id, title: 'Older', updatedAt: DateTime.now().subtract(const Duration(days: 1)));

        final changed = provider.upsertTask(older);

        expect(changed, false);
        expect(provider.tasks.first.title, 'Local');
      });

      test('upsertFolder adds a new folder', () {
        final folder = FolderItem(id: 'f1', name: 'New');
        final changed = provider.upsertFolder(folder);

        expect(changed, true);
        expect(provider.folders.any((f) => f.id == 'f1'), true);
      });

      test('upsertFolder overwrites with newer updatedAt', () {
        provider.addFolder('Old');
        final id = provider.folders.first.id;
        final newer = FolderItem(id: id, name: 'Newer', updatedAt: DateTime.now().add(const Duration(days: 1)));

        final changed = provider.upsertFolder(newer);

        expect(changed, true);
        expect(provider.folders.first.name, 'Newer');
      });
    });
  });
}
