import 'package:flutter/material.dart';

import '../../../core/description_document.dart';
import '../../../core/description_markdown.dart';
import '../../../core/description_render_context.dart';
import '../../../core/drag_close_sheet.dart';
import '../../../core/theme.dart';
import '../models/task_info_block.dart';

class DescriptionPreview extends StatelessWidget {
  final String text;
  final DescriptionFormat format;
  final List<TaskAttachment> attachments;
  final VoidCallback onTap;
  final DescriptionAttachmentTap onAttachmentTap;
  final DescriptionExternalLinkTap? onExternalLinkTap;
  final DescriptionRenderContext? renderContext;
  final Color textColor;
  final String semanticsLabel;

  const DescriptionPreview({
    super.key,
    required this.text,
    required this.format,
    required this.attachments,
    required this.onTap,
    required this.onAttachmentTap,
    required this.onExternalLinkTap,
    this.renderContext,
    required this.textColor,
    required this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();
    final isLong = trimmed.runes.length > kDescriptionPreviewLength;

    final child =
        isLong
            ? Text(
              descriptionPreview(trimmed),
              key: const ValueKey('description-preview-text'),
              style: TextStyle(color: textColor),
            )
            : format == DescriptionFormat.plainText
            ? Text(trimmed, style: TextStyle(color: textColor))
            : DescriptionBody(
              text: trimmed,
              format: format,
              attachments: attachments,
              onAttachmentTap: onAttachmentTap,
              onExternalLinkTap: onExternalLinkTap,
              renderContext: renderContext,
            );

    return Semantics(
      button: true,
      label: semanticsLabel,
      child: InkWell(
        key: const ValueKey('description-preview'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(4), child: child),
      ),
    );
  }
}

Future<void> showFullDescriptionSheet(
  BuildContext context, {
  required String text,
  required DescriptionFormat format,
  required List<TaskAttachment> attachments,
  required String title,
  required DescriptionAttachmentTap onAttachmentTap,
  required DescriptionExternalLinkTap? onExternalLinkTap,
  DescriptionRenderContext? renderContext,
  String? highlightBlockId,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    enableDrag: false,
    builder:
        (ctx) => DragToCloseSheet(
          trackScrollableDrag: true,
          child: DescriptionFullSheet(
            text: text,
            format: format,
            attachments: attachments,
            title: title,
            onAttachmentTap: onAttachmentTap,
            onExternalLinkTap: onExternalLinkTap,
            renderContext: renderContext,
            highlightBlockId: highlightBlockId,
          ),
        ),
  );
}

class DescriptionFullSheet extends StatelessWidget {
  final String text;
  final DescriptionFormat format;
  final List<TaskAttachment> attachments;
  final String title;
  final DescriptionAttachmentTap onAttachmentTap;
  final DescriptionExternalLinkTap? onExternalLinkTap;
  final DescriptionRenderContext? renderContext;
  final String? highlightBlockId;

  const DescriptionFullSheet({
    super.key,
    required this.text,
    required this.format,
    required this.attachments,
    required this.title,
    required this.onAttachmentTap,
    required this.onExternalLinkTap,
    this.renderContext,
    this.highlightBlockId,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetColor = isDark ? AppColors.sheetDark : AppColors.sheetLight;
    final textColor = isDark ? AppColors.textDark : AppColors.textLight;
    final secondaryColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.9,
      decoration: BoxDecoration(
        color: sheetColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: secondaryColor,
                borderRadius: BorderRadius.circular(AppTheme.sheetHandleRadius),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('close-full-description'),
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('full-description-scroll'),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: _HighlightableDescription(
                  text: text,
                  format: format,
                  attachments: attachments,
                  onAttachmentTap: onAttachmentTap,
                  onExternalLinkTap: onExternalLinkTap,
                  renderContext: renderContext,
                  highlightBlockId: highlightBlockId,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightableDescription extends StatefulWidget {
  final String text;
  final DescriptionFormat format;
  final List<TaskAttachment> attachments;
  final DescriptionAttachmentTap onAttachmentTap;
  final DescriptionExternalLinkTap? onExternalLinkTap;
  final DescriptionRenderContext? renderContext;
  final String? highlightBlockId;

  const _HighlightableDescription({
    required this.text,
    required this.format,
    required this.attachments,
    required this.onAttachmentTap,
    required this.onExternalLinkTap,
    this.renderContext,
    this.highlightBlockId,
  });

  @override
  State<_HighlightableDescription> createState() =>
      _HighlightableDescriptionState();
}

class _HighlightableDescriptionState extends State<_HighlightableDescription> {
  final _highlightKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _highlightKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 200),
          alignment: 0.2,
        );
      }
    });
  }

  Widget _body(String text) {
    return DescriptionBody(
      text: text,
      format: widget.format,
      attachments: widget.attachments,
      onAttachmentTap: widget.onAttachmentTap,
      onExternalLinkTap: widget.onExternalLinkTap,
      renderContext: widget.renderContext,
    );
  }

  @override
  Widget build(BuildContext context) {
    final highlightId = widget.highlightBlockId;
    if (highlightId == null) return _body(widget.text);
    final parts = splitDescriptionAroundBlock(widget.text, highlightId);
    if (parts == null) return _body(widget.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (parts.before.trim().isNotEmpty) _body(parts.before),
        Container(
          key: _highlightKey,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).colorScheme.primary),
          ),
          child: _body(parts.block),
        ),
        if (parts.after.trim().isNotEmpty) _body(parts.after),
      ],
    );
  }
}
