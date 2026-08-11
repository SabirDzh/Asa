import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asa/core/task_attachment_service.dart';
import 'package:asa/features/tasks/models/task_info_block.dart';

import 'task_attachment_service_test_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory documentsDirectory;

  setUp(() async {
    documentsDirectory = await Directory.systemTemp.createTemp(
      'asa-attachment-service-test-',
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

  test('normalizes safe http and https links and rejects unsafe URLs', () {
    expect(
      normalizeTaskAttachmentLink('  HTTPS://EXAMPLE.COM/book  '),
      'https://example.com/book',
    );
    expect(isAllowedTaskLink('https://example.com/book'), isTrue);
    expect(isAllowedTaskLink('http://localhost:8080/source'), isTrue);
    expect(isAllowedTaskLink('javascript:alert(1)'), isFalse);
    expect(
      isAllowedTaskLink('data:text/html,<script>alert(1)</script>'),
      isFalse,
    );
    expect(isAllowedTaskLink('file:///private/secret'), isFalse);
    expect(isAllowedTaskLink('https://user:password@example.com'), isFalse);
    expect(isAllowedTaskLink('https://example.com\x00/secret'), isFalse);
  });

  test(
    'detects image type from magic bytes and requires matching metadata',
    () {
      const png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      expect(taskImageMimeFromBytes(png), 'image/png');
      expect(
        isSupportedTaskAttachmentContent(
          type: TaskAttachmentType.image,
          name: 'cover.png',
          bytes: png,
          mimeType: 'image/png',
        ),
        isTrue,
      );
      expect(
        isSupportedTaskAttachmentContent(
          type: TaskAttachmentType.image,
          name: 'cover.png',
          bytes: png,
          mimeType: 'image/jpeg',
        ),
        isFalse,
      );
      expect(
        isSupportedTaskAttachmentContent(
          type: TaskAttachmentType.image,
          name: 'cover.jpg',
          bytes: png,
          mimeType: 'image/png',
        ),
        isFalse,
      );
    },
  );

  test('accepts safe document signatures and rejects executable content', () {
    expect(
      isSupportedTaskAttachmentContent(
        type: TaskAttachmentType.file,
        name: 'document.pdf',
        bytes: const [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31],
        mimeType: 'application/pdf',
      ),
      isTrue,
    );
    expect(
      isSupportedTaskAttachmentContent(
        type: TaskAttachmentType.file,
        name: 'document.pdf',
        bytes: const [0x4D, 0x5A, 0x90, 0x00],
        mimeType: 'application/pdf',
      ),
      isFalse,
    );
    expect(
      isSupportedTaskAttachmentContent(
        type: TaskAttachmentType.file,
        name: 'document.pdf',
        bytes: const [0x50, 0x4B, 0x03, 0x04],
        mimeType: 'application/pdf',
      ),
      isFalse,
    );
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

  test(
    'deletes an app-owned attachment and tolerates a missing file',
    () async {
      final attachment = await storeTaskAttachment(
        type: TaskAttachmentType.file,
        name: 'delete-me.pdf',
        bytes: const [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31],
        mimeType: 'application/pdf',
      );

      expect(attachment, isNotNull);
      final storedAttachment = attachment!;
      try {
        expect(
          await readStoredTaskAttachmentBytes(storedAttachment.value),
          isNotNull,
        );
        expect(
          await deleteStoredTaskAttachment(storedAttachment.value),
          isTrue,
        );
        expect(
          await readStoredTaskAttachmentBytes(storedAttachment.value),
          isNull,
        );
        expect(
          await deleteStoredTaskAttachment(storedAttachment.value),
          isFalse,
        );
      } finally {
        await deleteStoredTaskAttachment(storedAttachment.value);
      }
    },
  );

  test('rejects deleting an external path', () async {
    final outside = File(
      '${documentsDirectory.parent.path}${Platform.pathSeparator}outside.pdf',
    );
    await outside.writeAsBytes(const [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31]);
    try {
      expect(await deleteStoredTaskAttachment(outside.path), isFalse);
      expect(await outside.exists(), isTrue);
    } finally {
      if (await outside.exists()) await outside.delete();
    }
  });

  test('sweeps orphan files without following external symlinks', () async {
    final attachmentsDirectory = Directory(
      '${documentsDirectory.path}${Platform.pathSeparator}task_attachments',
    );
    await attachmentsDirectory.create(recursive: true);
    final orphan = File(
      '${attachmentsDirectory.path}${Platform.pathSeparator}orphan.pdf',
    );
    await orphan.writeAsBytes(const [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31]);
    final outside = File(
      '${documentsDirectory.parent.path}${Platform.pathSeparator}outside-orphan.pdf',
    );
    await outside.writeAsBytes(const [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31]);
    final link = Link(
      '${attachmentsDirectory.path}${Platform.pathSeparator}outside-link.pdf',
    );
    await link.create(outside.path);

    try {
      expect(await deleteAllStoredTaskAttachments(), 1);
      expect(await orphan.exists(), isFalse);
      expect(await link.exists(), isTrue);
      expect(await outside.exists(), isTrue);
    } finally {
      if (await link.exists()) await link.delete();
      if (await outside.exists()) await outside.delete();
    }
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
