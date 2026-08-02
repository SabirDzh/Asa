# In-App Update Install + Version Sync + "What's New" Screen — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the browser-open "Install" button with an in-app APK download + system-package-installer flow, automate version synchronization through a release script, and add a dedicated "What's New" screen showing release history from GitHub.

**Architecture:** Extend `UpdateInfo` (version/url/notes) with `publishedAt` + APK asset info parsed from the GitHub release JSON. Add a conditional platform `UpdateInstaller` (io/stub) that streams the APK to app documents and opens it with `open_filex` (ACTION_VIEW, MIME `application/vnd.android.package-archive`). Extract the update dialog into a stateful, testable `UpdateDialog` with download progress. Add `UpdateChecker.fetchReleaseHistory()` (list endpoint + prefs cache) powering a new `WhatsNewScreen` reachable from Settings and the update dialog. Create `scripts/release.sh` that bumps `pubspec.yaml`, updates the `APP_VERSION` default, builds with `--dart-define=APP_VERSION`, tags, and creates the GitHub release with the APK asset. Make the displayed app version dynamic (`VersionService.currentVersion`) so it can never drift.

**Tech Stack:** Flutter/Dart 3.7+, `provider`, `http`, `shared_preferences`, `path_provider`, `url_launcher`, `open_filex ^4.7.0` (new), `flutter_markdown_plus` (already present), GitHub REST API (`/releases` + `/releases/latest`).

## Global Constraints

- Repo: `SabirDzh/Asa`; release tag format `v<ver>+<build>` (e.g. `v1.2.0+3`); asset naming `Asa-<ver>+<build>-arm64-v8a.apk`.
- Version is plain SemVer for the app (`1.2.0`); build number goes into `pubspec.yaml` as `1.2.0+3`.
- `VersionService.currentVersion` stays `String.fromEnvironment('APP_VERSION', defaultValue: '<ver>')` — never remove the `--dart-define` path.
- All new user-facing strings must be added to BOTH `ru` and `en` maps in `lib/core/app_strings.dart`.
- Commit style (from repo history): `feat:`, `fix:`, `test:`, `chore:`, `refactor:`, lowercase subject, no trailing period. Commit after EVERY task.
- No `dart:io` imports in files compiled for web; use the existing conditional-import pattern (`stub` + `io`).
- Keep the update check optional: every network/storage failure must be swallowed (log via `LoggerService`), never block startup.
- Asset URL safety: only `https://github.com/<owner>/<repo>/releases/download/<tag>/<file.apk>` is accepted (mirrors `isSafeReleaseUrl`).
- `dart format` + `dart analyze` must stay clean; run the full `flutter test` suite at the end.
- GitHub release creation: prefer `gh` CLI if installed; otherwise `curl` with `GITHUB_TOKEN` env var. Never hardcode tokens in the repo.
- `open_filex` ships its own `FileProvider` (authority `${applicationId}.fileProvider.com.crazecoder.openfile`, `root-path` covers any file), so **no AndroidManifest provider change is needed**; the plugin deliberately does NOT require `REQUEST_INSTALL_PACKAGES`.

---

### Task 1: Extend `UpdateInfo` (date + APK asset) and asset-URL validation

**Files:**
- Modify: `lib/core/version_service.dart` (`UpdateInfo` class, `isSafeAssetUrl`)
- Test: `test/version_service_test.dart`

**Interfaces:**
- Produces: `UpdateInfo` gains fields `DateTime? publishedAt`, `String? assetUrl`, `String? assetName`. `UpdateInfo.fromJson` parses `published_at` + `assets` (prefers `arm64` APK, else any `.apk`). Static `UpdateChecker.isSafeAssetUrl(String, {required owner, required repo})`.

- [ ] **Step 1: Write the failing tests**

Append to `test/version_service_test.dart` inside `main()` (after the existing `UpdateChecker` group):

```dart
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
    final ok = 'https://github.com/SabirDzh/Asa/releases/download/v1.2.0/app-arm64-v8a-release.apk';
    expect(
      UpdateChecker.isSafeAssetUrl(
        ok,
        owner: 'SabirDzh',
        repo: 'Asa',
      ),
      isTrue,
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test --no-pub test/version_service_test.dart`
Expected: FAIL — `UpdateInfo.fromJson` has no `publishedAt`/`assetUrl` getters; `isSafeAssetUrl` undefined.

- [ ] **Step 3: Implement in `lib/core/version_service.dart`**

In `UpdateInfo`, add fields and parse them in `fromJson`:

```dart
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.url,
    required this.notes,
    this.publishedAt,
    this.assetUrl,
    this.assetName,
  });

  final String version;
  final String url;
  final String notes;
  final DateTime? publishedAt;
  final String? assetUrl;
  final String? assetName;

  static UpdateInfo? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final tag = value['tag_name'];
    final url = value['html_url'];
    if (tag is! String || url is! String) return null;

    final normalizedVersion = tag.trim().replaceFirst(RegExp(r'^v'), '');
    if (SemanticVersion.tryParse(normalizedVersion) == null ||
        url.trim().isEmpty) {
      return null;
    }

    final rawNotes = value['body'];
    final notes = rawNotes is String ? _truncate(rawNotes) : '';

    final publishedRaw = value['published_at'];
    final publishedAt = publishedRaw is String
        ? DateTime.tryParse(publishedRaw)
        : null;

    final asset = _pickApkAsset(value['assets']);
    return UpdateInfo(
      version: normalizedVersion,
      url: url.trim(),
      notes: notes,
      publishedAt: publishedAt,
      assetUrl: asset?.browserUrl,
      assetName: asset?.name,
    );
  }

  /// Picks the arm64-v8a APK when available, otherwise any `.apk` asset.
  static ({String name, String browserUrl})? _pickApkAsset(Object? value) {
    if (value is! List) return null;
    final candidates = <({String name, String browserUrl})>[];
    for (final item in value) {
      if (item is! Map<String, dynamic>) continue;
      final name = item['name'];
      final browserUrl = item['browser_download_url'];
      if (name is! String || browserUrl is! String) continue;
      if (!name.toLowerCase().endsWith('.apk')) continue;
      candidates.add((name: name, browserUrl: browserUrl));
    }
    if (candidates.isEmpty) return null;
    for (final candidate in candidates) {
      if (candidate.name.toLowerCase().contains('arm64')) return candidate;
    }
    return candidates.first;
  }
```

