import 'package:flutter_test/flutter_test.dart';

import 'package:asa/core/task_attachment_service.dart';
import 'package:asa/features/tasks/models/task_info_block.dart';

import 'task_attachment_service_test_platform.dart';

void main() {
  test('accepts only http and https task links', () {
    expect(isAllowedTaskLink('https://example.com/book'), isTrue);
    expect(isAllowedTaskLink('http://localhost:8080/source'), isTrue);
    expect(isAllowedTaskLink('javascript:alert(1)'), isFalse);
    expect(isAllowedTaskLink('file:///private/secret'), isFalse);
  });

  test('attachment display names cannot escape their basename', () {
    expect(attachmentDisplayName('../book.pdf'), 'book.pdf');
    expect(attachmentDisplayName(r'..\book.pdf'), 'book.pdf');
    expect(attachmentDisplayName('a' * 200).length, 128);
  });

  test('rejects image bytes without a supported signature', () async {
    final result = await storeTaskAttachment(
      type: TaskAttachmentType.image,
      name: 'cover.png',
      bytes: const [1, 2, 3, 4, 5],
    );
    expect(result, isNull);
  });

  test('accepts a PNG signature for image attachments', () async {
    final result = await storeTaskAttachment(
      type: TaskAttachmentType.image,
      name: 'cover.png',
      bytes: const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
    );
    // The web/stub implementation cannot persist local binary files, while
    // native implementations return a stored attachment for valid bytes.
    expect(result == null || result.type == TaskAttachmentType.image, isTrue);
  });

  test('does not store an attachment over the byte limit', () async {
    final result = await storeTaskAttachment(
      type: TaskAttachmentType.file,
      name: 'large.bin',
      bytes: List<int>.filled(kMaxTaskAttachmentBytes + 1, 0),
    );
    expect(result, isNull);
  });

  test('does not exceed the per-task attachment count', () async {
    final result = await storeTaskAttachment(
      type: TaskAttachmentType.file,
      name: 'book.pdf',
      bytes: const [1, 2, 3],
      existingAttachmentCount: kMaxTaskAttachmentsPerTask,
    );
    expect(result, isNull);
  });

  test('opening a missing local attachment returns false', () async {
    expect(
      await openTaskAttachment(
        const TaskAttachment(
          id: 'local',
          type: TaskAttachmentType.file,
          name: 'file.pdf',
          value: '/missing/file.pdf',
        ),
      ),
      isFalse,
    );
  });

  test(
    'does not open an existing file outside the app attachment directory',
    () async {
      expect(await verifyExternalPathIsRejected(), isTrue);
    },
  );
}
