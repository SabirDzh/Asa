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
  bool _unavailable = false;
  bool _done = false;

  Future<void> _install() async {
    setState(() {
      _downloading = true;
      _failed = false;
      _unavailable = false;
      _progress = null;
    });
    UpdateInstallOutcome outcome;
    try {
      outcome = await widget.onInstall((received, total) {
        if (!mounted) return;
        setState(() {
          _progress =
              total != null && total > 0
                  ? (received / total).clamp(0.0, 1.0).toDouble()
                  : null;
        });
      });
    } on Object {
      // An unexpected install failure must never strand the dialog in the
      // downloading state; fall back to the retry state.
      outcome = UpdateInstallOutcome.failed;
    }
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _done = outcome == UpdateInstallOutcome.installed;
      _failed = outcome == UpdateInstallOutcome.failed;
      _unavailable = outcome == UpdateInstallOutcome.unavailable;
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
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${settings.tr('version')} ${VersionService.currentVersion} → ${widget.info.version}',
              style: TextStyle(color: textSecondary),
            ),
            const SizedBox(height: 12),
            Text(
              settings.tr('update_notes'),
              style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight:
                    (MediaQuery.of(context).size.height * 0.25).clamp(
                      120.0,
                      150.0,
                    ),
              ),
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    widget.info.notes.isEmpty ? '—' : widget.info.notes,
                    style: TextStyle(color: textColor, height: 1.35),
                  ),
                ),
              ),
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
            if (_unavailable) ...[
              const SizedBox(height: 16),
              Text(
                settings.tr('update_unavailable_platform'),
                style: TextStyle(color: textSecondary),
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
        if (!_done && !_unavailable && !_downloading)
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