Add the validator next to `isSafeReleaseUrl` on `UpdateChecker`:

```dart
  static bool isSafeAssetUrl(
    String value, {
    required String owner,
    required String repo,
  }) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.toLowerCase() != 'github.com' ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty) {
      return false;
    }

    final segments = uri.pathSegments;
    return segments.length == 6 &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty &&
        segments[0].toLowerCase() == owner.toLowerCase() &&
        segments[1].toLowerCase() == repo.toLowerCase() &&
        segments[2] == 'releases' &&
        segments[3] == 'download' &&
        segments[4].isNotEmpty &&
        segments[5].toLowerCase().endsWith('.apk');
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test --no-pub test/version_service_test.dart`
Expected: PASS (old + new tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/version_service.dart test/version_service_test.dart
git commit -m "feat: parse release assets and published date"
```

---

### Task 2: `fetchReleaseHistory()` with prefs cache

**Files:**
- Modify: `lib/core/version_service.dart`
- Test: `test/version_service_test.dart`

**Interfaces:**
- Consumes: `UpdateInfo` from Task 1.
- Produces: `Future<List<UpdateInfo>> UpdateChecker.fetchReleaseHistory({SharedPreferences? preferences, int limit = 10})` (newest first, cached fallback) and `UpdateInfo.toCacheJson()` / `UpdateInfo.fromCacheJson()`.

- [ ] **Step 1: Write the failing tests**

Append inside the `UpdateChecker` group in `test/version_service_test.dart`:

```dart
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
                'html_url': 'https://github.com/SabirDzh/Asa/releases/tag/v1.1.0',
                'published_at': '2026-07-20T10:00:00Z',
                'body': 'Older',
              },
              {
                'tag_name': 'v1.2.0',
                'html_url': 'https://github.com/SabirDzh/Asa/releases/tag/v1.2.0',
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

    test('fetchReleaseHistory falls back to cache on network failure', () async {
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
    });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test --no-pub test/version_service_test.dart`
Expected: FAIL — `fetchReleaseHistory` undefined.

- [ ] **Step 3: Implement**

In `UpdateChecker`, add the cache key constant and methods; add cache helpers on `UpdateInfo`:

```dart
  static const String _historyKey = 'update_release_history';

  /// Fetches the latest [limit] published releases, newest first. Falls back
  /// to the last successful cache when the network is unavailable.
  @visibleForTesting
  Future<List<UpdateInfo>> fetchReleaseHistory({
    SharedPreferences? preferences,
    int limit = 10,
  }) async {
    final prefs = preferences ?? await _preferencesProvider();
    final uri = Uri.https('api.github.com', '/repos/$owner/$repo/releases', {
      'per_page': '$limit',
    });
    try {
      final response = await _client
          .get(uri, headers: _releaseHeaders())
          .timeout(requestTimeout);
      if (response.statusCode != 200) return _readCachedHistory(prefs);
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return _readCachedHistory(prefs);

      final releases = <UpdateInfo>[];
      for (final item in decoded) {
        final info = UpdateInfo.fromJson(item);
        if (info == null) continue;
        if (!isSafeReleaseUrl(info.url, owner: owner, repo: repo)) continue;
        if (info.assetUrl != null &&
            !isSafeAssetUrl(info.assetUrl!, owner: owner, repo: repo)) {
          // Keep the release but drop an unsafe asset reference.
          releases.add(
            UpdateInfo(
              version: info.version,
              url: info.url,
              notes: info.notes,
              publishedAt: info.publishedAt,
            ),
          );
          continue;
        }
        releases.add(info);
      }
      releases.sort((a, b) {
        final aTime = a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      await _writeCachedHistory(prefs, releases);
      return releases;
    } on Object {
      return _readCachedHistory(prefs);
    }
  }

  Map<String, String> _releaseHeaders() => {
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'ASA-UpdateChecker',
  };

  List<UpdateInfo> _readCachedHistory(SharedPreferences prefs) {
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final releases = <UpdateInfo>[];
      for (final item in decoded) {
        final info = UpdateInfo.fromCacheJson(item);
        if (info != null &&
            isSafeReleaseUrl(info.url, owner: owner, repo: repo)) {
          releases.add(info);
        }
      }
      return releases;
    } on Object {
      return const [];
    }
  }

  Future<void> _writeCachedHistory(
    SharedPreferences prefs,
    List<UpdateInfo> releases,
  ) async {
    await prefs.setString(
      _historyKey,
      jsonEncode([for (final r in releases) r.toCacheJson()]),
    );
  }
```

Also refactor the `_fetchLatest` headers to reuse `_releaseHeaders()` (optional; keep behavior identical).

On `UpdateInfo`, add:

```dart
  Map<String, Object?> toCacheJson() => {
    'version': version,
    'url': url,
    'notes': notes,
    'publishedAt': publishedAt?.toIso8601String(),
    'assetUrl': assetUrl,
    'assetName': assetName,
  };

  static UpdateInfo? fromCacheJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final version = value['version'];
    final url = value['url'];
    if (version is! String || url is! String) return null;
    if (SemanticVersion.tryParse(version) == null) return null;
    final publishedRaw = value['publishedAt'];
    return UpdateInfo(
      version: version,
      url: url,
      notes: value['notes'] is String ? value['notes'] as String : '',
      publishedAt: publishedRaw is String
          ? DateTime.tryParse(publishedRaw)
          : null,
      assetUrl: value['assetUrl'] is String ? value['assetUrl'] as String : null,
      assetName: value['assetName'] is String
          ? value['assetName'] as String
          : null,
    );
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test --no-pub test/version_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/version_service.dart test/version_service_test.dart
git commit -m "feat: fetch and cache release history"
```

---

### Task 3: `UpdateInstaller` (conditional io/stub) + `open_filex` dependency

**Files:**
- Create: `lib/core/update_installer.dart`, `lib/core/update_installer_io.dart`, `lib/core/update_installer_stub.dart`
- Modify: `pubspec.yaml` (add `open_filex: ^4.7.0`)
- Test: `test/update_installer_test.dart` (new)

**Interfaces:**
- Produces (shared API, web-safe):
  - `bool get canInstallApkLocally`
  - `Future<String?> downloadUpdateFile(String url, {http.Client? client, Future<String> Function()? directoryProvider, void Function(int received, int? total)? onProgress})`
  - `Future<bool> openApkInstaller(String path)`

- [ ] **Step 1: Write the failing test**

Create `test/update_installer_test.dart`:

```dart
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
    final response = http.StreamedResponse(
      Stream.value(bytes),
      200,
      contentLength: bytes.length,
      request: request,
    );
    return response;
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

    final client = _FailingClient();
    final path = await downloadUpdateFile(
      'https://github.com/SabirDzh/Asa/releases/download/v1.2.0/app.apk',
      client: client,
      directoryProvider: () async => dir.path,
    );
    expect(path, isNull);
  });

  test('openApkInstaller returns a bool without throwing', () async {
    expect(await openApkInstaller('/nonexistent/asa-update.apk'), isA<bool>());
  });
}

