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

Future<bool> openStoredTaskAttachment(String path) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final attachmentsDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}task_attachments',
    );
    if (!await attachmentsDirectory.exists()) return false;

    final rootPath = await attachmentsDirectory.resolveSymbolicLinks();
    final file = File(path);
    if (!await file.exists()) return false;
    final filePath = await file.resolveSymbolicLinks();
    final separator = Platform.pathSeparator;
    if (filePath != rootPath && !filePath.startsWith('$rootPath$separator')) {
      return false;
    }

    return launchUrl(Uri.file(filePath), mode: LaunchMode.externalApplication);
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
