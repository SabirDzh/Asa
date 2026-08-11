import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/tasks/models/task_info_block.dart';
import 'task_attachment_validation.dart' as validation;
import 'task_attachment_service_stub.dart'
    if (dart.library.io) 'task_attachment_service_io.dart';

const int kMaxTaskAttachmentBytes = 10 * 1024 * 1024;

String? normalizeTaskAttachmentLink(String value) =>
    validation.normalizeTaskAttachmentLink(value);

bool isAllowedTaskLink(String value) =>
    normalizeTaskAttachmentLink(value) != null;

/// Backwards-compatible export for callers that display a safe file name.
String attachmentDisplayName(String name) =>
    validation.attachmentDisplayName(name);

/// Validates the bytes and metadata before an attachment is persisted.
///
/// Image bytes are checked against their actual image signature. Generic files
/// are restricted to common document/text formats and known executable/script
/// signatures are rejected before an external app can open them.
bool isSupportedTaskAttachmentContent({
  required TaskAttachmentType type,
  required String name,
  required List<int> bytes,
  String? mimeType,
}) {
  if (bytes.isEmpty || bytes.length > kMaxTaskAttachmentBytes) return false;
  final extension = _extension(name);
  final mime = mimeType?.trim().toLowerCase();

  if (type == TaskAttachmentType.image) {
    return _hasSupportedImageSignature(bytes) &&
        _isCompatibleImageMime(bytes, extension, mime);
  }
  if (type != TaskAttachmentType.file) return false;
  return _hasSupportedFileSignature(extension, bytes) &&
      _isCompatibleFileMime(extension, mime);
}

Future<TaskAttachment?> storeTaskAttachment({
  required TaskAttachmentType type,
  required String name,
  required List<int> bytes,
  String? mimeType,
  int existingAttachmentCount = 0,
}) async {
  if (existingAttachmentCount < 0 ||
      existingAttachmentCount >= kMaxTaskAttachmentsPerTask ||
      bytes.length > kMaxTaskAttachmentBytes) {
    return null;
  }

  final displayName = validation.attachmentDisplayName(name);
  List<int> bytesToStore = bytes;
  String storedName = displayName;
  String? storedMimeType = mimeType?.trim().toLowerCase();

  if (type == TaskAttachmentType.image) {
    if (!isSupportedTaskAttachmentContent(
      type: type,
      name: displayName,
      bytes: bytes,
      mimeType: mimeType,
    )) {
      return null;
    }
    final compressed = await _compressImageToWebp(bytes);
    if (compressed == null ||
        compressed.length > kMaxTaskAttachmentBytes ||
        !_isWebpSignature(compressed)) {
      return null;
    }
    bytesToStore = compressed;
    storedName = _withExtension(displayName, '.webp');
    storedMimeType = 'image/webp';
  } else if (type == TaskAttachmentType.file) {
    if (!isSupportedTaskAttachmentContent(
      type: type,
      name: displayName,
      bytes: bytes,
      mimeType: mimeType,
    )) {
      return null;
    }
  } else {
    return null;
  }

  final storedPath = await storeTaskAttachmentBytes(
    displayName: storedName,
    bytes: bytesToStore,
  );
  if (storedPath == null) return null;

  return TaskAttachment(
    id: storedPath,
    type: type,
    name: storedName,
    value: storedPath,
    mimeType: storedMimeType,
  );
}

/// Reads a stored image after enforcing the same attachment-directory boundary
/// used when opening files. Returns null for missing or unsafe paths.
Future<List<int>?> readStoredTaskAttachmentBytes(
  String path, {
  int maxBytes = kMaxTaskAttachmentBytes,
}) async {
  return readStoredTaskAttachmentBytesPlatform(path, maxBytes: maxBytes);
}

Future<bool> shareTaskAttachment(TaskAttachment attachment) async {
  if (attachment.type != TaskAttachmentType.file) return false;
  return shareStoredTaskAttachment(
    attachment.value,
    name: attachment.name,
    mimeType: attachment.mimeType,
  );
}

Future<bool> openTaskAttachment(TaskAttachment attachment) async {
  if (attachment.type == TaskAttachmentType.link) {
    final normalized = validation.normalizeTaskAttachmentLink(attachment.value);
    if (normalized == null) return false;
    return launchUrl(
      Uri.parse(normalized),
      mode: LaunchMode.externalApplication,
    );
  }
  return openStoredTaskAttachment(attachment.value);
}

