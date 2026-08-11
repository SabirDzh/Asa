import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../../core/app_strings.dart';
import '../../../core/task_attachment_service.dart';
import '../../../core/task_attachment_validation.dart' as attachment_validation;
import '../../../core/theme.dart';
import '../models/task_info_block.dart';

const int kMaxTaskPdfViewerBytes = 10 * 1024 * 1024;

bool isTaskPdfAttachment(TaskAttachment attachment) {
  return attachment.type == TaskAttachmentType.file &&
      attachment_validation.taskAttachmentExtension(attachment.name) == 'pdf';
}

Future<bool> openTaskPdfViewer(
  BuildContext context,
  TaskAttachment attachment, {
  Future<List<int>?> Function(String path)? bytesLoader,
}) async {
  if (!isTaskPdfAttachment(attachment) || !context.mounted) return false;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder:
          (_) => TaskPdfViewerScreen(
            attachment: attachment,
            bytesLoader: bytesLoader,
          ),
    ),
  );
  return true;
}

class TaskPdfViewerScreen extends StatefulWidget {
  final TaskAttachment attachment;
  final Future<List<int>?> Function(String path)? bytesLoader;
  final Future<bool> Function(TaskAttachment attachment)? openExternal;
  final Future<bool> Function(TaskAttachment attachment)? shareFile;

  const TaskPdfViewerScreen({
    super.key,
    required this.attachment,
    this.bytesLoader,
    this.openExternal,
    this.shareFile,
  });

  @override
  State<TaskPdfViewerScreen> createState() => _TaskPdfViewerScreenState();
}

class _TaskPdfViewerScreenState extends State<TaskPdfViewerScreen> {
  late final Future<PdfControllerPinch?> _controllerFuture;
  bool _actionBusy = false;
  PdfControllerPinch? _controller;
  int _currentPage = 1;
  int _pageCount = 0;
  String? _documentError;

  String _tr(String key) =>
      AppStrings.get(key, Localizations.localeOf(context).languageCode);

  @override
  void initState() {
    super.initState();
    _controllerFuture = _createController();
  }

  Future<PdfControllerPinch?> _createController() async {
    final loader =
        widget.bytesLoader ??
        (path) => readStoredTaskAttachmentBytes(
          path,
          maxBytes: kMaxTaskPdfViewerBytes,
        );
    final bytes = await loader(widget.attachment.value);
    if (bytes == null ||
        bytes.length < 5 ||
        bytes.length > kMaxTaskPdfViewerBytes ||
        !_hasPdfSignature(bytes)) {
      return null;
    }

    final controller = PdfControllerPinch(
      document: PdfDocument.openData(Uint8List.fromList(bytes)),
    );
    if (!mounted) {
      controller.dispose();
      return null;
    }
    _controller = controller;
    return controller;
  }

  Future<void> _openExternally() async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final opened = await (widget.openExternal ?? openTaskAttachment)(
        widget.attachment,
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_tr('viewer_external_open_failed'))),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_tr('viewer_external_open_failed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _share() async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final shared = await (widget.shareFile ?? shareTaskAttachment)(
        widget.attachment,
      );
      if (!shared && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_tr('viewer_share_failed'))));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_tr('viewer_share_failed'))));
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  bool _hasPdfSignature(List<int> bytes) {
    return bytes.length >= 5 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46 &&
        bytes[4] == 0x2D;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? AppColors.bgDark : AppColors.bgLight;
    final title = attachment_validation.attachmentDisplayName(
      widget.attachment.name,
    );

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('close-task-pdf-viewer'),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const ValueKey('open-task-pdf-external'),
            tooltip: _tr('viewer_open_external'),
            onPressed: _actionBusy ? null : _openExternally,
            icon: const Icon(Icons.open_in_new),
          ),
          IconButton(
            key: const ValueKey('share-task-pdf'),
            tooltip: _tr('viewer_share'),
            onPressed: _actionBusy ? null : _share,
            icon: const Icon(Icons.share_outlined),
          ),
          if (_pageCount > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('$_currentPage / $_pageCount'),
              ),
            ),
        ],
      ),
      body: FutureBuilder<PdfControllerPinch?>(
        future: _controllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final controller = snapshot.data;
          if (controller == null || _documentError != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.picture_as_pdf_outlined,
                      size: 56,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _documentError ?? _tr('viewer_pdf_unavailable'),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return PdfViewPinch(
            key: const ValueKey('task-pdf-content'),
            controller: controller,
            onDocumentLoaded: (document) {
              if (!mounted) return;
              setState(() => _pageCount = document.pagesCount);
            },
            onPageChanged: (page) {
              if (!mounted) return;
              setState(() => _currentPage = page);
            },
            onDocumentError: (_) {
              if (!mounted) return;
              setState(() {
                _pageCount = 0;
                _documentError = _tr('viewer_pdf_error');
              });
            },
            backgroundDecoration: BoxDecoration(color: background),
            padding: 12,
          );
        },
      ),
    );
  }
}
