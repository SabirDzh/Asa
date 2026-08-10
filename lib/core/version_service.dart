import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../features/settings/providers/settings_provider.dart';
import '../features/settings/screens/whats_new_screen.dart';
import 'logger_service.dart';
import 'update_dialog.dart';
import 'update_installer.dart';

/// Public facade kept for the existing splash-screen integration.
class VersionService {
  static const String owner = 'SabirDzh';
  static const String repo = 'Asa';
  // The build pipeline can provide the version with --dart-define=APP_VERSION.
  static const String currentVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.1.3',
  );

  static final UpdateChecker _defaultChecker = UpdateChecker(
    owner: owner,
    repo: repo,
    currentVersion: currentVersion,
  );

  /// Checks for a newer stable GitHub release without blocking app startup.
  static Future<void> checkAndPrompt(
    BuildContext context,
    SettingsProvider settings,
  ) {
    return _defaultChecker.checkAndPrompt(context, settings);
  }

  @visibleForTesting
  static bool isNewer(String latest, String current) =>
      SemanticVersion.isNewer(latest, current);

  @visibleForTesting
  static bool isSafeReleaseUrl(
    String value, {
    String owner = VersionService.owner,
    String repo = VersionService.repo,
  }) => UpdateChecker.isSafeReleaseUrl(value, owner: owner, repo: repo);

  /// True when this platform can install an APK from a local file.
  static bool get canAutoInstall => canInstallApkLocally;

  /// Fetches the latest [limit] published releases, newest first, with a
  /// cached fallback when the network is unavailable.
  static Future<List<UpdateInfo>> fetchReleaseHistory({int limit = 10}) =>
      _defaultChecker.fetchReleaseHistory(limit: limit);

  /// Downloads the release APK to local storage. Returns the local path or
  /// null when the platform cannot install or the URL is unsafe.
  static Future<String?> downloadUpdate(
    UpdateInfo info, {
    void Function(int received, int? total)? onProgress,
    Future<String> Function()? directoryProvider,
  }) => _defaultChecker.downloadUpdate(
    info,
    onProgress: onProgress,
    directoryProvider: directoryProvider,
  );

  /// Opens a downloaded APK with the system package installer.
  static Future<bool> installUpdate(String path) =>
      _defaultChecker.installUpdate(path);

  /// Shows the update prompt dialog directly for [info].
  static Future<void> showUpdateDialog(
    BuildContext context,
    SettingsProvider settings,
    UpdateInfo info,
  ) => _defaultChecker.showUpdateDialogDirect(context, settings, info);
}

