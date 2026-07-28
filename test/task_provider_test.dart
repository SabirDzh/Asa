import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:asa/features/tasks/providers/task_provider.dart';

void main() {
  group('TaskProvider', () {
    late TaskProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = TaskProvider();
    });

    String _addTask(String title, {String? folderId}) {
      provider.addTask(title, folderId: folderId);
      return provider.allTasks.last.id;
    }

    test('starts with empty tasks and folders', () {
      expect(provider.filteredFolders, isEmpty);
    });

    test('addTask creates a task', () {
      _addTask('Test task');
      expect(provider.allTasks.length, 1);
      expect(provider.allTasks[0].title, 'Test task');
    });

    test('addFolder creates a folder', () {
      provider.addFolder('Work');
      expect(provider.filteredFolders.length, 1);
      expect(provider.filteredFolders[0].name, 'Work');
    });

    test('toggleTask flips isCompleted', () {
      final taskId = _addTask('Test');
      expect(provider.allTasks.first.isCompleted, false);

      provider.toggleTask(taskId);
      expect(provider.allTasks.first.isCompleted, true);

      provider.toggleTask(taskId);
      expect(provider.allTasks.first.isCompleted, false);
    });

    test('updateTask changes title', () {
      final taskId = _addTask('Old title');

      provider.updateTask(taskId, 'New title');
      expect(provider.allTasks.first.title, 'New title');
    });

    test('updateTask throws on >250 chars', () {
      final taskId = _addTask('Test');

      expect(
        () => provider.updateTask(taskId, 'a' * 251),
        throwsA(isA<Exception>()),
      );
    });

    test('removeTask removes the task', () {
      final taskId = _addTask('Test');

      provider.removeTask(taskId);
      expect(provider.allTasks, isEmpty);
    });

    test('removeFolder removes folder and its tasks', () {
      provider.addFolder('Work');
      final folderId = provider.filteredFolders.first.id;
      _addTask('Task 1', folderId: folderId);
      _addTask('Task 2', folderId: folderId);

      provider.removeFolder(folderId);
      expect(provider.filteredFolders, isEmpty);
      expect(provider.allTasks, isEmpty);
    });

    test('clearAllTasks removes all tasks', () {
      _addTask('Task 1');
      _addTask('Task 2');
      provider.clearAllTasks();
      expect(provider.allTasks, isEmpty);
    });

    test('clearAllData removes everything', () {
      provider.addFolder('Work');
      _addTask('Task');
      provider.clearAllData();
      expect(provider.filteredFolders, isEmpty);
      expect(provider.allTasks, isEmpty);
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
      final taskId = _addTask('Test task');

      provider.moveTaskToFolder(taskId, folderId);
      final folderTasks = provider.getFolderTasks(folderId);
      expect(folderTasks.length, 1);
      expect(folderTasks[0].id, taskId);
    });
  });
}
