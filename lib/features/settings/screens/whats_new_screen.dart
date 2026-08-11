import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme.dart';
import '../../../core/version_service.dart';
import '../providers/settings_provider.dart';

/// Shows the release history (version, date, notes) fetched from GitHub,
/// with a pinned bottom button to check for updates or install an available update.
class WhatsNewScreen extends StatefulWidget {
  final Future<List<UpdateInfo>> Function()? fetchHistory;

  const WhatsNewScreen({super.key, this.fetchHistory});

  @override
  State<WhatsNewScreen> createState() => _WhatsNewScreenState();
}

class _WhatsNewScreenState extends State<WhatsNewScreen> {
  late Future<List<UpdateInfo>> _future;
  bool _checking = false;
  DateTime? _lastManualCheckTime;
  static const Duration _manualCheckCooldown = Duration(seconds: 15);
  static const int _pageSize = 15;
  static const double _bottomButtonHeight = 100.0;
  int _visibleCount = _pageSize;
  DateTime? _installedAssetTime;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    _future = _fetch();
    _loadInstalledAssetTime();
  }

  Future<void> _loadInstalledAssetTime() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(UpdateChecker.installedAssetTimeKey);
    if (ms != null && mounted) {
      setState(() {
        _installedAssetTime = DateTime.fromMillisecondsSinceEpoch(ms);
      });
    }
  }

  Future<List<UpdateInfo>> _fetch() =>
      (widget.fetchHistory ?? VersionService.fetchReleaseHistory)();

  @override
  void dispose() {
    // This page owns its status messages. Remove a visible SnackBar before
    // the route is disposed so its page-specific bottom margin cannot leak
    // into the next screen through the root messenger.
    _messengerKey.currentState?.clearSnackBars();
    super.dispose();
  }

  void _showStatusSnackBar(
    BuildContext context,
    String message, {
    required Duration duration,
  }) {
    final bottomMargin = MediaQuery.of(context).padding.bottom + 96;
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(bottom: bottomMargin, left: 16, right: 16),
        duration: duration,
      ),
    );
  }

  void _retry() {
    setState(() {
      _visibleCount = _pageSize;
      _future = _fetch();
    });
  }

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
      _showStatusSnackBar(context, msg, duration: const Duration(seconds: 2));
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
        if (VersionService.isUpdateAvailable(
          rel,
          installedAssetUpdatedAt: _installedAssetTime,
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
          _showStatusSnackBar(
            context,
            msg,
            duration: const Duration(seconds: 3),
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

  Widget _buildBottomAction(
    BuildContext context,
    SettingsProvider settings,
    List<UpdateInfo> releases,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgDark : AppColors.bgLight;

    UpdateInfo? newerRelease;
    for (final rel in releases) {
      if (VersionService.isUpdateAvailable(
        rel,
        installedAssetUpdatedAt: _installedAssetTime,
      )) {
        newerRelease = rel;
        break;
      }
    }

    Widget button;
    if (newerRelease != null) {
      final label = settings
          .tr('install_update_version')
          .replaceAll('{version}', newerRelease.version);

      button = SizedBox(
        width: double.infinity,
        height: 56,
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 2,
          ),
        ),
      );
    } else {
      button = SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton.icon(
          onPressed: _checking ? null : () => _manualCheck(settings),
          icon:
              _checking
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
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.55),
            disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );
    }

    final bottomPadding = MediaQuery.of(context).padding.bottom;
    // Wrap in a gradient so the button stays readable over list content.
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bg.withValues(alpha: 0), bg.withValues(alpha: 0.85), bg],
          stops: const [0.0, 0.35, 0.65],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppTheme.screenPad,
          20,
          AppTheme.screenPad,
          (bottomPadding > 0 ? bottomPadding + 24 : 40),
        ),
        child: button,
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

    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              // ── Main scrollable content ───────────────────────────────────
              Column(
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
                            child: Icon(
                              Icons.arrow_back,
                              color: textColor,
                              size: 22,
                            ),
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
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
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
                          return Center(
                            child: _MessageState(
                              icon: Icons.history,
                              message: settings.tr('releases_empty'),
                              onRetry: _retry,
                              settings: settings,
                            ),
                          );
                        }
                        final hasMore = releases.length > _visibleCount;
                        final displayCount =
                            hasMore ? _visibleCount : releases.length;

                        return ListView.separated(
                          // Extra bottom padding so the last item isn't hidden
                          // behind the floating action button.
                          padding: EdgeInsets.fromLTRB(
                            AppTheme.screenPad,
                            4,
                            AppTheme.screenPad,
                            _bottomButtonHeight +
                                MediaQuery.of(context).padding.bottom,
                          ),
                          itemCount: displayCount + (hasMore ? 1 : 0),
                          separatorBuilder:
                              (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            if (hasMore && index == displayCount) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Center(
                                  child: OutlinedButton.icon(
                                    key: const ValueKey('whats-new-load-more'),
                                    onPressed: () {
                                      setState(() {
                                        _visibleCount += _pageSize;
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.expand_more_rounded,
                                      size: 20,
                                    ),
                                    label: Text(
                                      settings.tr('load_more'),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color:
                                            isDark
                                                ? AppColors.textDark
                                                : AppColors.textLight,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      side: BorderSide(
                                        color:
                                            isDark
                                                ? AppColors.textSecondaryDark
                                                    .withValues(alpha: 0.3)
                                                : AppColors.textSecondaryLight
                                                    .withValues(alpha: 0.3),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }
                            final release = releases[index];
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
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
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
                                    Text(
                                      '—',
                                      style: TextStyle(color: textSecondary),
                                    )
                                  else
                                    MarkdownBody(
                                      data: release.notes,
                                      selectable: true,
                                      extensionSet:
                                          md.ExtensionSet.gitHubFlavored,
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

              // ── Floating action button (no solid background block) ────────
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: FutureBuilder<List<UpdateInfo>>(
                  future: _future,
                  builder: (context, snapshot) {
                    return _buildBottomAction(
                      context,
                      settings,
                      snapshot.data ?? const [],
                    );
                  },
                ),
              ),
            ],
          ),
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
