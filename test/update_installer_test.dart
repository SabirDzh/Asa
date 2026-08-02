import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:asa/core/update_installer.dart';

class _StreamClient extends http.BaseClient {
  _StreamClient(this.bytes);

  final List<int> bytes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(bytes),
      200,
      contentLength: bytes.length,
      request: request,
    );
  }
}

class _FailingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(const Stream.empty(), 404, request: request);
  }
}

void main() {
  test('canInstallApkLocally is exposed (value checked in dialogs)', () {
    expect(canInstallApkLocally, isA<bool>());
  });

  test('downloadUpdateFile streams bytes and reports progress', () async {
    final dir = await Directory.systemTemp.createTemp('asa_download_test');
    addTearDown(() => dir.delete(recursive: true));

    final bytes = utf8.encode('fake apk content');
    final progress = <(int, int?)>[];
    final path = await downloadUpdateFile(
      'https://github.com/SabirDzh/Asa/releases/download/v1.2.0/app-arm64-v8a-release.apk',
      client: _StreamClient(bytes),
      directoryProvider: () async => dir.path,
      onProgress: (received, total) => progress.add((received, total)),
    );

    expect(path, isNotNull);
    final file = File(path!);
    expect(file.readAsBytesSync(), bytes);
    expect(progress, isNotEmpty);
    expect(progress.last.$1, bytes.length);
    expect(progress.last.$2, bytes.length);
  });

  test('downloadUpdateFile returns null on http error', () async {
    final dir = await Directory.systemTemp.createTemp('asa_download_test2');
    addTearDown(() => dir.delete(recursive: true));

    final path = await downloadUpdateFile(
      'https://github.com/SabirDzh/Asa/releases/download/v1.2.0/app.apk',
      client: _FailingClient(),
      directoryProvider: () async => dir.path,
    );
    expect(path, isNull);
  });

  test('downloadUpdateFile rejects an empty response', () async {
    final dir = await Directory.systemTemp.createTemp('asa_download_test3');
    addTearDown(() => dir.delete(recursive: true));

    final path = await downloadUpdateFile(
      'https://github.com/SabirDzh/Asa/releases/download/v1.2.0/app.apk',
      client: _StreamClient(const []),
      directoryProvider: () async => dir.path,
    );
    expect(path, isNull);
  });

  test('openApkInstaller returns a bool without throwing', () async {
    expect(await openApkInstaller('/nonexistent/asa-update.apk'), isA<bool>());
  });
}