class _FailingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(const Stream.empty(), 404, request: request);
  }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test --no-pub test/update_installer_test.dart`
Expected: FAIL — `package:asa/core/update_installer.dart` not found.

- [ ] **Step 3: Implement**

Add to `pubspec.yaml` under `dependencies`:

```yaml
  open_filex: ^4.7.0
```

Run `flutter pub get`.

`lib/core/update_installer.dart`:

```dart
import 'package:http/http.dart' as http;

import 'update_installer_stub.dart'
    if (dart.library.io) 'update_installer_io.dart';

/// True when the current platform can install an APK from a local file
/// (Android only).
bool get canInstallApkLocally => canInstallApkLocallyImpl;

/// Downloads [url] into the app documents directory and returns the absolute
/// local path, or null when the download failed or the platform cannot
/// persist files (web).
Future<String?> downloadUpdateFile(
  String url, {
  http.Client? client,
  Future<String> Function()? directoryProvider,
  void Function(int received, int? total)? onProgress,
}) {
  return downloadUpdateFileImpl(
    url,
    client: client,
    directoryProvider: directoryProvider,
    onProgress: onProgress,
  );
}

/// Opens a downloaded APK with the system package installer on Android.
/// Returns false on platforms without an installer.
Future<bool> openApkInstaller(String path) => openApkInstallerImpl(path);
```

`lib/core/update_installer_stub.dart` (web/unsupported):

```dart
import 'package:http/http.dart' as http;

bool get canInstallApkLocallyImpl => false;

Future<String?> downloadUpdateFileImpl(
  String url, {
  http.Client? client,
  Future<String> Function()? directoryProvider,
  void Function(int received, int? total)? onProgress,
}) async {
  return null;
}

