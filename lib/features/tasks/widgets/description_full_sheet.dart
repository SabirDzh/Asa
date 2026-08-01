import 'package:flutter/material.dart';

import '../../../core/description_markdown.dart';
import '../../../core/theme.dart';
import '../models/task_info_block.dart';

class DescriptionPreview extends StatelessWidget {
  final String text;
  final DescriptionFormat format;
  final List<TaskAttachment> attachments;
  final VoidCallback onTap;
  final DescriptionAttachmentTap onAttachmentTap;
  final DescriptionExternalLinkTap? onExternalLinkTap;
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
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (ctx) => DescriptionFullSheet(
          text: text,
          format: format,
          attachments: attachments,
          title: title,
          onAttachmentTap: onAttachmentTap,
          onExternalLinkTap: onExternalLinkTap,
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

  const DescriptionFullSheet({
    super.key,
    required this.text,
    required this.format,
    required this.attachments,
    required this.title,
    required this.onAttachmentTap,
    required this.onExternalLinkTap,
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
                child: DescriptionBody(
                  text: text,
                  format: format,
                  attachments: attachments,
                  onAttachmentTap: onAttachmentTap,
                  onExternalLinkTap: onExternalLinkTap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
