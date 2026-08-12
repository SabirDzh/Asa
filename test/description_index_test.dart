import 'package:flutter_test/flutter_test.dart';

import 'package:asa/features/tasks/models/task_info_block.dart';
import 'package:asa/features/tasks/models/task_model.dart';
import 'package:asa/features/tasks/services/description_index.dart';

void main() {
  late DescriptionIndex index;
  late TaskItem readBook;
  late TaskItem writeReport;
  late FolderItem projects;

  setUp(() {
    index = DescriptionIndex();
    projects = FolderItem(id: 'projects', name: 'Projects');
    readBook = TaskItem(
      id: 'read-book',
      title: 'Read book',
      folderId: 'projects',
      infoBlocks: [
        TaskInfoBlock.description(
          id: 'details',
          text: 'A note about #reading and #project/asa.',
        ),
      ],
    );
    writeReport = TaskItem(
      id: 'write-report',
      title: 'Write report',
      infoBlocks: [
        TaskInfoBlock.description(
          id: 'details',
          text: 'Depends on [[Projects/Read book|the book]].',
        ),
      ],
    );
    index.rebuild([readBook, writeReport], [projects]);
  });

  test('resolves exact and folder-qualified Wikilinks', () {
    final exact = index.resolve('Read book');
    final qualified = index.resolve('Projects/Read book');

    expect(exact.task?.id, 'read-book');
    expect(exact.isAmbiguous, isFalse);
    expect(qualified.task?.id, 'read-book');
    expect(qualified.isUnresolved, isFalse);
  });

  test('returns explicit ambiguity and unresolved results', () {
    final duplicate = TaskItem(id: 'read-book-2', title: 'Read book');
    index.rebuild([readBook, duplicate, writeReport], [projects]);

    final ambiguous = index.resolve('Read book');
    final missing = index.resolve('Does not exist');

    expect(ambiguous.task, isNull);
    expect(ambiguous.isAmbiguous, isTrue);
    expect(
      ambiguous.candidates.map((task) => task.id),
      containsAll(['read-book', 'read-book-2']),
    );
    expect(missing.isUnresolved, isTrue);
    expect(missing.candidates, isEmpty);
  });

  test('indexes tags and backlinks', () {
    expect(index.tagsForTask('read-book'), {'reading', 'project/asa'});
    expect(index.backlinkTaskIds('read-book'), {'write-report'});
    expect(index.backlinkTaskIds('write-report'), isEmpty);
  });

  test('ranks matches by title, folder, tags, then description', () {
    final results = index.search('read');

    expect(results, isNotEmpty);
    expect(results.first.task.id, 'read-book');
    expect(results.first.matchedFields, contains('title'));
    expect(results.first.score, greaterThan(300));
  });

  test('excludes deleted tasks from resolution, search, and backlinks', () {
    final deleted = readBook.copyWith(isDeleted: true);
    index.rebuild([deleted, writeReport], [projects]);

    expect(index.resolve('Read book').isUnresolved, isTrue);
    expect(index.search('reading'), isEmpty);
    expect(index.backlinkTaskIds('read-book'), isEmpty);
  });

  test('handles cyclic folder data without an infinite walk', () {
    final first = FolderItem(
      id: 'first',
      name: 'First',
      parentFolderId: 'second',
    );
    final second = FolderItem(
      id: 'second',
      name: 'Second',
      parentFolderId: 'first',
    );
    final task = TaskItem(
      id: 'cyclic-task',
      title: 'Cyclic task',
      folderId: 'first',
    );

    index.rebuild([task], [first, second]);

    expect(index.search('cyclic'), hasLength(1));
    expect(index.resolve('Second/First/Cyclic task').isUnresolved, isTrue);
  });

  test('updates and removes tasks without stale backlinks', () {
    final updated = writeReport.copyWith(
      infoBlocks: [
        TaskInfoBlock.description(id: 'details', text: 'No link now.'),
      ],
    );

    index.updateTask(updated, [projects]);
    expect(index.backlinkTaskIds('read-book'), isEmpty);

    index.removeTask('read-book');
    expect(index.resolve('Read book').isUnresolved, isTrue);
  });
}