Future<List<int>?> _compressImageToWebp(List<int> bytes) async {
  try {
    final compressed = await FlutterImageCompress.compressWithList(
      Uint8List.fromList(bytes),
      format: CompressFormat.webp,
      quality: 85,
    );
    return compressed;
  } on Object {
    return null;
  }
}

String? taskImageMimeFromBytes(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
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
    return 'image/png';
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38) {
    return 'image/gif';
  }
  if (_isWebpSignature(bytes)) return 'image/webp';
  return null;
}

bool _isCompatibleImageMime(List<int> bytes, String extension, String? mime) {
  final actualMime = taskImageMimeFromBytes(bytes);
  if (actualMime == null) return false;
  if (mime != null &&
      mime.isNotEmpty &&
      mime != 'image/*' &&
      mime != actualMime) {
    return false;
  }
  final expectedByExtension = switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    _ => null,
  };
  return expectedByExtension == null || expectedByExtension == actualMime;
}

bool _hasSupportedImageSignature(List<int> bytes) =>
    taskImageMimeFromBytes(bytes) != null;

bool _isWebpSignature(List<int> bytes) {
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

bool _hasSupportedFileSignature(String extension, List<int> bytes) {
  if (_hasExecutableOrScriptSignature(bytes)) return false;
  switch (extension) {
    case 'pdf':
      return bytes.length >= 5 &&
          bytes[0] == 0x25 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46 &&
          bytes[4] == 0x2D;
    case 'docx':
    case 'xlsx':
    case 'pptx':
    case 'zip':
      return _isZipSignature(bytes);
    case 'txt':
    case 'md':
    case 'csv':
    case 'json':
    case 'xml':
    case 'log':
      return _isUtf8Text(bytes);
    default:
      return false;
  }
}

bool _hasExecutableOrScriptSignature(List<int> bytes) {
  if (bytes.length >= 2 && bytes[0] == 0x4D && bytes[1] == 0x5A) return true;
  if (bytes.length >= 4 &&
      bytes[0] == 0x7F &&
      bytes[1] == 0x45 &&
      bytes[2] == 0x4C &&
      bytes[3] == 0x46) {
    return true;
  }
  if (bytes.length >= 2 && bytes[0] == 0x23 && bytes[1] == 0x21) return true;
  if (bytes.length >= 4 &&
      ((bytes[0] == 0xCF && bytes[1] == 0xFA) ||
          (bytes[0] == 0xCA && bytes[1] == 0xFE) ||
          (bytes[0] == 0xFE && bytes[1] == 0xED))) {
    return true;
  }
  return false;
}

bool _isZipSignature(List<int> bytes) {
  return bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4B &&
      (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07) &&
      (bytes[3] == 0x04 || bytes[3] == 0x06 || bytes[3] == 0x08);
}

bool _isUtf8Text(List<int> bytes) {
  if (bytes.contains(0)) return false;
  try {
    utf8.decode(bytes, allowMalformed: false);
    return true;
  } on FormatException {
    return false;
  }
}

bool _isCompatibleFileMime(String extension, String? mime) {
  if (mime == null || mime.isEmpty) return true;
  const allowed = <String, Set<String>>{
    'pdf': {'application/pdf'},
    'docx': {
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/zip',
    },
    'xlsx': {
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/zip',
    },
    'pptx': {
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'application/zip',
    },
    'zip': {'application/zip', 'application/x-zip-compressed'},
    'txt': {'text/plain'},
    'md': {'text/markdown', 'text/plain'},
    'csv': {'text/csv', 'text/plain', 'application/csv'},
    'json': {'application/json', 'text/plain'},
    'xml': {'application/xml', 'text/xml', 'text/plain'},
    'log': {'text/plain'},
  };
  return allowed[extension]?.contains(mime) ?? false;
}

String _extension(String name) {
  final basename = name.trim().split(RegExp(r'[\\/]')).last.toLowerCase();
  final dot = basename.lastIndexOf('.');
  if (dot <= 0 || dot == basename.length - 1) return '';
  return basename.substring(dot + 1);
}

String _withExtension(String name, String extension) {
  final basename = attachmentDisplayName(name);
  final dot = basename.lastIndexOf('.');
  final stem = dot > 0 ? basename.substring(0, dot) : basename;
  return validation.attachmentDisplayName('$stem$extension');
}