/// Handles release fetching independently from the dialog UI.
///
/// The injected [client], [now] and [preferencesProvider] make this class
/// deterministic in unit tests and avoid coupling network failures to Flutter
/// widget tests. A single instance can be kept for the application lifetime.
class UpdateChecker {
  UpdateChecker({
    required this.owner,
    required this.repo,
    required this.currentVersion,
    http.Client? client,
    DateTime Function()? now,
    Future<SharedPreferences> Function()? preferencesProvider,
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now,
       _preferencesProvider =
           preferencesProvider ?? SharedPreferences.getInstance;

  final String owner;
  final String repo;
  final String currentVersion;
  final http.Client _client;
  final DateTime Function() _now;
  final Future<SharedPreferences> Function() _preferencesProvider;

  static const Duration checkInterval = Duration(hours: 12);
  static const Duration errorRetryInterval = Duration(hours: 1);
  static const Duration postponeInterval = Duration(hours: 24);
  static const Duration requestTimeout = Duration(seconds: 5);

  static const String _lastAttemptKey = 'update_last_attempted_at';
  static const String _lastSuccessKey = 'update_last_checked_at';
  static const String _lastPromptKey = 'update_last_prompted_at';
  static const String _postponedKey = 'update_postponed';
  static const String _etagKey = 'update_release_etag';
  static const String _cachedVersionKey = 'update_release_version';
  static const String _cachedUrlKey = 'update_release_url';
  static const String _cachedNotesKey = 'update_release_notes';
  static const String _cachedPublishedAtKey = 'update_release_published_at';
  static const String _cachedAssetUrlKey = 'update_release_asset_url';
  static const String _cachedAssetNameKey = 'update_release_asset_name';
  static const String _historyKey = 'update_release_history';
  static const int _maxNotesLength = 20 * 1024;

  Future<_FetchResult>? _inFlight;
  bool _isPresenting = false;

  /// Runs the throttled check and shows the existing update dialog when
  /// appropriate. Network errors are intentionally swallowed: updates are
  /// optional and must never prevent the app from opening.
  Future<void> checkAndPrompt(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    try {
      await _checkAndPrompt(context, settings);
    } on Object catch (error, stackTrace) {
      // Update checks are optional. A storage/plugin failure must never become
      // an unhandled async error or block the first usable screen.
      LoggerService.instance.w(
        'Background update check failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _checkAndPrompt(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    if (owner.trim().isEmpty || repo.trim().isEmpty) return;

    final prefs = await _preferencesProvider();
    final now = _now();
    final activeRequest = _inFlight;
    late final _FetchResult result;
    if (activeRequest != null) {
      // A newer caller may have a mounted context even when the original
      // caller disappeared while the request was in flight.
      result = await activeRequest;
    } else {
      final lastAttempt = _readTime(prefs, _lastAttemptKey);
      final lastSuccess = _readTime(prefs, _lastSuccessKey);
      final interval = lastSuccess == null ? errorRetryInterval : checkInterval;
      if (lastAttempt != null &&
          _isWithinInterval(now, lastAttempt, interval)) {
        return;
      }

      await prefs.setInt(_lastAttemptKey, now.millisecondsSinceEpoch);
      result = await _fetchWithDeduplication(prefs);
    }
    if (!result.succeeded) return;
    await prefs.setInt(_lastSuccessKey, _now().millisecondsSinceEpoch);

    final info = result.info;
    if (info == null ||
        !SemanticVersion.isNewer(info.version, currentVersion)) {
      await prefs.setBool(_postponedKey, false);
      return;
    }

    final lastPrompt = _readTime(prefs, _lastPromptKey);
    final promptInterval =
        (prefs.getBool(_postponedKey) ?? false)
            ? postponeInterval
            : checkInterval;
    if (lastPrompt != null &&
        _isWithinInterval(now, lastPrompt, promptInterval)) {
      return;
    }

    // Acquire the presentation lock only after confirming that this context is
    // still mounted. This avoids suppressing a future prompt when splash has
    // already been replaced by another route.
    if (!context.mounted || _isPresenting) return;
    _isPresenting = true;
    try {
      await _showUpdateDialog(context, settings, info, prefs);
    } finally {
      _isPresenting = false;
    }
  }

  /// Downloads the release APK to local storage. Returns the local path or
  /// null when the platform cannot install or the URL is unsafe.
  Future<String?> downloadUpdate(
    UpdateInfo info, {
    void Function(int received, int? total)? onProgress,
    Future<String> Function()? directoryProvider,
  }) async {
    final assetUrl = info.assetUrl;
    if (assetUrl == null || !canInstallApkLocally) return null;
    if (!isSafeAssetUrl(assetUrl, owner: owner, repo: repo)) return null;
    return downloadUpdateFile(
      assetUrl,
      client: _client,
      onProgress: onProgress,
      directoryProvider: directoryProvider,
    );
  }

  /// Opens a downloaded APK with the system package installer.
  Future<bool> installUpdate(String path) => openApkInstaller(path);

  Future<_FetchResult> _fetchWithDeduplication(SharedPreferences prefs) async {
    final existing = _inFlight;
    if (existing != null) return existing;

    final future = _fetchLatest(prefs);
    _inFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight, future)) _inFlight = null;
    }
  }

  static bool _isWithinInterval(
    DateTime now,
    DateTime previous,
    Duration interval,
  ) {
    // A clock rollback should not disable update checks until the wall clock
    // catches up; treat a future persisted timestamp as expired instead.
    if (now.isBefore(previous)) return false;
    return now.difference(previous) < interval;
  }

  /// Fetches and validates the latest release, bypassing throttling.
  ///
  /// This is intentionally public so repository-level tests can verify the
  /// HTTP contract without rendering a dialog.
  @visibleForTesting
  Future<UpdateInfo?> fetchLatest({SharedPreferences? preferences}) async {
    final prefs = preferences ?? await _preferencesProvider();
    final result = await _fetchLatest(prefs);
    return result.info;
  }

  Map<String, String> _releaseHeaders() => {
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'ASA-UpdateChecker',
  };

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
          releases.add(_withoutAsset(info));
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

  List<UpdateInfo> _readCachedHistory(SharedPreferences prefs) {
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final releases = <UpdateInfo>[];
      for (final item in decoded) {
        final info = UpdateInfo.fromCacheJson(item);
        if (info == null ||
            !isSafeReleaseUrl(info.url, owner: owner, repo: repo)) {
          continue;
        }
        if (info.assetUrl != null &&
            !isSafeAssetUrl(info.assetUrl!, owner: owner, repo: repo)) {
          // Defense in depth: the cache is user-modifiable storage, so
          // re-validate the asset URL on read and drop unsafe references.
          releases.add(_withoutAsset(info));
          continue;
        }
        releases.add(info);
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
      jsonEncode([for (final release in releases) release.toCacheJson()]),
    );
  }

  Future<_FetchResult> _fetchLatest(SharedPreferences prefs) async {
    final uri = Uri.https(
      'api.github.com',
      '/repos/$owner/$repo/releases/latest',
    );
    final headers = _releaseHeaders();
    final etag = prefs.getString(_etagKey);
    if (etag != null && etag.isNotEmpty) headers['If-None-Match'] = etag;

    try {
      final response = await _client
          .get(uri, headers: headers)
          .timeout(requestTimeout);

      if (response.statusCode == 304) {
        final cached = _readCachedInfo(prefs);
        // A stale ETag without a complete cache must not be interpreted as a
        // successful "no update" response. Retry later without poisoning the
        // cache or suppressing future checks.
        if (cached == null) {
          await prefs.remove(_etagKey);
          return const _FetchResult.failure();
        }
        return _FetchResult.success(cached);
      }
      if (response.statusCode != 200) return const _FetchResult.failure();

      final info = UpdateInfo.fromJson(jsonDecode(response.body));
      if (info == null ||
          !isSafeReleaseUrl(info.url, owner: owner, repo: repo)) {
        return const _FetchResult.failure();
      }

      final responseEtag = response.headers['etag'];
      if (responseEtag != null && responseEtag.isNotEmpty) {
        await prefs.setString(_etagKey, responseEtag);
      }
      await _writeCachedInfo(prefs, info);
      return _FetchResult.success(info);
    } on Object {
      return const _FetchResult.failure();
    }
  }

  static bool isSafeReleaseUrl(
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
    return segments.length == 5 &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty &&
        segments[0].toLowerCase() == owner.toLowerCase() &&
        segments[1].toLowerCase() == repo.toLowerCase() &&
        segments[2] == 'releases' &&
        segments[3] == 'tag' &&
        segments[4].isNotEmpty;
  }

  /// Returns a copy of [info] without its asset reference. Used whenever an
  /// asset URL fails validation so the release itself is still shown.
  static UpdateInfo _withoutAsset(UpdateInfo info) => UpdateInfo(
    version: info.version,
    url: info.url,
    notes: info.notes,
    publishedAt: info.publishedAt,
  );

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

  UpdateInfo? _readCachedInfo(SharedPreferences prefs) {
    final version = prefs.getString(_cachedVersionKey);
    final url = prefs.getString(_cachedUrlKey);
    if (version == null ||
        url == null ||
        !isSafeReleaseUrl(url, owner: owner, repo: repo)) {
      return null;
    }
    final publishedRaw = prefs.getString(_cachedPublishedAtKey);
    final assetUrl = prefs.getString(_cachedAssetUrlKey);
    final assetName = prefs.getString(_cachedAssetNameKey);
    final base = UpdateInfo(
      version: version,
      url: url,
      notes: prefs.getString(_cachedNotesKey) ?? '',
      publishedAt:
          publishedRaw == null ? null : DateTime.tryParse(publishedRaw),
    );
    if (assetUrl != null &&
        !isSafeAssetUrl(assetUrl, owner: owner, repo: repo)) {
      return base;
    }
    return UpdateInfo(
      version: base.version,
      url: base.url,
      notes: base.notes,
      publishedAt: base.publishedAt,
      assetUrl: assetUrl,
      assetName: assetName,
    );
  }

  Future<void> _writeCachedInfo(
    SharedPreferences prefs,
    UpdateInfo info,
  ) async {
    await prefs.setString(_cachedVersionKey, info.version);
    await prefs.setString(_cachedUrlKey, info.url);
    await prefs.setString(_cachedNotesKey, info.notes);
    if (info.publishedAt != null) {
      await prefs.setString(
        _cachedPublishedAtKey,
        info.publishedAt!.toIso8601String(),
      );
    }
    if (info.assetUrl != null) {
      await prefs.setString(_cachedAssetUrlKey, info.assetUrl!);
    }
    if (info.assetName != null) {
      await prefs.setString(_cachedAssetNameKey, info.assetName!);
    }
  }

  static DateTime? _readTime(SharedPreferences prefs, String key) {
    final value = prefs.getInt(key);
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  /// Presents the update dialog for [info] on demand.
  Future<void> showUpdateDialogDirect(
    BuildContext context,
    SettingsProvider settings,
    UpdateInfo info,
  ) async {
    final prefs = await _preferencesProvider();
    if (!context.mounted || _isPresenting) return;
    _isPresenting = true;
    try {
      await _showUpdateDialog(context, settings, info, prefs);
    } finally {
      _isPresenting = false;
    }
  }

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
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
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
}

class _FetchResult {
  const _FetchResult._(this.succeeded, this.info);

  const _FetchResult.success(UpdateInfo? info) : this._(true, info);
  const _FetchResult.failure() : this._(false, null);

  final bool succeeded;
  final UpdateInfo? info;
}

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
    final publishedAt =
        publishedRaw is String ? DateTime.tryParse(publishedRaw) : null;

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
      publishedAt:
          publishedRaw is String ? DateTime.tryParse(publishedRaw) : null,
      assetUrl:
          value['assetUrl'] is String ? value['assetUrl'] as String : null,
      assetName:
          value['assetName'] is String ? value['assetName'] as String : null,
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

  static String _truncate(String value) {
    final codePoints = value.runes.toList(growable: false);
    if (codePoints.length <= UpdateChecker._maxNotesLength) return value;
    return '${String.fromCharCodes(codePoints.take(UpdateChecker._maxNotesLength))}\n…';
  }
}

/// A strict SemVer 2.0.0 value with Git tag-friendly leading `v` support.
class SemanticVersion implements Comparable<SemanticVersion> {
  SemanticVersion._(this.major, this.minor, this.patch, this.preRelease);

