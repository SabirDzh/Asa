import 'package:flutter_test/flutter_test.dart';
import 'package:asa/features/tasks/models/task_model.dart';

void main() {
  group('TaskItem', () {
    test('toJson / fromJson round-trip', () {
      final task = TaskItem(id: '1', title: 'Test task', isCompleted: true, folderId: 'f1');
      final json = task.toJson();
      final restored = TaskItem.fromJson(json);
      expect(restored.id, '1');
      expect(restored.title, 'Test task');
      expect(restored.isCompleted, true);
      expect(restored.folderId, 'f1');
    });

    test('copyWith preserves unchanged fields', () {
      final task = TaskItem(id: '1', title: 'Original');
      final copy = task.copyWith(title: 'Updated');
      expect(copy.id, '1');
      expect(copy.title, 'Updated');
      expect(copy.isCompleted, false);
    });

    test('fromJson handles missing folderId', () {
      final restored = TaskItem.fromJson({'id': '1', 'title': 'No folder'});
      expect(restored.folderId, null);
    });

    test('toJson / fromJson preserves time fields', () {
      final start = DateTime(2025, 1, 1, 16, 0);
      final end = DateTime(2025, 1, 1, 17, 0);
      final task = TaskItem(
        id: '1',
        title: 'Time task',
        expectedDuration: 90,
        startTime: start,
        endTime: end,
      );
      final restored = TaskItem.fromJson(task.toJson());
      expect(restored.expectedDuration, 90);
      expect(restored.startTime?.isAtSameMomentAs(start), true);
      expect(restored.endTime?.isAtSameMomentAs(end), true);
    });

    test('copyWith updates time fields', () {
      final task = TaskItem(id: '1', title: 'Task');
      final start = DateTime(2025, 1, 1, 10, 0);
      final updated = task.copyWith(startTime: start, expectedDuration: 60);
      expect(updated.startTime?.isAtSameMomentAs(start), true);
      expect(updated.expectedDuration, 60);
    });
  });

  group('FolderItem', () {
    test('toJson / fromJson round-trip', () {
      final folder = FolderItem(id: 'f1', name: 'Work', isSystemStreak: false, parentFolderId: null);
      final json = folder.toJson();
      final restored = FolderItem.fromJson(json);
      expect(restored.id, 'f1');
      expect(restored.name, 'Work');
      expect(restored.isSystemStreak, false);
      expect(restored.parentFolderId, null);
    });

    test('copyWith preserves unchanged fields', () {
      final folder = FolderItem(id: 'f1', name: 'Work');
      final copy = folder.copyWith(name: 'Personal');
      expect(copy.id, 'f1');
      expect(copy.name, 'Personal');
      expect(copy.isSystemStreak, false);
    });
  });
}
