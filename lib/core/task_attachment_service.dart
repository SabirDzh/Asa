import 'package:url_launcher/url_launcher.dart';

import '../features/tasks/models/task_info_block.dart';
import 'task_attachment_service_stub.dart'
    if (dart.library.io) 'task_attachment_service_io.dart';

const int kMaxTaskAttachmentBytes = 10 * 1024 * 1024;
bool isAllowedTaskLink(String value) => isAllowedTaskAttachmentLink(value);

String attachmentDisplayName(String name) {
  final basename = name.trim().split(RegExp(r'[\\/]')).last;
  final safeName = basename.isEmpty ? 'attachment' : basename;
  if (safeName.length <= 128) return safeName;
  return safeName.substring(0, 128);
}

Future<TaskAttachment?> storeTaskAttachment({
  required TaskAttachmentType type,
  required String name,
  required List<int> bytes,
  String? mimeType,
  int existingAttachmentCount = 0,
}) async {
  if (bytes.length > kMaxTaskAttachmentBytes ||
      existingAttachmentCount < 0 ||
      existingAttachmentCount >= kMaxTaskAttachmentsPerTask ||
      (type == TaskAttachmentType.image &&
          !_hasSupportedImageSignature(bytes))) {
    return null;
  }

  if (type == TaskAttachmentType.link) return null;
  final displayName = attachmentDisplayName(name);
  final storedPath = await storeTaskAttachmentBytes(
    displayName: displayName,
    bytes: bytes,
  );
  if (storedPath == null) return null;

  return TaskAttachment(
    id: storedPath,
    type: type,
    name: displayName,
    value: storedPath,
    mimeType: mimeType,
  );
}

Future<bool> openTaskAttachment(TaskAttachment attachment) async {
  if (attachment.type == TaskAttachmentType.link) {
    if (!isAllowedTaskLink(attachment.value)) return false;
    return launchUrl(
      Uri.parse(attachment.value),
      mode: LaunchMode.externalApplication,
    );
  }
  return openStoredTaskAttachment(attachment.value);
}

bool _hasSupportedImageSignature(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return true;
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return true;
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38) {
    return true;
  }
  return bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50;
}
