import 'package:flutter_test/flutter_test.dart';

import 'package:asa/core/description_markdown.dart';
import 'package:asa/core/description_reference_parser.dart';
import 'package:asa/core/task_attachment_validation.dart';
import 'package:asa/features/tasks/models/task_info_block.dart';
import 'package:asa/features/tasks/models/task_model.dart';
import 'package:asa/features/tasks/services/description_index.dart';

void main() {
  test('parser preserves source while capping scanned references', () {
    final source = List<String>.generate(
      400,
      (index) => '😀 [[Task $index]] #tag$index',
    ).join('\n');

    final document = parseDescriptionDocument(source);

    expect(document.source, source);
    expect(document.references.length, kMaxParsedDescriptionReferences);
    expect(
      document.references.every((reference) => reference.start >= 0),
      isTrue,
    );
  });

  test('description index caps broad search results', () {
    final tasks = [
      for (var index = 0; index < 300; index++)
        TaskItem(id: 'task-$index', title: 'Reading task $index'),
    ];
    final index = DescriptionIndex()..rebuild(tasks, const <FolderItem>[]);

    final results = index.search('reading');

    expect(results.length, kMaxDescriptionSearchResults);
    expect(results.map((result) => result.task.id).toSet(), hasLength(200));
  });

  test('unsafe external URLs are never accepted as description links', () {
    expect(isSafeDescriptionHref('https://example.com'), isTrue);
    expect(isSafeDescriptionHref('http://example.com/path'), isTrue);
    expect(isSafeDescriptionHref('javascript:alert(1)'), isFalse);
    expect(isSafeDescriptionHref('file:///etc/passwd'), isFalse);
    expect(isSafeDescriptionHref('data:text/html,<script>'), isFalse);
    expect(isSafeDescriptionHref('attachment://private-id'), isFalse);
  });

  test(
    'local attachment values stay inside the owned attachment namespace',
    () {
      expect(
        isSafeStoredTaskAttachmentValue(
          '/data/app/task_attachments/report.pdf',
        ),
        isTrue,
      );
      expect(
        isSafeStoredTaskAttachmentValue('/data/app/other/report.pdf'),
        isFalse,
      );
      expect(
        isSafeStoredTaskAttachmentValue(
          '/data/app/task_attachments/../secrets.txt',
        ),
        isFalse,
      );

      const traversal = TaskAttachment(
        id: 'report',
        type: TaskAttachmentType.file,
        name: 'report.pdf',
        value: '/data/app/task_attachments/../secrets.pdf',
      );
      expect(
        () => TaskInfoBlock.description(
          id: 'description',
          attachments: const [traversal],
        ),
        throwsFormatException,
      );
    },
  );
}
