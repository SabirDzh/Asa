import 'dart:io';

import 'package:crypto/crypto.dart';
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

bool _isSafeRedirectHost(String host) {
  final lower = host.toLowerCase();
  return lower == 'github.com' ||
      lower == 'objects.githubusercontent.com' ||
      lower == 'release-assets.github.com' ||
      lower.endsWith('.githubusercontent.com') ||
      lower.endsWith('.github.com');
}

Future<String?> downloadUpdateFileImpl(
  String url, {
  http.Client? client,
  Future<String> Function()? directoryProvider,
  void Function(int received, int? total)? onProgress,
  String? expectedSha256,
}) async {
  try {
    final directoryPath = await (directoryProvider ?? _defaultDirectory)();
    final directory = Directory(directoryPath);
    await directory.create(recursive: true);
    final file = File('$directoryPath${Platform.pathSeparator}asa-update.apk');
    final sender = client ?? http.Client();
    try {
      var currentUrl = url;
      http.StreamedResponse? response;
      for (var redirectCount = 0; redirectCount < 5; redirectCount++) {
        final currentUri = Uri.tryParse(currentUrl);
        if (currentUri == null || !_isSafeRedirectHost(currentUri.host)) {
          return null;
        }

        final request =
            http.Request('GET', currentUri)
              ..headers['User-Agent'] = 'ASA-UpdateChecker'
              ..followRedirects = false;
        final res = await sender
            .send(request)
            .timeout(const Duration(minutes: 3));
        if (res.statusCode == 301 ||
            res.statusCode == 302 ||
            res.statusCode == 307 ||
            res.statusCode == 308) {
          final location = res.headers['location'];
          if (location == null || location.isEmpty) return null;
          currentUrl = location;
          continue;
        }
        if (res.statusCode == 200) {
          response = res;
          break;
        }
        return null;
      }

      if (response == null || response.statusCode != 200) return null;
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

      if (expectedSha256 != null && expectedSha256.isNotEmpty) {
        final bytes = await file.readAsBytes();
        final actualHash =
            sha256.convert(bytes).toString().toLowerCase().trim();
        if (actualHash != expectedSha256.toLowerCase().trim()) {
          await file.delete();
          return null;
        }
      }

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
