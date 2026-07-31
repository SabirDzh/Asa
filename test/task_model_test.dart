import 'package:flutter_test/flutter_test.dart';
import 'package:asa/features/tasks/models/task_info_block.dart';
import 'package:asa/features/tasks/models/task_model.dart';

void main() {
  group('TaskItem', () {
    test('toJson / fromJson round-trip', () {
      final task = TaskItem(
        id: '1',
        title: 'Test task',
        isCompleted: true,
        folderId: 'f1',
      );
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
        timerStartedAt: DateTime(2025, 1, 1, 16, 5),
        timerElapsedSeconds: 30,
      );
      final restored = TaskItem.fromJson(task.toJson());
      expect(restored.expectedDuration, 90);
      expect(restored.startTime?.isAtSameMomentAs(start), true);
      expect(restored.endTime?.isAtSameMomentAs(end), true);
      expect(
        restored.timerStartedAt?.isAtSameMomentAs(DateTime(2025, 1, 1, 16, 5)),
        true,
      );
      expect(restored.timerElapsedSeconds, 30);
    });

    test('calculates period duration and supports overnight periods', () {
      final daytimeStart = DateTime(2025, 1, 1, 10, 0);
      final daytimeEnd = DateTime(2025, 1, 1, 11, 0);
      expect(TaskItem.durationForPeriod(daytimeStart, daytimeEnd), 60);

      final overnightStart = DateTime(2025, 1, 1, 23, 30);
      final overnightEnd = DateTime(2025, 1, 1, 1, 0);
      expect(TaskItem.durationForPeriod(overnightStart, overnightEnd), 90);
      expect(TaskItem.durationForPeriod(daytimeStart, daytimeStart), isNull);
    });

    test('keeps legacy duration when a task has no period', () {
      final task = TaskItem(
        id: '1',
        title: 'Legacy task',
        expectedDuration: 45,
      );
      expect(task.effectiveDurationMinutes, 45);
    });

    test('round-trips quantity and description blocks', () {
      final task = TaskItem(
        id: '1',
        title: 'Read a book',
        infoBlocks: [
          TaskInfoBlock.quantity(
            id: 'pages',
            label: 'Pages',
            currentValue: 12,
            targetValue: 120,
            unit: 'pages',
          ),
          TaskInfoBlock.description(
            id: 'notes',
            text: 'Read chapter 1',
            attachments: [
              const TaskAttachment(
                id: 'link-1',
                type: TaskAttachmentType.link,
                name: 'Source',
                value: 'https://example.com/book',
              ),
            ],
          ),
        ],
      );

      final restored = TaskItem.fromJson(task.toJson());
      expect(restored.infoBlocks, hasLength(2));
      expect(restored.infoBlocks.first.targetValue, 120);
      expect(
        restored.infoBlocks.last.attachments.single.value,
        'https://example.com/book',
      );
    });

    test('old task JSON defaults missing infoBlocks to an empty list', () {
      final task = TaskItem.fromJson({'id': 'legacy', 'title': 'Old task'});
      expect(task.infoBlocks, isEmpty);
    });

    test(
      'malformed information blocks are skipped without losing valid blocks',
      () {
        final task = TaskItem.fromJson({
          'id': 'mixed',
          'title': 'Mixed task',
          'infoBlocks': [
            {'id': 'valid', 'type': 'description', 'text': 'Keep me'},
            {'id': 'broken', 'type': 'unknown'},
          ],
        });
        expect(task.infoBlocks.map((block) => block.id), ['valid']);
      },
    );

    test('skips malformed attachments without losing valid descriptions', () {
      final task = TaskItem.fromJson({
        'id': 'attachments',
        'title': 'Attachment task',
        'infoBlocks': [
          {
            'id': 'notes',
            'type': 'description',
            'text': 'Keep this description',
            'attachments': [
              {1: 'not a valid attachment'},
              {
                'id': 'valid-link',
                'type': 'link',
                'name': 'Source',
                'value': 'https://example.com',
              },
            ],
          },
        ],
      });

      expect(task.infoBlocks.single.text, 'Keep this description');
      expect(task.infoBlocks.single.attachments.single.id, 'valid-link');
    });

    test('retains all decoded attachments for provider normalization', () {
      final attachments = List.generate(
        kMaxTaskAttachmentsPerTask + 1,
        (index) => {
          'id': 'file-$index',
          'type': 'file',
          'name': 'file-$index.pdf',
          'value': '/app/task_attachments/file-$index.pdf',
        },
      );
      final block = TaskInfoBlock.fromJson({
        'id': 'notes',
        'type': 'description',
        'attachments': attachments,
      });

      expect(block.attachments, hasLength(kMaxTaskAttachmentsPerTask + 1));
    });

    test('rejects invalid quantities and unsafe links', () {
      expect(
        () => TaskInfoBlock.quantity(
          id: 'invalid',
          currentValue: 2,
          targetValue: 1,
          unit: 'pages',
        ),
        throwsFormatException,
      );
      expect(
        () => TaskAttachment.fromJson({
          'id': 'unsafe',
          'type': 'link',
          'name': 'Unsafe',
          'value': 'javascript:alert(1)',
        }),
        throwsFormatException,
      );
    });
  });

  group('FolderItem', () {
    test('toJson / fromJson round-trip', () {
      final folder = FolderItem(
        id: 'f1',
        name: 'Work',
        isSystemStreak: false,
        parentFolderId: null,
        iconAsset: 'assets/icons/work.svg',
      );
      final json = folder.toJson();
      final restored = FolderItem.fromJson(json);
      expect(restored.id, 'f1');
      expect(restored.name, 'Work');
      expect(restored.isSystemStreak, false);
      expect(restored.parentFolderId, null);
      expect(restored.iconAsset, 'assets/icons/work.svg');
    });

    test('copyWith preserves unchanged fields', () {
      final folder = FolderItem(id: 'f1', name: 'Work');
      final copy = folder.copyWith(
        name: 'Personal',
        iconAsset: 'assets/icons/study.svg',
      );
      expect(copy.id, 'f1');
      expect(copy.name, 'Personal');
      expect(copy.isSystemStreak, false);
      expect(copy.iconAsset, 'assets/icons/study.svg');
    });
  });
}
