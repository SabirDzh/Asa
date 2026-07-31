import 'dart:io';

import 'package:asa/core/task_attachment_service.dart';
import 'package:asa/features/tasks/models/task_info_block.dart';

Future<bool> verifyExternalPathIsRejectedImpl() async {
  final directory = await Directory.systemTemp.createTemp(
    'asa-attachment-test-',
  );
  final file = File('${directory.path}${Platform.pathSeparator}outside.txt');
  await file.writeAsString('not an app attachment');
  try {
    final opened = await openTaskAttachment(
      TaskAttachment(
        id: 'outside',
        type: TaskAttachmentType.file,
        name: 'outside.txt',
        value: file.path,
      ),
    );
    return !opened;
  } finally {
    await directory.delete(recursive: true);
  }
}
