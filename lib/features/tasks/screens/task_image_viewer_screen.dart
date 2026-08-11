import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/task_attachment_service.dart';
import '../../../core/theme.dart';
import '../models/task_info_block.dart';

/// Opens a stored task image in a dedicated, zoomable page.
Future<bool> openTaskImageViewer(
  BuildContext context,
  TaskAttachment attachment, {
  Future<List<int>?> Function(String path)? bytesLoader,
}) async {
  if (attachment.type != TaskAttachmentType.image || !context.mounted) {
    return false;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder:
          (_) => TaskImageViewerScreen(
            attachment: attachment,
            bytesLoader: bytesLoader,
          ),
    ),
  );
  return true;
}

class TaskImageViewerScreen extends StatefulWidget {
  final TaskAttachment attachment;
  final Future<List<int>?> Function(String path)? bytesLoader;

  const TaskImageViewerScreen({
    super.key,
    required this.attachment,
    this.bytesLoader,
  });

  @override
  State<TaskImageViewerScreen> createState() => _TaskImageViewerScreenState();
}

class _TaskImageViewerScreenState extends State<TaskImageViewerScreen> {
  late final Future<List<int>?> _bytesFuture;

  @override
  void initState() {
    super.initState();
    _bytesFuture = (widget.bytesLoader ?? readStoredTaskAttachmentBytes)(
      widget.attachment.value,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? AppColors.bgDark : AppColors.bgLight;
    final title =
        widget.attachment.name.trim().isEmpty
            ? 'Image'
            : widget.attachment.name;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('close-task-image-viewer'),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: FutureBuilder<List<int>?>(
        future: _bytesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final bytes = snapshot.data;
          if (bytes == null || taskImageMimeFromBytes(bytes) == null) {
            return const Center(
              child: Icon(Icons.broken_image_outlined, size: 56),
            );
          }

          return Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Image.memory(
                Uint8List.fromList(bytes),
                // Keep decoded memory bounded for large or untrusted images.
                cacheWidth: 4096,
                cacheHeight: 4096,
                fit: BoxFit.contain,
                errorBuilder:
                    (_, _, _) =>
                        const Icon(Icons.broken_image_outlined, size: 56),
              ),
            ),
          );
        },
      ),
    );
  }
}
