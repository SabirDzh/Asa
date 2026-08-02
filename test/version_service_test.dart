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

    test('304 cache round-trips the asset and published date', () async {
      await prefs.setString('update_release_etag', '"cached-assets"');
      await prefs.setString('update_release_version', '1.3.0');
      await prefs.setString(
        'update_release_url',
        'https://github.com/SabirDzh/Asa/releases/tag/v1.3.0',
      );
      await prefs.setString('update_release_notes', 'Cached notes');
      await prefs.setString(
        'update_release_published_at',
        '2026-08-01T10:00:00.000Z',
      );
      await prefs.setString(
        'update_release_asset_url',
        'https://github.com/SabirDzh/Asa/releases/download/v1.3.0/app-arm64-v8a-release.apk',
      );
      await prefs.setString(
        'update_release_asset_name',
        'app-arm64-v8a-release.apk',
      );

      final checker = UpdateChecker(
        owner: 'SabirDzh',
        repo: 'Asa',
        currentVersion: '1.1.0',
        client: _FakeClient((uri, headers) async {
          return http.Response('', 304);
        }),
      );

      final info = await checker.fetchLatest(preferences: prefs);

      expect(info?.publishedAt, DateTime.utc(2026, 8, 1, 10));
      expect(info?.assetUrl, isNotNull);
      expect(info?.assetName, 'app-arm64-v8a-release.apk');
    });

    test('fetchReleaseHistory returns newest first and caches', () async {
      final checker = UpdateChecker(
        owner: 'SabirDzh',
        repo: 'Asa',
        currentVersion: '1.1.0',
        client: _FakeClient((uri, headers) async {
          return http.Response(
            jsonEncode([
              {
                'tag_name': 'v1.1.0',
                'html_url':
                    'https://github.com/SabirDzh/Asa/releases/tag/v1.1.0',
                'published_at': '2026-07-20T10:00:00Z',
                'body': 'Older',
              },
              {
                'tag_name': 'v1.2.0',
                'html_url':
                    'https://github.com/SabirDzh/Asa/releases/tag/v1.2.0',
                'published_at': '2026-08-01T10:00:00Z',
                'body': 'Newer',
                'assets': [
                  {
                    'name': 'app-arm64-v8a-release.apk',
                    'browser_download_url':
                        'https://github.com/SabirDzh/Asa/releases/download/v1.2.0/app-arm64-v8a-release.apk',
                  },
                ],
              },
            ]),
            200,
          );
        }),
      );

      final releases = await checker.fetchReleaseHistory(preferences: prefs);
      expect(releases.map((r) => r.version).toList(), ['1.2.0', '1.1.0']);
      expect(releases.first.assetUrl, isNotNull);
      expect(prefs.getString('update_release_history'), isNotNull);
    });

    test(
      'fetchReleaseHistory falls back to cache on network failure',
      () async {
        final checker = UpdateChecker(
          owner: 'SabirDzh',
          repo: 'Asa',
          currentVersion: '1.1.0',
          client: _FakeClient((uri, headers) async {
            return http.Response('boom', 500);
          }),
        );

        final releases = await checker.fetchReleaseHistory(preferences: prefs);
        expect(releases, isEmpty);

        await prefs.setString(
          'update_release_history',
          jsonEncode([
            {
              'version': '1.2.0',
              'url': 'https://github.com/SabirDzh/Asa/releases/tag/v1.2.0',
              'notes': 'Cached',
              'publishedAt': '2026-08-01T10:00:00.000Z',
              'assetUrl': null,
              'assetName': null,
            },
          ]),
        );
        final cached = await checker.fetchReleaseHistory(preferences: prefs);
        expect(cached.map((r) => r.version).toList(), ['1.2.0']);
        expect(cached.first.notes, 'Cached');
      },
    );

    test('drops an unsafe cached asset but keeps the release', () async {
      await prefs.setString('update_release_etag', '"cached-unsafe"');
      await prefs.setString('update_release_version', '1.3.0');
      await prefs.setString(
        'update_release_url',
        'https://github.com/SabirDzh/Asa/releases/tag/v1.3.0',
      );
      await prefs.setString(
        'update_release_asset_url',
        'https://evil.example/app.apk',
      );
      await prefs.setString('update_release_asset_name', 'app.apk');

      final checker = UpdateChecker(
        owner: 'SabirDzh',
        repo: 'Asa',
        currentVersion: '1.1.0',
        client: _FakeClient((uri, headers) async {
          return http.Response('', 304);
        }),
      );

      final info = await checker.fetchLatest(preferences: prefs);

      expect(info?.version, '1.3.0');
      expect(info?.assetUrl, isNull);
      expect(info?.assetName, isNull);
    });

    test('history cache drops an unsafe cached asset on read', () async {
      await prefs.setString(
        'update_release_history',
        jsonEncode([
          {
            'version': '1.2.0',
            'url': 'https://github.com/SabirDzh/Asa/releases/tag/v1.2.0',
            'notes': 'Cached',
            'assetUrl': 'https://evil.example/app.apk',
            'assetName': 'app.apk',
          },
        ]),
      );

      final checker = UpdateChecker(
        owner: 'SabirDzh',
        repo: 'Asa',
        currentVersion: '1.1.0',
        client: _FakeClient((uri, headers) async {
          return http.Response('boom', 500);
        }),
      );

      final cached = await checker.fetchReleaseHistory(preferences: prefs);
      expect(cached, hasLength(1));
      expect(cached.first.version, '1.2.0');
      expect(cached.first.assetUrl, isNull);
      expect(cached.first.assetName, isNull);
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

  group('UpdateInfo assets', () {
    test('parses published date and prefers the arm64 APK asset', () {
      final info = UpdateInfo.fromJson({
        'tag_name': 'v1.2.0',
        'html_url': 'https://github.com/SabirDzh/Asa/releases/tag/v1.2.0',
        'published_at': '2026-08-01T18:42:29Z',
        'body': 'Bug fixes',
        'assets': [
          {
            'name': 'app-x86_64-release.apk',
            'browser_download_url':
                'https://github.com/SabirDzh/Asa/releases/download/v1.2.0/app-x86_64-release.apk',
          },
          {
            'name': 'app-arm64-v8a-release.apk',
            'browser_download_url':
                'https://github.com/SabirDzh/Asa/releases/download/v1.2.0/app-arm64-v8a-release.apk',
          },
        ],
      });
      expect(info, isNotNull);
      expect(info!.publishedAt, DateTime.utc(2026, 8, 1, 18, 42, 29));
      expect(info.assetName, 'app-arm64-v8a-release.apk');
      expect(
        info.assetUrl,
        'https://github.com/SabirDzh/Asa/releases/download/v1.2.0/app-arm64-v8a-release.apk',
      );
    });

    test('falls back to any apk when no arm64 asset exists', () {
      final info = UpdateInfo.fromJson({
        'tag_name': '1.1.0',
        'html_url': 'https://github.com/SabirDzh/Asa/releases/tag/v1.1.0',
        'assets': [
          {
            'name': 'Asa-v1.1.0+2-arm64-v8a.apk',
            'browser_download_url':
                'https://github.com/SabirDzh/Asa/releases/download/v1.1.0%2B2/Asa-v1.1.0%2B2-arm64-v8a.apk',
          },
        ],
      });
      expect(info?.assetUrl, isNotNull);
      expect(info?.publishedAt, isNull);
    });
  });

  group('Asset URL validation', () {
    test('accepts only github.com owner/repo releases/download apk URLs', () {
      final ok =
          'https://github.com/SabirDzh/Asa/releases/download/v1.2.0/app-arm64-v8a-release.apk';
      expect(
        UpdateChecker.isSafeAssetUrl(ok, owner: 'SabirDzh', repo: 'Asa'),
        isTrue,
      );
      expect(
        UpdateChecker.isSafeAssetUrl(
          'https://github.com/SabirDzh/Asa/releases/download/v1.1.0%2B2/Asa-v1.1.0%2B2-arm64-v8a.apk',
          owner: 'SabirDzh',
          repo: 'Asa',
        ),
        isTrue,
      );
      expect(
        UpdateChecker.isSafeAssetUrl(
          'https://github.com/SabirDzh/Asa/releases/download/v1.2.0/app.apk?x=1',
          owner: 'SabirDzh',
          repo: 'Asa',
        ),
        isFalse,
      );
      expect(
        UpdateChecker.isSafeAssetUrl(
          'https://github.com/SabirDzh/Asa/releases/download/v1.2.0/app.apk#frag',
          owner: 'SabirDzh',
          repo: 'Asa',
        ),
        isFalse,
      );
      expect(
        UpdateChecker.isSafeAssetUrl(
          'http://github.com/SabirDzh/Asa/releases/download/v1.2.0/app.apk',
          owner: 'SabirDzh',
          repo: 'Asa',
        ),
        isFalse,
      );
      expect(
        UpdateChecker.isSafeAssetUrl(
          'https://evil.example/SabirDzh/Asa/releases/download/v1.2.0/app.apk',
          owner: 'SabirDzh',
          repo: 'Asa',
        ),
        isFalse,
      );
      expect(
        UpdateChecker.isSafeAssetUrl(
          'https://github.com/SabirDzh/Asa/releases/download/v1.2.0/notes.txt',
          owner: 'SabirDzh',
          repo: 'Asa',
        ),
        isFalse,
      );
      expect(
        UpdateChecker.isSafeAssetUrl(
          'https://github.com/SabirDzh/Asa/releases/tag/v1.2.0',
          owner: 'SabirDzh',
          repo: 'Asa',
        ),
        isFalse,
      );
      expect(
        UpdateChecker.isSafeAssetUrl(
          'https://github.com/SabirDzh/Other/releases/download/v1.2.0/app.apk',
          owner: 'SabirDzh',
          repo: 'Asa',
        ),
        isFalse,
      );
    });
  });
}
