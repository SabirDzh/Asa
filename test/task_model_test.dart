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
