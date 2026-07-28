import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/settings/providers/settings_provider.dart';
import 'theme.dart';

/// GitHub release version checker.
///
/// Replace [owner] and [repo] with the actual GitHub values before shipping.
/// The dialog is shown at most once every 24 hours after the user presses
/// "Postpone".
class VersionService {
  static const String owner = 'SabirDzh';
  static const String repo = 'Asa';
  static const String currentVersion = '1.1.0';

  static const String _lastPromptKey = 'update_last_prompted_at';
  /// Default interval between automatic update checks.
  static const Duration _checkInterval = Duration(hours: 12);
  /// Interval after the user postpones/reminds-later an update.
  static const Duration _postponeInterval = Duration(hours: 24);

  /// Fetches the latest GitHub release and, if it is newer than the current
  /// version and enough time has passed since the last prompt, shows an update
  /// dialog.
  ///
  /// Does nothing when [owner] or [repo] are empty.
  static Future<void> checkAndPrompt(BuildContext context, SettingsProvider settings) async {
    if (owner.isEmpty || repo.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final lastPrompted = prefs.getInt(_lastPromptKey) ?? 0;
    final lastPromptedAt = DateTime.fromMillisecondsSinceEpoch(lastPrompted);
    final interval = (prefs.getBool('update_postponed') ?? false)
        ? _postponeInterval
        : _checkInterval;
    if (DateTime.now().difference(lastPromptedAt) < interval) {
      return;
    }

    final info = await _fetchLatest();
    if (info == null || info.version.trim().isEmpty || !_isNewer(info.version, currentVersion)) {
      // No newer version: record the check so the next one happens
      // after the normal 12-hour interval.
      await prefs.setInt(_lastPromptKey, DateTime.now().millisecondsSinceEpoch);
      await prefs.setBool('update_postponed', false);
      return;
    }

    if (!context.mounted) return;
    _showUpdateDialog(context, settings, info);
  }

  static Future<UpdateInfo?> _fetchLatest() async {
    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$owner/$repo/releases/latest',
      );
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return UpdateInfo(
        version: (data['tag_name'] as String? ?? '').replaceFirst('v', ''),
        url: data['html_url'] as String? ?? '',
        notes: data['body'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  static bool _isNewer(String latest, String current) {
    final latestParts = _toVersionParts(latest);
    final currentParts = _toVersionParts(current);
    for (int i = 0; i < 3; i++) {
      final l = i < latestParts.length ? latestParts[i] : 0;
      final c = i < currentParts.length ? currentParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  /// Parses a version string like "1.2.0", "v1.2.0", "1.2.0-beta+build" into
  /// its numeric semver parts. Non-numeric segments and pre-release/build
  /// metadata are ignored so that comparison focuses on major/minor/patch.
  static List<int> _toVersionParts(String version) {
    final clean = version
        .replaceFirst('v', '')
        .split('-')
        .first
        .split('+')
        .first;
    return clean
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
  }

  static void _showUpdateDialog(
    BuildContext context,
    SettingsProvider settings,
    UpdateInfo info,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFFFFFFF);
    final textColor = isDark ? Colors.white : Colors.black;
    final textSecondary = isDark ? const Color(0xFF8E8E93) : const Color(0xFF6B7280);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
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
                '${settings.tr('version')} → ${info.version}',
                style: TextStyle(color: textSecondary),
              ),
              const SizedBox(height: 12),
              Text(
                settings.tr('update_notes'),
                style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
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
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt(
                _lastPromptKey,
                DateTime.now().millisecondsSinceEpoch,
              );
              await prefs.setBool('update_postponed', true);
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
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt(
                _lastPromptKey,
                DateTime.now().millisecondsSinceEpoch,
              );
              await prefs.setBool('update_postponed', false);
              final uri = Uri.parse(info.url);
              if (await canLaunchUrl(uri)) {
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
  }
}

class UpdateInfo {
  final String version;
  final String url;
  final String notes;

  UpdateInfo({required this.version, required this.url, required this.notes});
}
