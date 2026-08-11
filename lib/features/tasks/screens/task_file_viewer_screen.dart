import 'package:flutter/material.dart';

import '../../../core/app_strings.dart';
import '../../../core/task_attachment_service.dart';
import '../../../core/task_attachment_validation.dart' as attachment_validation;
import '../../../core/theme.dart';
import '../models/task_info_block.dart';

String taskFileViewerKind(TaskAttachment attachment) {
  if (attachment.type != TaskAttachmentType.file) return 'file';
  final extension = attachment_validation.taskAttachmentExtension(
    attachment.name,
  );
  return switch (extension) {
    'docx' || 'xlsx' || 'pptx' => 'office',
    'zip' => 'archive',
    _ => 'file',
  };
}

Future<bool> openTaskFileFallback(
  BuildContext context,
  TaskAttachment attachment,
) async {
  if (attachment.type != TaskAttachmentType.file || !context.mounted) {
    return false;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => TaskFileViewerScreen(attachment: attachment),
    ),
  );
  return true;
}

class TaskFileViewerScreen extends StatefulWidget {
  final TaskAttachment attachment;
  final Future<bool> Function(TaskAttachment attachment)? openExternal;
  final Future<bool> Function(TaskAttachment attachment)? shareFile;

  const TaskFileViewerScreen({
    super.key,
    required this.attachment,
    this.openExternal,
    this.shareFile,
  });

  @override
  State<TaskFileViewerScreen> createState() => _TaskFileViewerScreenState();
}

class _TaskFileViewerScreenState extends State<TaskFileViewerScreen> {
  bool _busy = false;
  String? _error;

  String _tr(String key) =>
      AppStrings.get(key, Localizations.localeOf(context).languageCode);

  Future<void> _openExternally() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final opened = await (widget.openExternal ?? openTaskAttachment)(
        widget.attachment,
      );
      if (!opened && mounted) {
        setState(() => _error = _tr('viewer_external_open_failed'));
      }
    } on Object {
      if (mounted) setState(() => _error = _tr('viewer_external_open_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final shared = await (widget.shareFile ?? shareTaskAttachment)(
        widget.attachment,
      );
      if (!shared && mounted) {
        setState(() => _error = _tr('viewer_share_failed'));
      }
    } on Object {
      if (mounted) setState(() => _error = _tr('viewer_share_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? AppColors.bgDark : AppColors.bgLight;
    final title = attachment_validation.attachmentDisplayName(
      widget.attachment.name,
    );
    final kind = taskFileViewerKind(widget.attachment);
    final kindLabel = switch (kind) {
      'office' => _tr('viewer_office_file'),
      'archive' => _tr('viewer_archive_file'),
      _ => _tr('viewer_generic_file'),
    };

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('close-task-file-viewer'),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                kind == 'office'
                    ? Icons.description_outlined
                    : kind == 'archive'
                    ? Icons.folder_zip_outlined
                    : Icons.insert_drive_file_outlined,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(kindLabel, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(_tr('viewer_external_hint'), textAlign: TextAlign.center),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('open-task-file-external'),
                  onPressed: _busy ? null : _openExternally,
                  icon: const Icon(Icons.open_in_new),
                  label: Text(_tr('viewer_open_external')),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('share-task-file'),
                  onPressed: _busy ? null : _share,
                  icon: const Icon(Icons.share_outlined),
                  label: Text(_tr('viewer_share')),
                ),
              ),
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
