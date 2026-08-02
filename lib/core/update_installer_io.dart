import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

bool get canInstallApkLocallyImpl =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

Future<String> _defaultDirectory() async {
  final directory = await getApplicationDocumentsDirectory();
  return directory.path;
}

Future<String?> downloadUpdateFileImpl(
  String url, {
  http.Client? client,
  Future<String> Function()? directoryProvider,
  void Function(int received, int? total)? onProgress,
}) async {
  try {
    final directoryPath = await (directoryProvider ?? _defaultDirectory)();
    final directory = Directory(directoryPath);
    await directory.create(recursive: true);
    final file = File('$directoryPath${Platform.pathSeparator}asa-update.apk');
    final sender = client ?? http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..headers['User-Agent'] = 'ASA-UpdateChecker';
      final response = await sender
          .send(request)
          .timeout(const Duration(minutes: 3));
      if (response.statusCode != 200) return null;
      final total = response.contentLength;
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      // Reject empty or truncated downloads before the installer sees them.
      if (received == 0) return null;
      if (total != null && total > 0 && received != total) return null;
      return file.path;
    } finally {
      if (client == null) sender.close();
    }
  } on Object {
    return null;
  }
}

Future<bool> openApkInstallerImpl(String path) async {
  if (!canInstallApkLocallyImpl) return false;
  try {
    final result = await OpenFilex.open(
      path,
      type: 'application/vnd.android.package-archive',
    );
    return result.type == ResultType.done;
  } on Object {
    return false;
  }
}
