import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/settings/providers/settings_provider.dart';
import 'logger_service.dart';
import 'theme.dart';

/// Public facade kept for the existing splash-screen integration.
class VersionService {
  static const String owner = 'SabirDzh';
  static const String repo = 'Asa';
  // The build pipeline can provide the version with --dart-define=APP_VERSION.
  static const String currentVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.1.1',
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

  Future<_FetchResult> _fetchLatest(SharedPreferences prefs) async {
    final uri = Uri.https(
      'api.github.com',
      '/repos/$owner/$repo/releases/latest',
    );
    final headers = <String, String>{
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'ASA-UpdateChecker',
    };
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

  UpdateInfo? _readCachedInfo(SharedPreferences prefs) {
    final version = prefs.getString(_cachedVersionKey);
    final url = prefs.getString(_cachedUrlKey);
    if (version == null ||
        url == null ||
        !isSafeReleaseUrl(url, owner: owner, repo: repo)) {
      return null;
    }
    return UpdateInfo(
      version: version,
      url: url,
      notes: prefs.getString(_cachedNotesKey) ?? '',
    );
  }

  Future<void> _writeCachedInfo(
    SharedPreferences prefs,
    UpdateInfo info,
  ) async {
    await prefs.setString(_cachedVersionKey, info.version);
    await prefs.setString(_cachedUrlKey, info.url);
    await prefs.setString(_cachedNotesKey, info.notes);
  }

  static DateTime? _readTime(SharedPreferences prefs, String key) {
    final value = prefs.getInt(key);
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<void> _showUpdateDialog(
    BuildContext context,
    SettingsProvider settings,
    UpdateInfo info,
    SharedPreferences prefs,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final textSecondary =
        isDark ? const Color(0xFF8E8E93) : const Color(0xFF6B7280);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
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
                    '${settings.tr('version')} → ${info.version}',
                    style: TextStyle(color: textSecondary),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    settings.tr('update_notes'),
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    info.notes.isEmpty ? '—' : info.notes,
                    style: TextStyle(color: textColor),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await prefs.setBool(_postponedKey, true);
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop();
                },
                child: Text(
                  settings.tr('update_postpone'),
                  style: const TextStyle(color: Color(0xFF8E8E93)),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  await prefs.setBool(_postponedKey, false);
                  final uri = Uri.tryParse(info.url);
                  if (uri != null &&
                      isSafeReleaseUrl(info.url, owner: owner, repo: repo) &&
                      await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop();
                },
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
  });

  final String version;
  final String url;
  final String notes;

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
    return UpdateInfo(
      version: normalizedVersion,
      url: url.trim(),
      notes: notes,
    );
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
