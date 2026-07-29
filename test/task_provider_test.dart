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

    String addTask(String title, {String? folderId}) {
      provider.addTask(title, folderId: folderId);
      return provider.allTasks.last.id;
    }

    test('starts with empty tasks and folders', () {
      expect(provider.filteredFolders, isEmpty);
    });

    test('addTask creates a task', () {
      addTask('Test task');
      expect(provider.allTasks.length, 1);
      expect(provider.allTasks[0].title, 'Test task');
    });

    test('addFolder creates a folder', () {
      provider.addFolder('Work');
      expect(provider.filteredFolders.length, 1);
      expect(provider.filteredFolders[0].name, 'Work');
    });

    test('toggleTask flips isCompleted', () {
      final taskId = addTask('Test');
      expect(provider.allTasks.first.isCompleted, false);

      provider.toggleTask(taskId);
      expect(provider.allTasks.first.isCompleted, true);

      provider.toggleTask(taskId);
      expect(provider.allTasks.first.isCompleted, false);
    });

    test('updateTask changes title', () {
      final taskId = addTask('Old title');

      provider.updateTask(taskId, 'New title');
      expect(provider.allTasks.first.title, 'New title');
    });

    test('updateTask throws on >250 chars', () {
      final taskId = addTask('Test');

      expect(
        () => provider.updateTask(taskId, 'a' * 251),
        throwsA(isA<Exception>()),
      );
    });

    test('removeTask soft-deletes the task', () {
      final taskId = addTask('Test');

      provider.removeTask(taskId);
      expect(provider.tasks, isEmpty);
      expect(provider.allTasks.length, 1);
      expect(provider.allTasks.first.isDeleted, true);
    });

    test('removeFolder soft-deletes folder and its tasks', () {
      provider.addFolder('Work');
      final folderId = provider.filteredFolders.first.id;
      addTask('Task 1', folderId: folderId);
      addTask('Task 2', folderId: folderId);

      provider.removeFolder(folderId);
      expect(provider.filteredFolders, isEmpty);
      expect(provider.tasks, isEmpty);
      expect(provider.allTasks.length, 2);
      expect(provider.allTasks.every((t) => t.isDeleted), true);
    });

    test('clearAllTasks removes all tasks', () {
      addTask('Task 1');
      addTask('Task 2');
      provider.clearAllTasks();
      expect(provider.tasks, isEmpty);
    });

    test('clearAllData removes everything', () {
      provider.addFolder('Work');
      addTask('Task');
      provider.clearAllData();
      expect(provider.filteredFolders, isEmpty);
      expect(provider.tasks, isEmpty);
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
      final taskId = addTask('Test task');

      provider.moveTaskToFolder(taskId, folderId);
      final folderTasks = provider.getFolderTasks(folderId);
      expect(folderTasks.length, 1);
      expect(folderTasks[0].id, taskId);
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
