import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:asa/features/tasks/models/task_info_block.dart';
import 'package:asa/features/tasks/models/task_model.dart';
import 'package:asa/features/tasks/providers/task_provider.dart';
import 'package:asa/core/task_attachment_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('TaskProvider', () {
    late Directory documentsDirectory;

    late TaskProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      documentsDirectory = await Directory.systemTemp.createTemp(
        'asa-task-provider-test-',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async {
              if (call.method == 'getApplicationDocumentsDirectory') {
                return documentsDirectory.path;
              }
              return null;
            },
          );
      provider = TaskProvider();
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      if (await documentsDirectory.exists()) {
        await documentsDirectory.delete(recursive: true);
      }
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

    test('addTask calculates duration from a selected period', () {
      provider.addTask(
        'Timed task',
        startTime: DateTime(2025, 1, 1, 10, 0),
        endTime: DateTime(2025, 1, 1, 11, 0),
      );

      expect(provider.allTasks.single.expectedDuration, 60);
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

    test('timer persists elapsed time across stop and reset', () {
      final taskId = addTaskForTest('Timed task');
      final startedAt = DateTime(2025, 1, 1, 10, 0);
      final stoppedAt = startedAt.add(const Duration(minutes: 12, seconds: 30));

      provider.startTimer(taskId, startedAt: startedAt);
      expect(provider.isTimerRunning(taskId), true);
      expect(
        provider.elapsedForTask(taskId, now: stoppedAt),
        const Duration(minutes: 12, seconds: 30),
      );

      provider.stopTimer(taskId, stoppedAt: stoppedAt);
      expect(provider.isTimerRunning(taskId), false);
      expect(provider.allTasks.first.timerElapsedSeconds, 750);

      provider.resetTimer(taskId);
      expect(provider.elapsedForTask(taskId), Duration.zero);
      expect(provider.allTasks.first.timerElapsedSeconds, 0);
    });

    test('completing a running task stops and records its timer', () {
      final taskId = addTaskForTest('Complete timed task');
      final startedAt = DateTime.now().subtract(const Duration(minutes: 3));

      provider.startTimer(taskId, startedAt: startedAt);
      provider.toggleTask(taskId);

      final task = provider.allTasks.first;
      expect(task.isCompleted, true);
      expect(task.timerStartedAt, isNull);
      expect(task.timerElapsedSeconds, greaterThanOrEqualTo(180));
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

    test(
      'addTask persists information blocks and title updates preserve them',
      () async {
        await provider.ready;
        final block = TaskInfoBlock.quantity(
          id: 'water',
          targetValue: 3,
          unit: 'glasses',
        );
        provider.addTask('Drink water', infoBlocks: [block]);
        final taskId = provider.tasks.single.id;

        provider.updateTask(taskId, 'Drink more water');
        await provider.persist();

        expect(provider.tasks.single.infoBlocks.single.id, 'water');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('saved_tasks'), contains('water'));
      },
    );

    test('rejects new tasks with more than three quantity blocks', () {
      final blocks = List.generate(
        kMaxTaskQuantityBlocksPerTask + 1,
        (index) => TaskInfoBlock.quantity(
          id: 'quantity-$index',
          targetValue: 1,
          unit: 'times',
        ),
      );

      expect(
        () => provider.addTask('Too many quantities', infoBlocks: blocks),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects adding a fourth quantity block through an update', () {
      final taskId = addTaskForTest('Quantity task');
      final blocks = List.generate(
        kMaxTaskQuantityBlocksPerTask + 1,
        (index) => TaskInfoBlock.quantity(
          id: 'quantity-$index',
          targetValue: 1,
          unit: 'times',
        ),
      );

      expect(
        () => provider.updateTaskInfoBlocks(taskId, blocks),
        throwsA(isA<FormatException>()),
      );
      expect(provider.tasks.single.infoBlocks, isEmpty);
    });

    test('preserves legacy quantity blocks while rejecting new additions', () {
      final legacyBlocks = List.generate(
        kMaxTaskQuantityBlocksPerTask + 2,
        (index) => TaskInfoBlock.quantity(
          id: 'legacy-quantity-$index',
          targetValue: index + 1,
          unit: 'times',
        ),
      );
      provider.addTaskRaw(
        TaskItem(
          id: 'legacy-quantity-task',
          title: 'Legacy quantities',
          infoBlocks: legacyBlocks,
        ),
      );

      provider.updateTask('legacy-quantity-task', 'Renamed legacy task');
      provider.updateTaskInfoBlocks('legacy-quantity-task', [
        ...legacyBlocks.take(legacyBlocks.length - 1),
        legacyBlocks.last.copyWith(targetValue: 99),
      ]);

      expect(provider.tasks.single.infoBlocks, hasLength(legacyBlocks.length));
      expect(provider.tasks.single.infoBlocks.last.targetValue, 99);

      expect(
        () => provider.updateTaskInfoBlocks('legacy-quantity-task', [
          ...legacyBlocks.take(legacyBlocks.length - 1),
          legacyBlocks.last.copyWith(targetValue: 99),
          TaskInfoBlock.quantity(
            id: 'new-quantity',
            targetValue: 1,
            unit: 'times',
          ),
        ]),
        throwsA(isA<FormatException>()),
      );
      expect(provider.tasks.single.infoBlocks, hasLength(legacyBlocks.length));
    });

    test('completing a task fills every quantity block to its target', () {
      final blocks = [
        TaskInfoBlock.quantity(
          id: 'pages',
          currentValue: 3,
          targetValue: 10,
          unit: 'pages',
        ),
        TaskInfoBlock.quantity(
          id: 'minutes',
          currentValue: 5,
          targetValue: 25,
          unit: 'minutes',
        ),
      ];
      provider.addTask('Read and study', infoBlocks: blocks);
      final taskId = provider.tasks.single.id;

      provider.toggleTask(taskId);

      expect(provider.tasks.single.isCompleted, isTrue);
      expect(
        provider.tasks.single.infoBlocks.map((block) => block.currentValue),
        [10, 25],
      );
    });

    test(
      'adjustQuantityBlock clamps to target without completing the task',
      () {
        final block = TaskInfoBlock.quantity(
          id: 'pages',
          currentValue: 9,
          targetValue: 10,
          unit: 'pages',
        );
        provider.addTask('Read', infoBlocks: [block]);
        final taskId = provider.tasks.single.id;

        provider.adjustQuantityBlock(taskId, 'pages', 5);

        expect(provider.tasks.single.infoBlocks.single.currentValue, 10);
        expect(provider.tasks.single.isCompleted, isFalse);

        provider.adjustQuantityBlock(taskId, 'pages', -20);
        expect(provider.tasks.single.infoBlocks.single.currentValue, 0);
      },
    );

    test('rejects more than one description block per task', () {
      final blocks = [
        TaskInfoBlock.description(id: 'notes-1'),
        TaskInfoBlock.description(id: 'notes-2'),
      ];

      expect(
        () => provider.addTask('Two descriptions', infoBlocks: blocks),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects duplicate descriptions on update and raw add', () {
      final taskId = addTaskForTest('Existing task');
      final duplicateBlocks = [
        TaskInfoBlock.description(id: 'notes-1'),
        TaskInfoBlock.description(id: 'notes-2'),
      ];

      expect(
        () => provider.updateTask(
          taskId,
          'Existing task',
          infoBlocks: duplicateBlocks,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => provider.addTaskRaw(
          TaskItem(
            id: 'raw-duplicate',
            title: 'Raw',
            infoBlocks: duplicateBlocks,
          ),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(provider.tasks, hasLength(1));
    });

    test('upsertTask preserves imported quantity blocks above the limit', () {
      final importedBlocks = List.generate(
        kMaxTaskQuantityBlocksPerTask + 2,
        (index) => TaskInfoBlock.quantity(
          id: 'imported-quantity-$index',
          targetValue: index + 1,
          unit: 'times',
        ),
      );
      final importedTask = TaskItem(
        id: 'imported-quantity-task',
        title: 'Imported quantities',
        infoBlocks: importedBlocks,
      );

      expect(provider.upsertTask(importedTask), isTrue);
      expect(
        provider.tasks.single.infoBlocks,
        hasLength(importedBlocks.length),
      );
      expect(
        provider.tasks.single.infoBlocks.map((block) => block.id),
        importedBlocks.map((block) => block.id),
      );
    });

    test('upsertTask cannot add a fourth quantity block to a current task', () {
      final currentBlocks = List.generate(
        kMaxTaskQuantityBlocksPerTask,
        (index) => TaskInfoBlock.quantity(
          id: 'current-quantity-$index',
          targetValue: index + 1,
          unit: 'times',
        ),
      );
      provider.addTask('Current task', infoBlocks: currentBlocks);
      final currentId = provider.tasks.single.id;
      final incomingBlocks = [
        ...currentBlocks,
        TaskInfoBlock.quantity(
          id: 'incoming-quantity',
          targetValue: 1,
          unit: 'times',
        ),
      ];

      expect(
        () => provider.upsertTask(
          TaskItem(
            id: currentId,
            title: 'Synced task',
            infoBlocks: incomingBlocks,
            updatedAt: DateTime.now().add(const Duration(days: 1)),
          ),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(provider.tasks.single.title, 'Current task');
      expect(
        provider.tasks.single.infoBlocks,
        hasLength(kMaxTaskQuantityBlocksPerTask),
      );
    });

    test('normalizes duplicate descriptions on upsert', () {
      final duplicateTask = TaskItem(
        id: 'remote-duplicate',
        title: 'Remote task',
        infoBlocks: [
          TaskInfoBlock.description(id: 'notes-1', text: 'First'),
          TaskInfoBlock.description(id: 'notes-2', text: 'Second'),
        ],
      );

      expect(provider.upsertTask(duplicateTask), isTrue);
      expect(provider.tasks.single.infoBlocks, hasLength(1));
      expect(provider.tasks.single.infoBlocks.single.text, 'First\n\nSecond');
    });

    test('rejects more than the task-wide attachment limit across blocks', () {
      final attachments = List.generate(
        kMaxTaskAttachmentsPerTask,
        (index) => TaskAttachment(
          id: 'file-$index',
          type: TaskAttachmentType.file,
          name: 'file-$index.pdf',
          value: '/app/task_attachments/file-$index.pdf',
        ),
      );
      final blocks = [
        TaskInfoBlock.description(
          id: 'notes-1',
          attachments: attachments.sublist(0, 10),
        ),
        TaskInfoBlock.description(
          id: 'notes-2',
          attachments: attachments.sublist(10),
        ),
        TaskInfoBlock.description(
          id: 'notes-3',
          attachments: [attachments.first],
        ),
      ];

      expect(
        () => provider.addTask('Too many references', infoBlocks: blocks),
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

    test('clearAllTasks removes all local task attachments', () async {
      await provider.ready;
      final attachment = await storeTaskAttachment(
        type: TaskAttachmentType.file,
        name: 'task.pdf',
        bytes: const [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31],
        mimeType: 'application/pdf',
      );
      expect(attachment, isNotNull);
      final storedAttachment = attachment!;
      provider.addTask(
        'Task with attachment',
        infoBlocks: [
          TaskInfoBlock.description(
            attachments: [storedAttachment],
            id: 'notes',
          ),
        ],
      );

      await provider.clearAllTasks();

      expect(provider.tasks, isEmpty);
      expect(
        await readStoredTaskAttachmentBytes(storedAttachment.value),
        isNull,
      );
    });

    test('clearAllFolders removes attachments from folder tasks', () async {
      await provider.ready;
      provider.addFolder('Work');
      final folderId =
          provider.filteredFolders.firstWhere((f) => !f.isSystemStreak).id;
      final attachment = await storeTaskAttachment(
        type: TaskAttachmentType.file,
        name: 'folder-task.pdf',
        bytes: const [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31],
        mimeType: 'application/pdf',
      );
      expect(attachment, isNotNull);
      final storedAttachment = attachment!;
      provider.addTask(
        'Folder task',
        folderId: folderId,
        infoBlocks: [
          TaskInfoBlock.description(
            attachments: [storedAttachment],
            id: 'notes',
          ),
        ],
      );

      await provider.clearAllFolders();

      expect(provider.tasks, isEmpty);
      expect(
        await readStoredTaskAttachmentBytes(storedAttachment.value),
        isNull,
      );
    });

    test(
      'clearAllData removes local files, preserves links, and tolerates missing paths',
      () async {
        await provider.ready;
        final localAttachment = await storeTaskAttachment(
          type: TaskAttachmentType.file,
          name: 'private.pdf',
          bytes: const [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31],
          mimeType: 'application/pdf',
        );
        expect(localAttachment, isNotNull);
        final storedAttachment = localAttachment!;
        final orphan = File(
          '${documentsDirectory.path}${Platform.pathSeparator}task_attachments${Platform.pathSeparator}orphan.pdf',
        );
        await orphan.parent.create(recursive: true);
        await orphan.writeAsBytes(const [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31]);
        const link = TaskAttachment(
          id: 'link',
          type: TaskAttachmentType.link,
          name: 'ASA',
          value: 'https://example.com',
        );
        const missingFile = TaskAttachment(
          id: 'missing',
          type: TaskAttachmentType.file,
          name: 'missing.pdf',
          value: '/app/task_attachments/missing.pdf',
        );
        provider.addTask(
          'Task',
          infoBlocks: [
            TaskInfoBlock.description(
              id: 'notes',
              attachments: [storedAttachment, link, missingFile],
            ),
          ],
        );

        await provider.clearAllData();

        expect(
          provider.filteredFolders.where((folder) => !folder.isSystemStreak),
          isEmpty,
        );
        expect(
          provider.filteredFolders.where((folder) => folder.isSystemStreak),
          hasLength(1),
        );
        expect(provider.tasks, isEmpty);
        expect(
          await readStoredTaskAttachmentBytes(storedAttachment.value),
          isNull,
        );
        expect(await orphan.exists(), isFalse);
        final deletedTask = provider.allTasks.single;
        expect(
          deletedTask.infoBlocks.single.attachments.map((item) => item.type),
          [
            TaskAttachmentType.file,
            TaskAttachmentType.link,
            TaskAttachmentType.file,
          ],
        );
        expect(
          deletedTask.infoBlocks.single.attachments[1].value,
          'https://example.com',
        );
      },
    );

    test('setTaskTime calculates duration from the selected period', () {
      final taskId = addTaskForTest('Time task');
      final start = DateTime(2025, 1, 1, 16, 0);
      final end = DateTime(2025, 1, 1, 17, 0);

      provider.setTaskTime(taskId, startTime: start, endTime: end);

      final task = provider.tasks.first;
      expect(task.startTime?.isAtSameMomentAs(start), true);
      expect(task.endTime?.isAtSameMomentAs(end), true);
      expect(task.expectedDuration, 60);
      expect(task.effectiveDurationMinutes, 60);
    });

    test('setTaskTime calculates overnight duration', () {
      final taskId = addTaskForTest('Night task');
      provider.setTaskTime(
        taskId,
        startTime: DateTime(2025, 1, 1, 23, 30),
        endTime: DateTime(2025, 1, 1, 1, 0),
      );

      expect(provider.tasks.first.expectedDuration, 90);
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

    test(
      'search and filters compose across active and completed tasks',
      () async {
        await provider.ready;
        provider.addFolder('Work Projects');
        provider.addFolder('Personal');
        addTaskForTest('Write report');
        final completedId = addTaskForTest('Read book');
        provider.toggleTask(completedId);

        provider.setSearchQuery('report');
        expect(provider.filteredInProgressTasks.map((task) => task.title), [
          'Write report',
        ]);
        expect(provider.filteredCompletedTasks, isEmpty);

        provider.setSearchQuery('');
        provider.setFilter(TaskFilter.completed);
        expect(provider.filteredInProgressTasks, isEmpty);
        expect(provider.filteredCompletedTasks.map((task) => task.title), [
          'Read book',
        ]);

        provider.setFilter(TaskFilter.active);
        expect(provider.filteredCompletedTasks, isEmpty);
        expect(provider.filteredInProgressTasks.map((task) => task.title), [
          'Write report',
        ]);

        provider.setFilter(TaskFilter.foldersOnly);
        expect(provider.filteredInProgressTasks, isEmpty);
        expect(provider.filteredCompletedTasks, isEmpty);
        expect(
          provider.filteredFolders.any(
            (folder) => folder.name == 'Work Projects',
          ),
          isTrue,
        );

        provider.setSearchQuery('work');
        expect(provider.filteredFolders.map((folder) => folder.name), [
          'Work Projects',
        ]);
      },
    );

    test(
      'reorders root folders while keeping the streak folder first',
      () async {
        await provider.ready;
        provider.addFolder('First');
        provider.addFolder('Second');
        provider.addFolder('Third');

        final before =
            provider.filteredFolders
                .where((folder) => !folder.isSystemStreak)
                .map((folder) => folder.id)
                .toList();
        final firstVisibleIndex = provider.filteredFolders.indexWhere(
          (folder) => folder.id == before.first,
        );
        final secondVisibleIndex = provider.filteredFolders.indexWhere(
          (folder) => folder.id == before[1],
        );

        provider.reorderRootFolders(firstVisibleIndex, secondVisibleIndex);

        expect(
          provider.filteredFolders
              .where((folder) => !folder.isSystemStreak)
              .map((folder) => folder.id),
          [before[1], before[0], before[2]],
        );
        expect(provider.filteredFolders.first.isSystemStreak, isTrue);
      },
    );

    test('reorders subfolders under the same parent', () {
      provider.addFolder('Parent');
      final parentId =
          provider.folders.firstWhere((f) => f.name == 'Parent').id;
      provider.addFolder('First child', parentFolderId: parentId);
      provider.addFolder('Second child', parentFolderId: parentId);
      final before = provider.getSubfolders(parentId).map((f) => f.id).toList();

      provider.reorderSubfolders(parentId, 0, 1);

      expect(provider.getSubfolders(parentId).map((folder) => folder.id), [
        before[1],
        before[0],
      ]);
    });

    test(
      'reorders tasks in a folder and accepts an explicit ordered id list',
      () {
        provider.addFolder('Reading');
        final folderId =
            provider.folders.firstWhere((f) => f.name == 'Reading').id;
        provider.addTask('First task', folderId: folderId);
        provider.addTask('Second task', folderId: folderId);
        provider.addTask('Third task', folderId: folderId);
        final before =
            provider.getFolderTasks(folderId).map((task) => task.id).toList();

        provider.reorderFolderTasks(folderId, 0, 2);
        expect(provider.getFolderTasks(folderId).map((task) => task.id), [
          before[1],
          before[2],
          before[0],
        ]);

        provider.reorderFolderTasks(
          folderId,
          0,
          0,
          orderedTaskIds: [before[0], before[2], before[1]],
        );
        expect(provider.getFolderTasks(folderId).map((task) => task.id), [
          before[0],
          before[2],
          before[1],
        ]);
      },
    );

    test(
      'invalid reorder operations leave task and folder order unchanged',
      () async {
        await provider.ready;
        provider.addFolder('First');
        provider.addFolder('Second');
        final folderIdsBefore =
            provider.filteredFolders.map((folder) => folder.id).toList();
        final userFolderId =
            provider.filteredFolders
                .firstWhere((folder) => !folder.isSystemStreak)
                .id;
        provider.addTask('First task', folderId: userFolderId);
        provider.addTask('Second task', folderId: userFolderId);
        final taskIdsBefore =
            provider
                .getFolderTasks(userFolderId)
                .map((task) => task.id)
                .toList();

        provider.reorderRootFolders(-1, 0);
        provider.reorderRootFolders(0, 999);
        provider.reorderFolderTasks(userFolderId, -1, 0);
        provider.reorderFolderTasks(userFolderId, 0, 999);

        expect(
          provider.filteredFolders.map((folder) => folder.id).toList(),
          folderIdsBefore,
        );
        expect(
          provider.getFolderTasks(userFolderId).map((task) => task.id).toList(),
          taskIdsBefore,
        );
      },
    );

    test('moveTaskToFolder moves task between folders', () {
      provider.addFolder('Work');
      final folderId = provider.filteredFolders.first.id;
      final taskId = addTaskForTest('Test task');

      final moved = provider.moveTaskToFolder(taskId, folderId);
      final folderTasks = provider.getFolderTasks(folderId);
      expect(moved, true);
      expect(folderTasks.length, 1);
      expect(folderTasks[0].id, taskId);
    });

    test('moveTaskToFolder rejects moving a task into the streak folder', () {
      final taskId = addTaskForTest('Task for streak');

      final moved = provider.moveTaskToFolder(taskId, 'system_streak_folder');

      expect(moved, false);
      expect(provider.allTasks.single.folderId, isNot('system_streak_folder'));
    });

    test('moveTaskToFolder rejects moving a task to the root', () {
      final taskId = addTaskForTest('Task for root');

      final moved = provider.moveTaskToFolder(taskId, null);

      expect(moved, false);
      expect(provider.allTasks.single.folderId, isNull);
    });

    test('moveTaskToFolder reports false for an unknown task', () {
      expect(provider.moveTaskToFolder('missing-task', null), false);
    });

    test('moveTaskToParentFolder moves a nested task one level up', () {
      provider.addFolder('Parent');
      final parentId =
          provider.folders.firstWhere((f) => f.name == 'Parent').id;
      provider.addFolder('Child', parentFolderId: parentId);
      final childId = provider.folders.firstWhere((f) => f.name == 'Child').id;
      final taskId = addTaskForTest('Nested task', folderId: childId);

      provider.moveTaskToParentFolder(taskId);

      expect(provider.allTasks.first.folderId, parentId);
      expect(provider.getFolderTasks(childId), isEmpty);
      expect(provider.getFolderTasks(parentId).single.id, taskId);
    });

    test(
      'moveTaskToParentFolder rejects moving a root-folder task to the root',
      () {
        provider.addFolder('Root folder');
        final folderId =
            provider.folders.firstWhere((f) => f.name == 'Root folder').id;
        final taskId = addTaskForTest(
          'Task in root folder',
          folderId: folderId,
        );

        final moved = provider.moveTaskToParentFolder(taskId);

        expect(moved, false);
        expect(provider.allTasks.first.folderId, folderId);
      },
    );

    test('canMoveTaskToParent reflects where a task would land', () {
      provider.addFolder('Root folder');
      final rootFolderId =
          provider.folders.firstWhere((f) => f.name == 'Root folder').id;
      provider.addFolder('Child', parentFolderId: rootFolderId);
      final childId = provider.folders.firstWhere((f) => f.name == 'Child').id;
      final nestedTaskId = addTaskForTest('Nested', folderId: childId);
      final rootFolderTaskId = addTaskForTest(
        'In root folder',
        folderId: rootFolderId,
      );
      final rootTaskId = addTaskForTest('At root');

      expect(provider.canMoveTaskToParent(nestedTaskId), isTrue);
      expect(provider.canMoveTaskToParent(rootFolderTaskId), isFalse);
      expect(provider.canMoveTaskToParent(rootTaskId), isFalse);
      expect(provider.canMoveTaskToParent('missing'), isFalse);
    });

    test('moveFolderToParentFolder moves a nested folder one level up', () {
      provider.addFolder('Grandparent');
      final grandparentId =
          provider.folders.firstWhere((f) => f.name == 'Grandparent').id;
      provider.addFolder('Parent', parentFolderId: grandparentId);
      final parentId =
          provider.folders.firstWhere((f) => f.name == 'Parent').id;
      provider.addFolder('Child', parentFolderId: parentId);
      final childId = provider.folders.firstWhere((f) => f.name == 'Child').id;

      provider.moveFolderToParentFolder(childId);

      expect(
        provider.folders.firstWhere((f) => f.id == childId).parentFolderId,
        grandparentId,
      );
    });

    test('move-back operations leave root tasks and folders unchanged', () {
      provider.addFolder('Root folder');
      final folderId =
          provider.folders.firstWhere((f) => f.name == 'Root folder').id;
      final taskId = addTaskForTest('Root task');

      provider.moveTaskToParentFolder(taskId);
      provider.moveFolderToParentFolder(folderId);

      expect(provider.allTasks.first.folderId, isNull);
      expect(
        provider.folders.firstWhere((f) => f.id == folderId).parentFolderId,
        isNull,
      );
    });

    test('moveFolderToFolder rejects moving a folder into its descendant', () {
      provider.addFolder('Parent');
      final parentId = provider.filteredFolders.first.id;
      provider.addFolder('Child', parentFolderId: parentId);
      final childId = provider.getSubfolders(parentId).first.id;

      final moved = provider.moveFolderToFolder(parentId, childId);

      expect(moved, false);
      expect(
        provider.folders.firstWhere((f) => f.id == parentId).parentFolderId,
        null,
      );
      expect(
        provider.folders.firstWhere((f) => f.id == childId).parentFolderId,
        parentId,
      );
    });

    test('moveFolderToFolder reports false for a missing target parent', () {
      provider.addFolder('Parent');
      final parentId = provider.filteredFolders.first.id;

      expect(provider.moveFolderToFolder(parentId, 'missing'), false);
      expect(provider.folders.first.parentFolderId, null);
    });

    test('moveFolderToFolder reports false for a self move', () {
      provider.addFolder('Solo');
      final folderId = provider.filteredFolders.first.id;

      expect(provider.moveFolderToFolder(folderId, folderId), false);
    });

    test('user folders cannot be placed inside the streak folder', () {
      provider.addFolder('Root');
      final rootId = provider.filteredFolders.first.id;

      provider.addFolder(
        'Invalid child',
        parentFolderId: 'system_streak_folder',
      );
      final moved = provider.moveFolderToFolder(rootId, 'system_streak_folder');

      expect(moved, false);
      expect(provider.folders.where((f) => f.name == 'Invalid child'), isEmpty);
      expect(
        provider.folders.firstWhere((f) => f.id == rootId).parentFolderId,
        null,
      );
    });

    test('raw and upsert folder paths reject reserved streak records', () {
      provider.addFolderRaw(
        FolderItem(id: 'system_streak_folder', name: 'Fake streak'),
      );
      provider.addFolderRaw(
        FolderItem(
          id: 'raw-system',
          name: 'System-shaped',
          isSystemStreak: true,
        ),
      );
      provider.addFolderRaw(
        FolderItem(
          id: 'raw-child',
          name: 'Child of streak',
          parentFolderId: 'system_streak_folder',
        ),
      );

      expect(
        provider.upsertFolder(
          FolderItem(id: 'system_streak_folder', name: 'Fake streak'),
        ),
        false,
      );
      expect(
        provider.upsertFolder(
          FolderItem(
            id: 'upsert-system',
            name: 'System-shaped',
            isSystemStreak: true,
          ),
        ),
        false,
      );
      expect(
        provider.upsertFolder(
          FolderItem(
            id: 'upsert-child',
            name: 'Child of streak',
            parentFolderId: 'system_streak_folder',
          ),
        ),
        false,
      );
      expect(
        provider.folders.where((folder) => folder.id.startsWith('raw-')),
        isEmpty,
      );
    });

    test('skips malformed persisted tasks and preserves valid ones', () async {
      final validTask = TaskItem(id: 'valid-task', title: 'Valid task');
      SharedPreferences.setMockInitialValues({
        'saved_tasks': jsonEncode([
          validTask.toJson(),
          {'id': 'broken-task'},
        ]),
      });

      final restored = TaskProvider();
      await restored.ready;

      expect(restored.allTasks.map((task) => task.id), contains('valid-task'));
      expect(
        restored.allTasks.where((task) => task.id == 'broken-task'),
        isEmpty,
      );
    });

    test('merges duplicate descriptions when loading legacy data', () async {
      final firstAttachment = const TaskAttachment(
        id: 'first-file',
        type: TaskAttachmentType.file,
        name: 'first.pdf',
        value: '/app/task_attachments/first.pdf',
      );
      final secondAttachment = const TaskAttachment(
        id: 'second-file',
        type: TaskAttachmentType.file,
        name: 'second.pdf',
        value: '/app/task_attachments/second.pdf',
      );
      final legacyTask = TaskItem(
        id: 'legacy-duplicate',
        title: 'Legacy task',
        infoBlocks: [
          TaskInfoBlock.description(
            id: 'notes-1',
            text: 'First',
            attachments: [firstAttachment],
          ),
          TaskInfoBlock.quantity(id: 'pages', targetValue: 10, unit: 'pages'),
          TaskInfoBlock.description(
            id: 'notes-2',
            text: 'Second',
            attachments: [secondAttachment],
          ),
        ],
      );
      SharedPreferences.setMockInitialValues({
        'saved_tasks': jsonEncode([legacyTask.toJson()]),
      });

      final restored = TaskProvider();
      await restored.ready;

      expect(restored.tasks.single.infoBlocks, hasLength(2));
      expect(
        restored.tasks.single.infoBlocks.first.type,
        TaskInfoBlockType.description,
      );
      expect(restored.tasks.single.infoBlocks.first.text, 'First\n\nSecond');
      expect(
        restored.tasks.single.infoBlocks.first.attachments.map(
          (item) => item.id,
        ),
        ['first-file', 'second-file'],
      );
      expect(
        restored.tasks.single.infoBlocks.last.type,
        TaskInfoBlockType.quantity,
      );
    });

    test('skips persisted tasks over the total attachment limit', () async {
      final attachments = List.generate(
        kMaxTaskAttachmentsPerTask,
        (index) => TaskAttachment(
          id: 'stored-$index',
          type: TaskAttachmentType.file,
          name: 'stored-$index.pdf',
          value: '/app/task_attachments/stored-$index.pdf',
        ),
      );
      final oversizedTask = TaskItem(
        id: 'oversized-task',
        title: 'Oversized task',
        infoBlocks: [
          TaskInfoBlock.description(id: 'notes-1', attachments: attachments),
          TaskInfoBlock.description(
            id: 'notes-2',
            attachments: [attachments.first],
          ),
        ],
      );
      SharedPreferences.setMockInitialValues({
        'saved_tasks': jsonEncode([oversizedTask.toJson()]),
      });

      final restored = TaskProvider();
      await restored.ready;

      expect(restored.allTasks, hasLength(1));
      expect(
        restored.allTasks.single.infoBlocks
            .expand((block) => block.attachments)
            .length,
        kMaxTaskAttachmentsPerTask,
      );
    });

    test(
      'loading persisted streak corruption restores user folders to root',
      () async {
        final persistedFolder = FolderItem(
          id: 'user-child',
          name: 'Recovered folder',
          parentFolderId: 'system_streak_folder',
        );
        final persistedStreak = FolderItem(
          id: 'system_streak_folder',
          name: 'Fake streak',
          isSystemStreak: true,
        );
        SharedPreferences.setMockInitialValues({
          'saved_folders':
              '[${jsonEncode(persistedFolder.toJson())},${jsonEncode(persistedStreak.toJson())},{"id":"broken","name":42}]',
        });

        final restored = TaskProvider();
        await restored.ready;

        final recovered = restored.folders.firstWhere(
          (folder) => folder.id == 'user-child',
        );
        expect(recovered.parentFolderId, isNull);
        expect(
          restored.folders.where(
            (folder) => folder.id == 'system_streak_folder',
          ),
          hasLength(1),
        );
        expect(
          restored.folders.where((folder) => folder.name == 'Fake streak'),
          isEmpty,
        );
      },
    );

    test('clearAllFolders soft-deletes folders and their tasks', () async {
      provider.addFolder('Work');
      final folderId = provider.filteredFolders.first.id;
      final taskId = addTaskForTest('Task', folderId: folderId);

      await provider.clearAllFolders();

      expect(provider.folders, isEmpty);
      expect(provider.tasks, isEmpty);
      expect(
        provider.allTasks.firstWhere((t) => t.id == taskId).isDeleted,
        true,
      );
      expect(
        provider.allTasks.firstWhere((t) => t.id == taskId).folderId,
        folderId,
      );
    });

    test('serializes the latest task state to preferences', () async {
      provider.addTask('First');
      provider.addTask('Second');

      await provider.ready;
      await provider.persist();
      final prefs = await SharedPreferences.getInstance();
      final savedTasks = prefs.getString('saved_tasks');

      expect(savedTasks, isNotNull);
      expect(savedTasks, contains('First'));
      expect(savedTasks, contains('Second'));
    });

    test('coalesces rapid mutations into one persistence write', () async {
      await provider.ready;
      provider.addTask('First');
      provider.addTask('Second');

      await provider.flushPersistence();

      expect(provider.persistenceWriteCount, 1);
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('saved_tasks');
      expect(saved, contains('First'));
      expect(saved, contains('Second'));
    });

    test('concurrent flush calls share one persistence write', () async {
      await provider.ready;
      provider.addTask('Concurrent flush');

      final firstFlush = provider.flushPersistence();
      final secondFlush = provider.flushPersistence();
      await Future.wait([firstFlush, secondFlush]);

      expect(provider.persistenceWriteCount, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('saved_tasks'), contains('Concurrent flush'));
    });

    test(
      'mutation after a completed flush is persisted by the next flush',
      () async {
        await provider.ready;
        provider.addTask('Before flush');
        await provider.flushPersistence();

        provider.addTask('After flush');
        await provider.flushPersistence();

        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString('saved_tasks');
        expect(saved, contains('Before flush'));
        expect(saved, contains('After flush'));
        expect(provider.persistenceWriteCount, 2);
      },
    );

    test(
      'does not overwrite loaded tasks when mutated before initialization',
      () async {
        final existing =
            TaskItem(id: 'existing', title: 'Loaded task').toJson();
        SharedPreferences.setMockInitialValues({
          'saved_tasks': jsonEncode([existing]),
        });

        final restored = TaskProvider();
        restored.addTask('Added during startup');
        await restored.ready;
        await restored.persist();

        expect(
          restored.allTasks.map((task) => task.title),
          containsAll(<String>['Loaded task', 'Added during startup']),
        );
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString('saved_tasks');
        expect(saved, contains('Loaded task'));
        expect(saved, contains('Added during startup'));
      },
    );

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
        final newer = TaskItem(
          id: id,
          title: 'Newer',
          updatedAt: DateTime.now().add(const Duration(days: 1)),
        );

        final changed = provider.upsertTask(newer);

        expect(changed, true);
        expect(provider.tasks.first.title, 'Newer');
      });

      test('upsertTask keeps newer local task', () {
        provider.addTask('Local');
        final id = provider.tasks.first.id;
        final older = TaskItem(
          id: id,
          title: 'Older',
          updatedAt: DateTime.now().subtract(const Duration(days: 1)),
        );

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
        final newer = FolderItem(
          id: id,
          name: 'Newer',
          updatedAt: DateTime.now().add(const Duration(days: 1)),
        );

        final changed = provider.upsertFolder(newer);

        expect(changed, true);
        expect(provider.folders.first.name, 'Newer');
      });

      test('upsertFolder breaks an incoming hierarchy cycle at the root', () {
        provider.addFolder('Parent');
        final parentId =
            provider.folders.firstWhere((f) => f.name == 'Parent').id;
        provider.addFolder('Child', parentFolderId: parentId);
        final childId =
            provider.folders.firstWhere((f) => f.name == 'Child').id;

        final changed = provider.upsertFolder(
          FolderItem(
            id: parentId,
            name: 'Parent from remote',
            parentFolderId: childId,
            updatedAt: DateTime.now().add(const Duration(days: 1)),
          ),
        );

        expect(changed, true);
        expect(
          provider.folders.firstWhere((f) => f.id == parentId).parentFolderId,
          isNull,
        );
      });
    });

    group('soft-delete retention purge', () {
      test(
        'purges deleted tasks and folders older than the retention period',
        () async {
          final oldDeletedTask = TaskItem(
            id: 'old-deleted-task',
            title: 'Old deleted task',
            isDeleted: true,
            updatedAt: DateTime.now().subtract(const Duration(days: 30)),
          );
          final recentDeletedTask = TaskItem(
            id: 'recent-deleted-task',
            title: 'Recent deleted task',
            isDeleted: true,
            updatedAt: DateTime.now().subtract(const Duration(days: 2)),
          );
          final activeTask = TaskItem(
            id: 'active-task',
            title: 'Active task',
            updatedAt: DateTime.now().subtract(const Duration(days: 30)),
          );
          final oldDeletedFolder = FolderItem(
            id: 'old-deleted-folder',
            name: 'Old deleted folder',
            isDeleted: true,
            updatedAt: DateTime.now().subtract(const Duration(days: 30)),
          );
          final recentDeletedFolder = FolderItem(
            id: 'recent-deleted-folder',
            name: 'Recent deleted folder',
            isDeleted: true,
            updatedAt: DateTime.now().subtract(const Duration(days: 2)),
          );
          SharedPreferences.setMockInitialValues({
            'saved_tasks': jsonEncode([
              oldDeletedTask.toJson(),
              recentDeletedTask.toJson(),
              activeTask.toJson(),
            ]),
            'saved_folders': jsonEncode([
              oldDeletedFolder.toJson(),
              recentDeletedFolder.toJson(),
            ]),
          });

          final restored = TaskProvider();
          await restored.ready;
          await restored.persist();

          expect(
            restored.allTasks.map((task) => task.id),
            isNot(contains('old-deleted-task')),
          );
          expect(
            restored.allTasks.map((task) => task.id),
            containsAll(<String>['recent-deleted-task', 'active-task']),
          );
          expect(
            restored.folders.map((folder) => folder.id),
            isNot(contains('old-deleted-folder')),
          );
          // The app-owned streak folder is recreated at startup and survives.
          expect(
            restored.folders.any(
              (folder) => folder.id == 'system_streak_folder',
            ),
            isTrue,
          );

          final prefs = await SharedPreferences.getInstance();
          expect(
            prefs.getString('saved_tasks'),
            isNot(contains('old-deleted-task')),
          );
          expect(
            prefs.getString('saved_folders'),
            contains('recent-deleted-folder'),
          );
          expect(
            prefs.getString('saved_folders'),
            isNot(contains('old-deleted-folder')),
          );
        },
      );

      test('keeps deleted tasks still inside the retention period', () async {
        final recentDeletedTask = TaskItem(
          id: 'recent-deleted-task',
          title: 'Recent deleted task',
          isDeleted: true,
          updatedAt: DateTime.now().subtract(const Duration(days: 6)),
        );
        SharedPreferences.setMockInitialValues({
          'saved_tasks': jsonEncode([recentDeletedTask.toJson()]),
        });

        final restored = TaskProvider();
        await restored.ready;
        await restored.persist();

        expect(
          restored.allTasks.map((task) => task.id),
          contains('recent-deleted-task'),
        );
      });

      test('purges old deleted items merged during import or sync', () async {
        await provider.ready;
        final oldDeleted = TaskItem(
          id: 'synced-old-deleted',
          title: 'Synced old deleted',
          isDeleted: true,
          updatedAt: DateTime.now().subtract(const Duration(days: 30)),
        );
        final freshDeleted = TaskItem(
          id: 'synced-fresh-deleted',
          title: 'Synced fresh deleted',
          isDeleted: true,
          updatedAt: DateTime.now().subtract(const Duration(days: 1)),
        );

        provider.addTaskRaw(oldDeleted);
        provider.addTaskRaw(freshDeleted);
        await provider.persist();

        expect(
          provider.allTasks.map((task) => task.id),
          contains('synced-fresh-deleted'),
        );
        expect(
          provider.allTasks.map((task) => task.id),
          isNot(contains('synced-old-deleted')),
        );
      });

      test('deletes attachment files of purged tasks', () async {
        await provider.ready;
        final attachment = await storeTaskAttachment(
          type: TaskAttachmentType.file,
          name: 'purged.pdf',
          bytes: const [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31],
          mimeType: 'application/pdf',
        );
        expect(attachment, isNotNull);
        final storedAttachment = attachment!;
        provider.addTaskRaw(
          TaskItem(
            id: 'purged-with-attachment',
            title: 'Purged attachment',
            isDeleted: true,
            updatedAt: DateTime.now().subtract(const Duration(days: 30)),
            infoBlocks: [
              TaskInfoBlock.description(
                id: 'notes',
                attachments: [storedAttachment],
              ),
            ],
          ),
        );

        await provider.persist();

        expect(
          provider.allTasks.map((task) => task.id),
          isNot(contains('purged-with-attachment')),
        );
        expect(
          await readStoredTaskAttachmentBytes(storedAttachment.value),
          isNull,
        );
      });

      test(
        'stale widget completion does not reset the retention clock',
        () async {
          await provider.ready;
          final oldDeleted = TaskItem(
            id: 'widget-deleted',
            title: 'Widget deleted',
            isDeleted: true,
            updatedAt: DateTime.now().subtract(const Duration(days: 30)),
          );
          provider.addTaskRaw(oldDeleted);

          // A stale background widget callback must not bump `updatedAt` on a
          // soft-deleted task, otherwise it would keep the record alive.
          provider.completeTaskFromWidget('widget-deleted');
          await provider.persist();

          expect(provider.allTasks, isEmpty);
        },
      );
    });
  });
}
