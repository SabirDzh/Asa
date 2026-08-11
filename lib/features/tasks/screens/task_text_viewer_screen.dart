import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/task_attachment_service.dart';
import '../../../core/task_attachment_validation.dart' as attachment_validation;
import '../../../core/description_markdown.dart';
import '../../../core/app_strings.dart';
import '../../../core/theme.dart';
import '../../browser/screens/in_app_browser_screen.dart';
import '../models/task_info_block.dart';

const int kMaxTaskTextViewerBytes = 2 * 1024 * 1024;

const _textExtensions = <String>{'txt', 'md', 'json', 'csv', 'xml', 'log'};

bool isTaskTextAttachment(TaskAttachment attachment) {
  if (attachment.type != TaskAttachmentType.file) return false;
  return _textExtensions.contains(
    attachment_validation.taskAttachmentExtension(attachment.name),
  );
}

Future<bool> openTaskTextViewer(
  BuildContext context,
  TaskAttachment attachment, {
  Future<List<int>?> Function(String path)? bytesLoader,
}) async {
  if (!isTaskTextAttachment(attachment) || !context.mounted) return false;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder:
          (_) => TaskTextViewerScreen(
            attachment: attachment,
            bytesLoader: bytesLoader,
          ),
    ),
  );
  return true;
}

class TaskTextViewerScreen extends StatefulWidget {
  final TaskAttachment attachment;
  final Future<List<int>?> Function(String path)? bytesLoader;

  const TaskTextViewerScreen({
    super.key,
    required this.attachment,
    this.bytesLoader,
  });

  @override
  State<TaskTextViewerScreen> createState() => _TaskTextViewerScreenState();
}

class _TaskTextViewerScreenState extends State<TaskTextViewerScreen> {
  late final Future<_LoadedText?> _contentFuture;

  @override
  void initState() {
    super.initState();
    _contentFuture = _loadText();
  }

  Future<_LoadedText?> _loadText() async {
    final loader =
        widget.bytesLoader ??
        (path) => readStoredTaskAttachmentBytes(
          path,
          maxBytes: kMaxTaskTextViewerBytes,
        );
    final bytes = await loader(widget.attachment.value);
    if (bytes == null ||
        bytes.isEmpty ||
        bytes.length > kMaxTaskTextViewerBytes) {
      return null;
    }
    try {
      final text = utf8.decode(bytes, allowMalformed: false);
      return _LoadedText(
        text:
            widget.attachment.name.toLowerCase().endsWith('.json')
                ? _prettyJson(text)
                : text,
      );
    } on FormatException {
      return null;
    }
  }

  String _prettyJson(String value) {
    try {
      final decoded = jsonDecode(value);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } on Object {
      return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? AppColors.bgDark : AppColors.bgLight;
    final title = attachment_validation.attachmentDisplayName(
      widget.attachment.name,
    );
    String tr(String key) =>
        AppStrings.get(key, Localizations.localeOf(context).languageCode);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('close-task-text-viewer'),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          FutureBuilder<_LoadedText?>(
            future: _contentFuture,
            builder: (context, snapshot) {
              if (snapshot.data == null) return const SizedBox.shrink();
              return IconButton(
                key: const ValueKey('copy-task-text'),
                tooltip: tr('viewer_copy'),
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: snapshot.data!.text),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(tr('viewer_copied'))));
                },
                icon: const Icon(Icons.copy_outlined),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<_LoadedText?>(
        future: _contentFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final content = snapshot.data;
          if (content == null) {
            return const Center(
              child: Icon(Icons.description_outlined, size: 56),
            );
          }
          final isMarkdown =
              attachment_validation.taskAttachmentExtension(
                widget.attachment.name,
              ) ==
              'md';
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child:
                isMarkdown
                    ? DescriptionBody(
                      key: const ValueKey('task-text-content'),
                      text: content.text,
                      format: DescriptionFormat.markdown,
                      attachments: const [],
                      onAttachmentTap: (_) {},
                      onExternalLinkTap:
                          (href, {title}) =>
                              openTaskLink(context, href, title: title),
                    )
                    : SelectableText(
                      content.text,
                      key: const ValueKey('task-text-content'),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                      ),
                    ),
          );
        },
      ),
    );
  }
}

class _LoadedText {
  final String text;

  const _LoadedText({required this.text});
}
