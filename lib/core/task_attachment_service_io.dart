import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
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

Future<List<int>?> readStoredTaskAttachmentBytesPlatform(String path) async {
  try {
    final file = await _resolveStoredTaskAttachmentFile(path);
    if (file == null) return null;
    final length = await file.length();
    if (length <= 0 || length > 10 * 1024 * 1024) return null;
    return await file.readAsBytes();
  } on Object {
    return null;
  }
}

Future<bool> openStoredTaskAttachment(String path) async {
  try {
    final file = await _resolveStoredTaskAttachmentFile(path);
    if (file == null) return false;
    return launchUrl(Uri.file(file.path), mode: LaunchMode.externalApplication);
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
