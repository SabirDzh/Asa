import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asa/core/version_service.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final Future<http.Response> Function(Uri uri, Map<String, String> headers)
  handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request.url, request.headers);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }
}

void main() {
  group('SemanticVersion', () {
    test('compares stable versions and ignores build metadata', () {
      expect(SemanticVersion.isNewer('1.2.0', '1.1.9'), isTrue);
      expect(SemanticVersion.isNewer('1.2.0+4', '1.2.0+3'), isFalse);
      expect(SemanticVersion.isNewer('v1.2.0', '1.2.0'), isFalse);
      expect(SemanticVersion.isNewer('1.2', '1.1.0'), isFalse);
    });

    test('follows prerelease precedence', () {
      expect(SemanticVersion.isNewer('1.0.0', '1.0.0-rc.1'), isTrue);
      expect(SemanticVersion.isNewer('1.0.0-beta.2', '1.0.0-beta.11'), isFalse);
      expect(SemanticVersion.isNewer('1.0.0-alpha.2', '1.0.0-alpha.1'), isTrue);
      expect(SemanticVersion.tryParse('1.0.0-0beta'), isNotNull);
      expect(
        SemanticVersion.isNewer('1.0.0-alpha.01', '1.0.0-alpha.1'),
        isFalse,
      );
    });

    test('rejects malformed versions', () {
      expect(SemanticVersion.tryParse('1.0'), isNull);
      expect(SemanticVersion.tryParse('01.0.0'), isNull);
      expect(SemanticVersion.tryParse('1.0.0-'), isNull);
      expect(SemanticVersion.isNewer('latest', '1.0.0'), isFalse);
    });
  });

  group('VersionService URL validation', () {
    test('allows only the canonical GitHub release tag URL', () {
      expect(
        VersionService.isSafeReleaseUrl(
          'https://github.com/SabirDzh/Asa/releases/tag/v1.2.0',
        ),
        isTrue,
      );
      expect(
        VersionService.isSafeReleaseUrl(
          'http://github.com/SabirDzh/Asa/releases/tag/v1.2.0',
        ),
        isFalse,
      );
      expect(
        VersionService.isSafeReleaseUrl(
          'https://evil.example/SabirDzh/Asa/releases/tag/v1.2.0',
        ),
        isFalse,
      );
      expect(
        VersionService.isSafeReleaseUrl(
          'https://github.com/SabirDzh/Asa/releases/latest',
        ),
        isFalse,
      );
    });
  });

  group('UpdateChecker', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('parses, validates and caches a release with its ETag', () async {
      late Map<String, String> requestHeaders;
      final checker = UpdateChecker(
        owner: 'SabirDzh',
        repo: 'Asa',
        currentVersion: '1.1.0',
        client: _FakeClient((uri, headers) async {
          requestHeaders = headers;
          return http.Response(
            jsonEncode({
              'tag_name': 'v1.2.0',
              'html_url': 'https://github.com/SabirDzh/Asa/releases/tag/v1.2.0',
              'body': 'Bug fixes',
            }),
            200,
            headers: {'etag': '"release-1.2.0"'},
          );
        }),
      );

      final info = await checker.fetchLatest(preferences: prefs);

      expect(info?.version, '1.2.0');
      expect(info?.notes, 'Bug fixes');
      expect(requestHeaders['accept'], 'application/vnd.github+json');
      expect(prefs.getString('update_release_etag'), '"release-1.2.0"');
      expect(prefs.getString('update_release_version'), '1.2.0');
    });

    test(
      'clears a stale ETag when a 304 has no valid cached release',
      () async {
        await prefs.setString('update_release_etag', '"stale"');

        final checker = UpdateChecker(
          owner: 'SabirDzh',
          repo: 'Asa',
          currentVersion: '1.1.0',
          client: _FakeClient((uri, headers) async {
            return http.Response('', 304);
          }),
        );

        expect(await checker.fetchLatest(preferences: prefs), isNull);
        expect(prefs.getString('update_release_etag'), isNull);
      },
    );

    test('uses cached release data after a 304 response', () async {
      await prefs.setString('update_release_etag', '"cached"');
      await prefs.setString('update_release_version', '1.3.0');
      await prefs.setString(
        'update_release_url',
        'https://github.com/SabirDzh/Asa/releases/tag/v1.3.0',
      );
      await prefs.setString('update_release_notes', 'Cached notes');

      final checker = UpdateChecker(
        owner: 'SabirDzh',
        repo: 'Asa',
        currentVersion: '1.1.0',
        client: _FakeClient((uri, headers) async {
          expect(headers['if-none-match'], '"cached"');
          return http.Response('', 304);
        }),
      );

      final info = await checker.fetchLatest(preferences: prefs);

      expect(info?.version, '1.3.0');
      expect(info?.notes, 'Cached notes');
    });

    test('rejects releases with unsafe URLs or invalid JSON shape', () async {
      final responses = <http.Response>[
        http.Response(
          jsonEncode({
            'tag_name': 'v1.2.0',
            'html_url': 'https://example.com/release',
          }),
          200,
        ),
        http.Response('{"tag_name": 12}', 200),
        http.Response('not json', 200),
      ];

      for (final response in responses) {
        final checker = UpdateChecker(
          owner: 'SabirDzh',
          repo: 'Asa',
          currentVersion: '1.1.0',
          client: _FakeClient((uri, headers) async => response),
        );
        expect(await checker.fetchLatest(preferences: prefs), isNull);
      }
    });

    test('truncates oversized release notes by Unicode code points', () async {
      final notes = '😀' * 25 * 1024;
      final checker = UpdateChecker(
        owner: 'SabirDzh',
        repo: 'Asa',
        currentVersion: '1.1.0',
        client: _FakeClient((uri, headers) async {
          return http.Response(
            jsonEncode({
              'tag_name': '1.2.0',
              'html_url': 'https://github.com/SabirDzh/Asa/releases/tag/v1.2.0',
              'body': notes,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final info = await checker.fetchLatest(preferences: prefs);

      expect(info, isNotNull);
      expect(info!.notes.endsWith('\n…'), isTrue);
      expect(info.notes.runes.length, 20 * 1024 + 2);
    });
  });
}
