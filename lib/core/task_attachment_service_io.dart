import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

Future<String?> storeTaskAttachmentBytes({
  required String displayName,
  required List<int> bytes,
}) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final attachmentsDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}task_attachments',
    );
    await attachmentsDirectory.create(recursive: true);

    final extension = _safeExtension(displayName);
    final fileName = '${const Uuid().v4()}$extension';
    final file = File(
      '${attachmentsDirectory.path}${Platform.pathSeparator}$fileName',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } on Object {
    return null;
  }
}

Future<File?> _resolveStoredTaskAttachmentFile(String path) async {
  final directory = await getApplicationDocumentsDirectory();
  final attachmentsDirectory = Directory(
    '${directory.path}${Platform.pathSeparator}task_attachments',
  );
  if (!await attachmentsDirectory.exists()) return null;

  final rootPath = await attachmentsDirectory.resolveSymbolicLinks();
  final file = File(path);
  if (!await file.exists()) return null;
  final filePath = await file.resolveSymbolicLinks();
  final separator = Platform.pathSeparator;
  if (filePath == rootPath || !filePath.startsWith('$rootPath$separator')) {
    return null;
  }
  return File(filePath);
}

Future<bool> deleteStoredTaskAttachmentPlatform(String path) async {
  try {
    final file = await _resolveStoredTaskAttachmentFile(path);
    if (file == null) return false;
    await file.delete();
    return true;
  } on Object {
    return false;
  }
}

Future<int> deleteAllStoredTaskAttachmentsPlatform() async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final attachmentsDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}task_attachments',
    );
    if (!await attachmentsDirectory.exists()) return 0;

    var deleted = 0;
    await for (final entity in attachmentsDirectory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || await Link(entity.path).exists()) continue;
      final resolved = await _resolveStoredTaskAttachmentFile(entity.path);
      if (resolved == null) continue;
      try {
        await resolved.delete();
        deleted++;
      } on Object {
        // A single inaccessible orphan must not block the rest of the reset.
      }
    }
    return deleted;
  } on Object {
    return 0;
  }
}

Future<List<int>?> readStoredTaskAttachmentBytesPlatform(
  String path, {
  int maxBytes = 10 * 1024 * 1024,
}) async {
  try {
    if (maxBytes <= 0) return null;
    final file = await _resolveStoredTaskAttachmentFile(path);
    if (file == null) return null;
    final length = await file.length();
    if (length <= 0 || length > maxBytes) return null;
    return await file.readAsBytes();
  } on Object {
    return null;
  }
}

Future<bool> shareStoredTaskAttachment(
  String path, {
  required String name,
  String? mimeType,
}) async {
  try {
    final file = await _resolveStoredTaskAttachmentFile(path);
    if (file == null) return false;
    final length = await file.length();
    if (length <= 0 || length > 10 * 1024 * 1024) return false;
    await Share.shareXFiles([
      XFile(file.path, name: name, mimeType: mimeType),
    ], subject: name);
    return true;
  } on Object {
    return false;
  }
}

Future<bool> openStoredTaskAttachment(String path) async {
  try {
    final file = await _resolveStoredTaskAttachmentFile(path);
    if (file == null) return false;
    final result = await OpenFilex.open(file.path);
    return result.type == ResultType.done;
  } on Object {
    return false;
  }
}

String _safeExtension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  final extension = name.substring(dot, name.length);
  if (!RegExp(r'^\.[A-Za-z0-9]{1,10}$').hasMatch(extension)) return '';
  return extension.toLowerCase();
}
