import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../core/version_service.dart';
import '../providers/settings_provider.dart';

/// Shows the release history (version, date, notes) fetched from GitHub,
/// with a button to check for updates or install an available update.
class WhatsNewScreen extends StatefulWidget {
  final Future<List<UpdateInfo>> Function()? fetchHistory;

  const WhatsNewScreen({super.key, this.fetchHistory});

  @override
  State<WhatsNewScreen> createState() => _WhatsNewScreenState();
}

class _WhatsNewScreenState extends State<WhatsNewScreen> {
  late Future<List<UpdateInfo>> _future;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<UpdateInfo>> _fetch() =>
      (widget.fetchHistory ?? VersionService.fetchReleaseHistory)();

  void _retry() {
    setState(() {
      _future = _fetch();
    });
  }

  DateTime? _lastManualCheckTime;
  static const Duration _manualCheckCooldown = Duration(seconds: 15);

  Future<void> _manualCheck(SettingsProvider settings) async {
    final now = DateTime.now();
    if (_lastManualCheckTime != null &&
        now.difference(_lastManualCheckTime!) < _manualCheckCooldown) {
      final remaining =
          _manualCheckCooldown.inSeconds -
          now.difference(_lastManualCheckTime!).inSeconds;
      final msg = settings
          .tr('check_cooldown_message')
          .replaceAll('{seconds}', '$remaining');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
      return;
    }
    _lastManualCheckTime = now;

    setState(() {
      _checking = true;
    });
    try {
      final list = await _fetch();
      if (!mounted) return;
      setState(() {
        _future = Future.value(list);
        _checking = false;
      });

      UpdateInfo? newerRelease;
      for (final rel in list) {
        if (SemanticVersion.isNewer(
          rel.version,
          VersionService.currentVersion,
        )) {
          newerRelease = rel;
          break;
        }
      }

      if (newerRelease != null) {
        if (mounted) {
          VersionService.showUpdateDialog(context, settings, newerRelease);
        }
      } else {
        if (mounted) {
          final msg = settings
              .tr('up_to_date_message')
              .replaceAll('{version}', VersionService.currentVersion);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _checking = false;
        });
      }
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final d = date.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  Widget _buildTopAction(
    BuildContext context,
    SettingsProvider settings,
    List<UpdateInfo> releases,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    UpdateInfo? newerRelease;
    for (final rel in releases) {
      if (SemanticVersion.isNewer(
        rel.version,
        VersionService.currentVersion,
      )) {
        newerRelease = rel;
        break;
      }
    }

    if (newerRelease != null) {
      final label = settings
          .tr('install_update_version')
          .replaceAll('{version}', newerRelease.version);

      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () {
            VersionService.showUpdateDialog(context, settings, newerRelease!);
          },
          icon: const Icon(Icons.system_update_alt_rounded, size: 20),
          label: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 2,
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _checking ? null : () => _manualCheck(settings),
        icon: _checking
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh_rounded, size: 20),
        label: Text(
          _checking
              ? settings.tr('checking_updates')
              : settings.tr('check_for_updates'),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.textDark : AppColors.textLight,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: BorderSide(
            color:
                isDark
                    ? AppColors.textSecondaryDark.withValues(alpha: 0.3)
                    : AppColors.textSecondaryLight.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
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
                AppTheme.screenPad * 1.5,
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            isDark
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
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.screenPad,
                        4,
                        AppTheme.screenPad,
                        80,
                      ),
                      children: [
                        _buildTopAction(context, settings, releases),
                        const SizedBox(height: 32),
                        _MessageState(
                          icon: Icons.history,
                          message: settings.tr('releases_empty'),
                          onRetry: _retry,
                          settings: settings,
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.screenPad,
                      4,
                      AppTheme.screenPad,
                      80,
                    ),
                    itemCount: releases.length + 1,
                    separatorBuilder: (_, index) =>
                        index == 0 ? const SizedBox.shrink() : const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _buildTopAction(context, settings, releases);
                      }
                      final release = releases[index - 1];
                      final date = _formatDate(release.publishedAt);
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color:
                              isDark
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
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                if (date.isNotEmpty)
                                  Text(
                                    '${settings.tr('published')} $date',
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
                                imageBuilder:
                                    (uri, title, alt) => Text(
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