  final int major;
  final int minor;
  final int patch;
  final List<String> preRelease;

  static final RegExp _pattern = RegExp(
    r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
    r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'
    r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
  );

  static SemanticVersion? tryParse(String value) {
    final match = _pattern.firstMatch(value.trim());
    if (match == null) return null;
    final pre = match.group(4);
    if (pre != null) {
      for (final identifier in pre.split('.')) {
        final isNumeric = RegExp(r'^\d+$').hasMatch(identifier);
        if (isNumeric && identifier.length > 1 && identifier.startsWith('0')) {
          return null;
        }
      }
    }
    return SemanticVersion._(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      pre?.split('.') ?? const [],
    );
  }

  static bool isNewer(String latest, String current) {
    final latestVersion = tryParse(latest);
    final currentVersion = tryParse(current);
    if (latestVersion == null || currentVersion == null) return false;
    return latestVersion.compareTo(currentVersion) > 0;
  }

  @override
  int compareTo(SemanticVersion other) {
    final core = _compareInts(major, other.major);
    if (core != 0) return core;
    final minorComparison = _compareInts(minor, other.minor);
    if (minorComparison != 0) return minorComparison;
    final patchComparison = _compareInts(patch, other.patch);
    if (patchComparison != 0) return patchComparison;
    if (preRelease.isEmpty && other.preRelease.isNotEmpty) return 1;
    if (preRelease.isNotEmpty && other.preRelease.isEmpty) return -1;
    for (var i = 0; i < preRelease.length && i < other.preRelease.length; i++) {
      final left = preRelease[i];
      final right = other.preRelease[i];
      if (left == right) continue;
      final leftIsNumber = RegExp(r'^\d+$').hasMatch(left);
      final rightIsNumber = RegExp(r'^\d+$').hasMatch(right);
      if (leftIsNumber && rightIsNumber) {
        final leftNumber = left.replaceFirst(RegExp(r'^0+'), '');
        final rightNumber = right.replaceFirst(RegExp(r'^0+'), '');
        final normalizedLeft = leftNumber.isEmpty ? '0' : leftNumber;
        final normalizedRight = rightNumber.isEmpty ? '0' : rightNumber;
        if (normalizedLeft.length != normalizedRight.length) {
          return normalizedLeft.length.compareTo(normalizedRight.length);
        }
        return normalizedLeft.compareTo(normalizedRight);
      }
      if (leftIsNumber) return -1;
      if (rightIsNumber) return 1;
      return left.compareTo(right);
    }
    return _compareInts(preRelease.length, other.preRelease.length);
  }

  static int _compareInts(int left, int right) => left.compareTo(right);
}
