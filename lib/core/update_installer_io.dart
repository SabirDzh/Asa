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
      lower == 'release-assets.github.com' ||
      lower == 'objects.githubusercontent.com' ||
      lower.endsWith('.githubusercontent.com');
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
        if (currentUri == null ||
            currentUri.scheme.toLowerCase() != 'https' ||
            !_isSafeRedirectHost(currentUri.host) ||
            currentUri.hasPort ||
            currentUri.userInfo.isNotEmpty) {
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
          final resolved = currentUri.resolve(location);
          if (!_isSafeRedirectHost(resolved.host) ||
              resolved.scheme.toLowerCase() != 'https' ||
              resolved.hasPort ||
              resolved.userInfo.isNotEmpty) {
            return null;
          }
          currentUrl = resolved.toString();
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
      if (received == 0) {
        if (await file.exists()) await file.delete();
        return null;
      }
      if (total != null && total > 0 && received != total) {
        if (await file.exists()) await file.delete();
        return null;
      }

      if (expectedSha256 != null && expectedSha256.trim().isNotEmpty) {
        final expected = expectedSha256.trim().toLowerCase();
        if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
          await file.delete();
          return null;
        }
        final bytes = await file.readAsBytes();
        final actualHash = sha256.convert(bytes).toString().toLowerCase();
        if (actualHash != expected) {
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