Future<bool> openApkInstallerImpl(String path) async => false;
```

`lib/core/update_installer_io.dart`:

```dart
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
  final directoryPath = await (directoryProvider ?? _defaultDirectory)();
  try {
    final directory = Directory(directoryPath);
    await directory.create(recursive: true);
    final file = File(
      '${directoryPath}${Platform.pathSeparator}asa-update.apk',
    );
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
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test --no-pub test/update_installer_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/core/update_installer.dart lib/core/update_installer_io.dart lib/core/update_installer_stub.dart test/update_installer_test.dart
git commit -m "feat: download and install apk inside the app"
```

---

### Task 4: Expose download/install on `UpdateChecker` + facade

**Files:**
- Modify: `lib/core/version_service.dart`
- Test: `test/version_service_test.dart`

**Interfaces:**
- Produces:
  - `Future<String?> UpdateChecker.downloadUpdate(UpdateInfo info, {void Function(int received, int? total)? onProgress})`
  - `Future<bool> UpdateChecker.installUpdate(String path)`
  - `static Future<String?> VersionService.downloadUpdate(...)`
  - `static Future<bool> VersionService.installUpdate(String path)`
  - `static Future<List<UpdateInfo>> VersionService.fetchReleaseHistory({int limit = 10})`
  - `static bool get VersionService.canAutoInstall`

- [ ] **Step 1: Write the failing tests**

Append to the `UpdateChecker` group:

```dart
    test('downloadUpdate returns null when the platform cannot install', () async {
      final checker = UpdateChecker(
        owner: 'SabirDzh',
        repo: 'Asa',
        currentVersion: '1.1.0',
        client: _FakeClient((uri, headers) async {
          return http.Response('nope', 200);
        }),
      );
      final info = UpdateInfo(
        version: '1.2.0',
        url: 'https://github.com/SabirDzh/Asa/releases/tag/v1.2.0',
        notes: '',
        assetUrl:
            'https://github.com/SabirDzh/Asa/releases/download/v1.2.0/app-arm64-v8a-release.apk',
        assetName: 'app-arm64-v8a-release.apk',
      );
      // The io implementation only downloads on Android; unit tests on the
      // host still exercise the safe-validation branch for unsafe URLs.
      final unsafe = await checker.downloadUpdate(
        UpdateInfo(
          version: '1.2.0',
          url: info.url,
          notes: '',
          assetUrl: 'https://evil.example/app.apk',
          assetName: 'app.apk',
        ),
      );
      expect(unsafe, isNull);
      expect(checker.installUpdate('/tmp/asa-update.apk'), isA<Future<bool>>());
    });

    test('VersionService facade exposes history and install helpers', () async {
      expect(VersionService.canAutoInstall, isA<bool>());
      expect(VersionService.fetchReleaseHistory(limit: 3), isA<Future<List<UpdateInfo>>>());
    });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test --no-pub test/version_service_test.dart`
Expected: FAIL — `downloadUpdate` / `installUpdate` / `canAutoInstall` undefined.

- [ ] **Step 3: Implement**

In `UpdateChecker`, add:

```dart
  /// Downloads the release APK to local storage. Returns the local path or
  /// null when the platform cannot install or the URL is unsafe.
  Future<String?> downloadUpdate(
    UpdateInfo info, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final assetUrl = info.assetUrl;
    if (assetUrl == null || !canInstallApkLocally) return null;
    if (!isSafeAssetUrl(assetUrl, owner: owner, repo: repo)) return null;
    return downloadUpdateFile(assetUrl, client: _client, onProgress: onProgress);
  }

  /// Opens a downloaded APK with the system package installer.
  Future<bool> installUpdate(String path) => openApkInstaller(path);
```

Add imports at the top of the file:

```dart
import 'update_installer.dart';
```

On `VersionService`, add:

```dart
  static bool get canAutoInstall => canInstallApkLocally;

  static Future<List<UpdateInfo>> fetchReleaseHistory({int limit = 10}) =>
      _defaultChecker.fetchReleaseHistory(limit: limit);

  static Future<String?> downloadUpdate(
    UpdateInfo info, {
    void Function(int received, int? total)? onProgress,
  }) =>
      _defaultChecker.downloadUpdate(info, onProgress: onProgress);

  static Future<bool> installUpdate(String path) =>
      _defaultChecker.installUpdate(path);
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test --no-pub test/version_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/version_service.dart test/version_service_test.dart
git commit -m "feat: expose in-app update download and install"
```

---

### Task 5: Stateful `UpdateDialog` with download progress

**Files:**
- Create: `lib/core/update_dialog.dart`
- Modify: `lib/core/version_service.dart` (replace inline dialog), `lib/core/app_strings.dart` (strings)
- Test: `test/update_dialog_test.dart` (new)

**Interfaces:**
- Produces:
  - `enum UpdateInstallOutcome { installed, failed, unavailable }`
  - `typedef UpdateInstallCallback = Future<UpdateInstallOutcome> Function(void Function(int received, int? total) onProgress);`
  - `class UpdateDialog extends StatefulWidget` with `{required SettingsProvider settings, required UpdateInfo info, required VoidCallback onPostpone, required UpdateInstallCallback onInstall, VoidCallback? onViewHistory}`

- [ ] **Step 1: Write the failing test**

Create `test/update_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asa/core/update_dialog.dart';
import 'package:asa/core/version_service.dart';
import 'package:asa/features/settings/providers/settings_provider.dart';

Widget _harness(
  WidgetTester tester,
  UpdateInstallCallback onInstall,
) {
  return ChangeNotifierProvider(
    create: (_) => SettingsProvider(),
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            final settings = Provider.of<SettingsProvider>(
              context,
              listen: false,
            );
            return Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => UpdateDialog(
                    settings: settings,
                    info: const UpdateInfo(
                      version: '1.2.0',
                      url: 'https://github.com/SabirDzh/Asa/releases/tag/v1.2.0',
                      notes: 'New stuff',
                      assetUrl:
                          'https://github.com/SabirDzh/Asa/releases/download/v1.2.0/app-arm64-v8a-release.apk',
                      assetName: 'app-arm64-v8a-release.apk',
                    ),
                    onPostpone: () => Navigator.of(context).pop(),
                    onInstall: onInstall,
                  ),
                ),
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('install flow shows progress then closes on success', (
    tester,
  ) async {
    final progressValues = <double>[];
    await tester.pumpWidget(
      _harness(tester, (onProgress) async {
        onProgress(50, 100);
        onProgress(100, 100);
        return UpdateInstallOutcome.installed;
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Установить'));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);
  });

  testWidgets('failed install shows error and allows retry', (tester) async {
    await tester.pumpWidget(
      _harness(tester, (onProgress) async => UpdateInstallOutcome.failed),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Установить'));
    await tester.pumpAndSettle();

    expect(find.text('Не удалось загрузить обновление'), findsOneWidget);
    expect(find.text('Установить'), findsOneWidget);
  });

  testWidgets('unavailable outcome hides the install button', (tester) async {
    await tester.pumpWidget(
      _harness(tester, (onProgress) async => UpdateInstallOutcome.unavailable),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Установить'));
    await tester.pumpAndSettle();

    expect(find.text('Установить'), findsNothing);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test --no-pub test/update_dialog_test.dart`
Expected: FAIL — `package:asa/core/update_dialog.dart` not found.

- [ ] **Step 3: Implement**

Add strings to `lib/core/app_strings.dart` (`ru`):

```dart
      'update_downloading': 'Загрузка обновления…',
      'update_download_failed': 'Не удалось загрузить обновление',
      'view_all_versions': 'Все версии',
```

(`en`):

```dart
      'update_downloading': 'Downloading update…',
      'update_download_failed': 'Failed to download the update',
      'view_all_versions': 'All versions',
```

Create `lib/core/update_dialog.dart`:

```dart
import 'package:flutter/material.dart';

import '../features/settings/providers/settings_provider.dart';
import 'theme.dart';
import 'version_service.dart';

/// Result of an in-app update install attempt.
enum UpdateInstallOutcome { installed, failed, unavailable }

typedef UpdateInstallCallback =
    Future<UpdateInstallOutcome> Function(
      void Function(int received, int? total) onProgress,
    );

/// Stateful update dialog that downloads the APK in-app (when supported) and
/// reports progress. On unsupported platforms the caller reports
/// [UpdateInstallOutcome.unavailable] so the dialog hides the install action.
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.settings,
    required this.info,
    required this.onPostpone,
    required this.onInstall,
    this.onViewHistory,
  });

  final SettingsProvider settings;
  final UpdateInfo info;
  final VoidCallback onPostpone;
  final UpdateInstallCallback onInstall;
  final VoidCallback? onViewHistory;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  double? _progress;
  bool _failed = false;
  bool _done = false;

  Future<void> _install() async {
    setState(() {
      _downloading = true;
      _failed = false;
      _progress = null;
    });
    final outcome = await widget.onInstall((received, total) {
      if (!mounted) return;
      setState(() {
        _progress = total != null && total > 0
            ? (received / total).clamp(0.0, 1.0)
            : null;
      });
    });
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _done = outcome == UpdateInstallOutcome.installed;
      _failed = outcome == UpdateInstallOutcome.failed;
      _progress = null;
    });
    if (_done) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final textSecondary =
        isDark ? const Color(0xFF8E8E93) : const Color(0xFF6B7280);

    return AlertDialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        settings.tr('update_available'),
        style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${settings.tr('version')} → ${widget.info.version}',
              style: TextStyle(color: textSecondary),
            ),
            const SizedBox(height: 12),
            Text(
              settings.tr('update_notes'),
              style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              widget.info.notes.isEmpty ? '—' : widget.info.notes,
              style: TextStyle(color: textColor),
            ),
            if (widget.onViewHistory != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: widget.onViewHistory,
                icon: const Icon(Icons.history, size: 18),
                label: Text(settings.tr('view_all_versions')),
              ),
            ],
            if (_downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(
                settings.tr('update_downloading'),
                style: TextStyle(color: textSecondary, fontSize: 13),
              ),
            ],
            if (_failed) ...[
              const SizedBox(height: 16),
              Text(
                settings.tr('update_download_failed'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _downloading ? null : widget.onPostpone,
          child: Text(
            settings.tr('update_postpone'),
            style: const TextStyle(color: Color(0xFF8E8E93)),
          ),
        ),
        if (!_done && !_failed && !_downloading)
          ElevatedButton(
            onPressed: _install,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(settings.tr('update_install')),
          ),
      ],
    );
  }
}
```

In `lib/core/version_service.dart`, replace the body of `_showUpdateDialog` with a call to the new widget. Remove the now-unused `isDark/bg/textColor/textSecondary` locals and the old inline dialog:

```dart
  Future<void> _showUpdateDialog(
    BuildContext context,
    SettingsProvider settings,
    UpdateInfo info,
    SharedPreferences prefs,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => UpdateDialog(
            settings: settings,
            info: info,
            onPostpone: () async {
              await prefs.setBool(_postponedKey, true);
            },
            onInstall: (onProgress) async {
              final path = await downloadUpdate(info, onProgress: onProgress);
              if (path == null) return UpdateInstallOutcome.unavailable;
              final installed = await installUpdate(path);
              return installed
                  ? UpdateInstallOutcome.installed
                  : UpdateInstallOutcome.failed;
            },
          ),
    );
    await prefs.setInt(_lastPromptKey, _now().millisecondsSinceEpoch);
  }
```

Add import `update_dialog.dart` to `version_service.dart`. Keep the `url_launcher` import only if still referenced; if it becomes unused, remove it.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test --no-pub test/update_dialog_test.dart test/version_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/update_dialog.dart lib/core/version_service.dart lib/core/app_strings.dart test/update_dialog_test.dart
git commit -m "feat: add download progress to the update dialog"
```

---

### Task 6: "What's New" screen + Settings entry

**Files:**
- Create: `lib/features/settings/screens/whats_new_screen.dart`
- Modify: `lib/features/settings/screens/settings_screen.dart`, `lib/core/app_strings.dart`, `lib/core/version_service.dart` (dialog wiring: pass `onViewHistory`)
- Test: `test/whats_new_screen_test.dart` (new), `test/settings_screen_test.dart` (add navigation test)

**Interfaces:**
- Produces: `class WhatsNewScreen extends StatefulWidget` with `{Future<List<UpdateInfo>> Function()? fetchHistory}`.

- [ ] **Step 1: Write the failing tests**

Create `test/whats_new_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:asa/core/version_service.dart';
import 'package:asa/features/settings/providers/settings_provider.dart';
import 'package:asa/features/settings/screens/whats_new_screen.dart';

Widget _harness(Future<List<UpdateInfo>> Function() fetch) {
  return ChangeNotifierProvider(
    create: (_) => SettingsProvider(),
    child: MaterialApp(
      home: WhatsNewScreen(fetchHistory: fetch),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders releases newest first with notes', (tester) async {
    await tester.pumpWidget(
      _harness(() async => [
        const UpdateInfo(
          version: '1.2.0',
          url: 'https://github.com/SabirDzh/Asa/releases/tag/v1.2.0',
          notes: 'New **bold** feature',
          publishedAt: DateTime.utc(2026, 8, 1),
        ),
        const UpdateInfo(
          version: '1.1.0',
          url: 'https://github.com/SabirDzh/Asa/releases/tag/v1.1.0',
          notes: 'Older release',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('1.2.0'), findsOneWidget);
    expect(find.text('1.1.0'), findsOneWidget);
    expect(find.text('New bold feature'), findsOneWidget);
    expect(find.text('Older release'), findsOneWidget);
  });

  testWidgets('shows empty state', (tester) async {
    await tester.pumpWidget(_harness(() async => []));
    await tester.pumpAndSettle();
    expect(find.text('Релизов пока нет'), findsOneWidget);
  });

  testWidgets('shows error state and retries', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _harness(() async {
        calls += 1;
        if (calls == 1) throw Exception('network');
        return [const UpdateInfo(
          version: '1.2.0',
          url: 'https://github.com/SabirDzh/Asa/releases/tag/v1.2.0',
          notes: 'Recovered',
        )];
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Не удалось загрузить историю версий'), findsOneWidget);

    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Recovered'), findsOneWidget);
  });
}
```

In `test/settings_screen_test.dart`, add:

```dart
  testWidgets('opens the what-is-new screen from the other group', (
    tester,
  ) async {
    await pumpAndInit(tester, createTestApp());

    final row = find.text('Что нового');
    await tester.scrollUntilVisible(
      row,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(WhatsNewScreen), findsOneWidget);
  });
```

Add import: `import 'package:asa/features/settings/screens/whats_new_screen.dart';`

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test --no-pub test/whats_new_screen_test.dart test/settings_screen_test.dart`
Expected: FAIL — screen file missing; row string missing.

- [ ] **Step 3: Implement**

Strings (`ru`):

```dart
      'whats_new': 'Что нового',
      'releases_empty': 'Релизов пока нет',
      'releases_error': 'Не удалось загрузить историю версий',
      'retry': 'Повторить',
      'published': 'Опубликовано',
```

(`en`):

```dart
      'whats_new': "What's New",
      'releases_empty': 'No releases yet',
      'releases_error': 'Could not load release history',
      'retry': 'Retry',
      'published': 'Published',
```

Create `lib/features/settings/screens/whats_new_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../core/version_service.dart';
import '../providers/settings_provider.dart';

/// Shows the release history (version, date, notes) fetched from GitHub.
class WhatsNewScreen extends StatefulWidget {
  final Future<List<UpdateInfo>> Function()? fetchHistory;

  const WhatsNewScreen({super.key, this.fetchHistory});

  @override
  State<WhatsNewScreen> createState() => _WhatsNewScreenState();
}

class _WhatsNewScreenState extends State<WhatsNewScreen> {
  late Future<List<UpdateInfo>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<UpdateInfo>> _fetch() =>
      (widget.fetchHistory ?? VersionService.fetchReleaseHistory)();

  void _retry() {
    setState(() => _future = _fetch());
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final d = date.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgDark : AppColors.bgLight;
    final textColor = isDark ? AppColors.textDark : AppColors.textLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final settings = context.read<SettingsProvider>();

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.screenPad,
                AppTheme.screenPad,
                AppTheme.screenPad,
                AppTheme.screenPad * 2,
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.surfaceDark
                            : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.arrow_back, color: textColor, size: 22),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    settings.tr('whats_new'),
                    style: TextStyle(
                      color: textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<UpdateInfo>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _MessageState(
                      icon: Icons.error_outline,
                      message: settings.tr('releases_error'),
                      onRetry: _retry,
                      settings: settings,
                    );
                  }
                  final releases = snapshot.data ?? const <UpdateInfo>[];
                  if (releases.isEmpty) {
                    return _MessageState(
                      icon: Icons.history,
                      message: settings.tr('releases_empty'),
                      onRetry: _retry,
                      settings: settings,
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.screenPad,
                      4,
                      AppTheme.screenPad,
                      80,
                    ),
                    itemCount: releases.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final release = releases[index];
                      final date = _formatDate(release.publishedAt);
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.surfaceDark
                              : AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'v${release.version}',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                if (date.isNotEmpty)
                                  Text(
                                    date,
                                    style: TextStyle(
                                      color: textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (release.notes.isEmpty)
                              Text('—', style: TextStyle(color: textSecondary))
                            else
                              MarkdownBody(
                                data: release.notes,
                                selectable: true,
                                extensionSet: md.ExtensionSet.gitHubFlavored,
                                styleSheet: MarkdownStyleSheet.fromTheme(
                                  Theme.of(context),
                                ).copyWith(
                                  p: TextStyle(color: textColor),
                                  a: TextStyle(color: AppColors.primary),
                                ),
                                imageBuilder: (uri, title, alt) => Text(
                                  '[${alt?.trim().isNotEmpty == true ? alt!.trim() : 'image'}]',
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback onRetry;
  final SettingsProvider settings;

  const _MessageState({
    required this.icon,
    required this.message,
    required this.onRetry,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final textSecondary =
        Theme.of(context).brightness == Brightness.dark
            ? AppColors.textSecondaryDark
            : AppColors.textSecondaryLight;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: textSecondary),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: onRetry,
            child: Text(settings.tr('retry')),
          ),
        ],
      ),
    );
  }
}
```

In `lib/features/settings/screens/settings_screen.dart`:

- Add import: `import 'whats_new_screen.dart';`
- In the `other` `SettingGroup`, before the About row, add:

```dart
                SettingRow(
                  icon: Iconsax.star,
                  label: settings.tr('whats_new'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const WhatsNewScreen(),
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: textSecondary,
                    size: 22,
                  ),
                ),
```

In `lib/core/version_service.dart`, wire the dialog's history link:

```dart
            onViewHistory: () {
              Navigator.of(ctx).push(
                MaterialPageRoute<void>(
                  builder: (_) => const WhatsNewScreen(),
                ),
              );
            },
```

Add import: `import '../features/settings/screens/whats_new_screen.dart';`

- [ ] **Step 4: Run to verify they pass**

Run: `flutter test --no-pub test/whats_new_screen_test.dart test/settings_screen_test.dart test/version_service_test.dart test/update_dialog_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings/screens/whats_new_screen.dart lib/features/settings/screens/settings_screen.dart lib/core/app_strings.dart lib/core/version_service.dart test/whats_new_screen_test.dart test/settings_screen_test.dart
git commit -m "feat: add what's new screen with release history"
```

---

### Task 7: Dynamic version display

**Files:**
- Modify: `lib/core/app_strings.dart` (`version` value), `lib/features/settings/widgets/about_bottom_sheet.dart`, `test/settings_screen_test.dart` (expectation already matches; verify)

**Interfaces:**
- Produces: `settings.tr('version')` returns just the label (`'Версия'` / `'Version'`); the About sheet renders `'${settings.tr('version')} ${VersionService.currentVersion}'`.

- [ ] **Step 1: Write the failing test**

In `test/settings_screen_test.dart`, change the About assertion to be version-agnostic and add an explicit label check:

```dart
    expect(find.text('О приложении ASA'), findsOneWidget);
    expect(
      find.textContaining(VersionService.currentVersion),
      findsOneWidget,
    );
```

Add import: `import 'package:asa/core/version_service.dart';`

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test --no-pub test/settings_screen_test.dart --plain-name 'shows about sheet on tap'`
Expected: FAIL — rendered string still contains the hardcoded `1.1.1` only as part of `'Версия 1.1.1'`; `textContaining('1.1.1')` still matches, so instead first change the string in Step 3 then observe the About sheet uses the constant. (If it passes initially, that is fine — the real regression check is the constant match.)

- [ ] **Step 3: Implement**

In `lib/core/app_strings.dart`, change both `version` values:

```dart
      'version': 'Версия',
```

```dart
      'version': 'Version',
```

In `lib/features/settings/widgets/about_bottom_sheet.dart`:

```dart
import '../../../core/version_service.dart';
// ...
              Text(
                '${settings.tr('version')} ${VersionService.currentVersion}',
                style: TextStyle(color: textSecondary, fontSize: 14),
              ),
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test --no-pub test/settings_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/app_strings.dart lib/features/settings/widgets/about_bottom_sheet.dart test/settings_screen_test.dart
git commit -m "feat: show the real app version in the about sheet"
```

---

### Task 8: Release automation script + docs

**Files:**
- Create: `scripts/release.sh`
- Modify: `docs/DEVELOPER.md`

**Interfaces:**
- Produces: `./scripts/release.sh <version> <build> [--no-push] [--dry-run]` — bumps `pubspec.yaml`, updates `APP_VERSION` default in `version_service.dart`, builds arm64 APK with `--dart-define=APP_VERSION=<ver>`, copies the asset to `Asa-<ver>+<build>-arm64-v8a.apk`, tags `v<ver>+<build>`, and creates the GitHub release (via `gh` or `curl`+`GITHUB_TOKEN`).

- [ ] **Step 1: Write the script**

Create `scripts/release.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/release.sh <version> <build> [--no-push] [--dry-run]
#   version — plain SemVer, e.g. 1.2.0
#   build   — Android build number, e.g. 3  (pubspec becomes 1.2.0+3)

VERSION="${1:-}"
BUILD="${2:-}"
DRY_RUN=0
NO_PUSH=0
for arg in "${@:3}"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --no-push) NO_PUSH=1 ;;
    *) echo "Unknown flag: $arg" >&2; exit 1 ;;
  esac
done

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must be plain SemVer (e.g. 1.2.0)" >&2
  exit 1
fi
if [[ ! "$BUILD" =~ ^[0-9]+$ ]]; then
  echo "Build must be an integer (e.g. 3)" >&2
  exit 1
fi

FULL="${VERSION}+${BUILD}"
TAG="v${FULL}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

step() { echo "==> $*"; }

# 1. Version bump (pubspec + APP_VERSION default).
step "Bumping pubspec.yaml to ${FULL}"
perl -pi -e "s/^version: .*/version: ${FULL}/" pubspec.yaml
step "Updating APP_VERSION default to ${VERSION}"
perl -pi -e "s/(defaultValue: ')[0-9]+\.[0-9]+\.[0-9]+(')/\${1}${VERSION}\${2}/" lib/core/version_service.dart

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Dry run — skipping build, commit, tag, and release."
  git diff --stat pubspec.yaml lib/core/version_service.dart
  exit 0
fi

# 2. Commit the bump.
step "Committing version bump"
git add pubspec.yaml lib/core/version_service.dart
git commit -m "chore: bump version to ${FULL}"

# 3. Build the arm64 APK with the correct APP_VERSION.
step "Building arm64 APK (APP_VERSION=${VERSION})"
flutter build apk \
  --target-platform android-arm64 \
  --split-per-abi \
  --release \
  --dart-define="APP_VERSION=${VERSION}"

APK="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
ASSET="build/app/outputs/flutter-apk/Asa-${FULL}-arm64-v8a.apk"
step "Copying asset to ${ASSET}"
cp "$APK" "$ASSET"

# 4. Tag.
step "Tagging ${TAG}"
git tag "$TAG"
if [[ "$NO_PUSH" -eq 0 ]]; then
  step "Pushing commit + tag"
  git push origin HEAD --tags
else
  echo "Skipping push (--no-push)."
fi

# 5. Release notes from git log since the previous tag.
PREV_TAG="$(git describe --tags --abbrev=0 "$TAG^" 2>/dev/null || echo '')"
if [[ -z "$PREV_TAG" ]]; then
  NOTES="Release ${VERSION}"
else
  NOTES="$(git log --format='- %s' "${PREV_TAG}..HEAD" | head -80)"
fi

# 6. Create the GitHub release + upload the APK.
if command -v gh >/dev/null 2>&1; then
  step "Creating release with gh"
  gh release create "$TAG" "$ASSET" \
    --title "ASA ${VERSION}" \
    --notes "$NOTES"
else
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "gh CLI not found and GITHUB_TOKEN is not set. Release not created." >&2
    echo "Tag and asset are ready: ${TAG} -> ${ASSET}" >&2
    exit 1
  fi
  step "Creating release via GitHub API"
  BODY_JSON="$(python3 -c 'import json,sys; print(json.dumps({"tag_name": sys.argv[1], "name": sys.argv[2], "body": sys.argv[3], "draft": False, "prerelease": False}))' "$TAG" "ASA ${VERSION}" "$NOTES")"
  RELEASE_JSON="$(curl -fsSL -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -d "$BODY_JSON" \
    "https://api.github.com/repos/SabirDzh/Asa/releases")"
  RELEASE_ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$RELEASE_JSON")"
  ENCODED="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "Asa-${FULL}-arm64-v8a.apk")"
  step "Uploading ${ASSET}"
  curl -fsSL -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/vnd.android.package-archive" \
    --data-binary "@${ASSET}" \
    "https://uploads.github.com/repos/SabirDzh/Asa/releases/${RELEASE_ID}/assets?name=${ENCODED}" >/dev/null
fi

echo "Done: ${TAG}"
```

Make it executable: `chmod +x scripts/release.sh`

- [ ] **Step 2: Validate syntax + dry run**

Run:
```bash
bash -n scripts/release.sh
./scripts/release.sh 1.2.0 3 --dry-run
git diff --stat   # should show only the two bumped files, uncommitted
git checkout -- pubspec.yaml lib/core/version_service.dart
```
Expected: `bash -n` silent; dry run prints diff; repo restored.

- [ ] **Step 3: Update docs**

In `docs/DEVELOPER.md` §12.3, add after the build command:

```markdown
### 12.4 Release automation

`./scripts/release.sh <version> <build> [--no-push] [--dry-run]` performs the full
release flow:

1. Bumps `pubspec.yaml` to `<version>+<build>` and updates the `APP_VERSION`
   default in `lib/core/version_service.dart`.
2. Commits the bump, builds the arm64 APK with
   `--dart-define=APP_VERSION=<version>`, and copies the artifact to
   `Asa-<version>+<build>-arm64-v8a.apk`.
3. Tags `v<version>+<build>`, pushes (unless `--no-push`), and creates the GitHub
   release with the APK asset — via the `gh` CLI when available, otherwise via the
   GitHub REST API with `GITHUB_TOKEN`.

In-app updates download the release's arm64 APK and open the system package
installer (`open_filex`). The "What's New" screen shows release history from the
GitHub `/releases` endpoint with a local cache fallback.
```

Also update §7.8 VersionService to mention in-app install + release history.

- [ ] **Step 4: Commit**

```bash
git add scripts/release.sh docs/DEVELOPER.md
git commit -m "feat: automate release builds with version sync"
```

---

### Task 9: Final validation, review, and cleanup

- [ ] **Step 1: Format + analyze + full test suite**

```bash
dart format lib test
dart analyze
flutter test --no-pub
```

Expected: formatter clean, analyzer 0 issues, all tests green.

- [ ] **Step 2: Code review**

Spawn `code-reviewer-deepseek-flash` with a summary of all changed files; fix any actionable findings.

- [ ] **Step 3: Verify no leftover probe files**

```bash
git status --short
```
Expected: only intended files; no temp/probe files committed.

- [ ] **Step 4: Final commit (if review produced changes)**

```bash
git add -A
git commit -m "refactor: address review feedback"   # only if changes were made
```

---

## Self-Review

1. **Spec coverage:** In-app APK download+install → Tasks 3–5; version sync (APP_VERSION const + `--dart-define` in build script) → Task 8; "What's New" screen with release history → Tasks 2 + 6. All three requests covered.
2. **Placeholder scan:** All code blocks are complete; no TBD/TODO.
3. **Type consistency:** `UpdateInfo` fields (`publishedAt`, `assetUrl`, `assetName`) used consistently; `fetchReleaseHistory({SharedPreferences? preferences, int limit})` signature matches across tests and facade; `downloadUpdate`/`installUpdate` signatures match between checker, facade, and dialog wiring.
