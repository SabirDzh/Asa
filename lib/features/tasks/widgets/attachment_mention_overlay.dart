import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../models/task_info_block.dart';

class AttachmentMentionSuggestions extends StatelessWidget {
  final List<TaskAttachment> attachments;
  final ValueChanged<TaskAttachment> onSelected;
  final String typeLinkLabel;
  final String typeImageLabel;
  final String typeFileLabel;

  const AttachmentMentionSuggestions({
    super.key,
    required this.attachments,
    required this.onSelected,
    required this.typeLinkLabel,
    required this.typeImageLabel,
    required this.typeFileLabel,
  });

  IconData _icon(TaskAttachmentType type) {
    switch (type) {
      case TaskAttachmentType.link:
        return Icons.link;
      case TaskAttachmentType.image:
        return Icons.image_outlined;
      case TaskAttachmentType.file:
        return Icons.attach_file;
    }
  }

  String _typeLabel(TaskAttachmentType type) {
    switch (type) {
      case TaskAttachmentType.link:
        return typeLinkLabel;
      case TaskAttachmentType.image:
        return typeImageLabel;
      case TaskAttachmentType.file:
        return typeFileLabel;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor =
        isDark ? AppColors.surfaceSecondaryDark : AppColors.surfaceSecondaryLight;
    final borderColor =
        isDark
            ? AppColors.textSecondaryDark.withValues(alpha: 0.25)
            : AppColors.textSecondaryLight.withValues(alpha: 0.25);
    final textColor = isDark ? AppColors.textDark : AppColors.textLight;

    return Container(
      key: const ValueKey('attachment-mention-suggestions'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 180),
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: attachments.length,
          itemBuilder: (context, index) {
            final attachment = attachments[index];
            return Semantics(
              button: true,
              label: '${attachment.name}, ${_typeLabel(attachment.type)}',
              child: ListTile(
                key: ValueKey('attachment-mention-${attachment.id}'),
                minTileHeight: 44,
                dense: true,
                leading: Icon(
                  _icon(attachment.type),
                  color: AppColors.primary,
                  size: 20,
                ),
                title: Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
                ),
                trailing: Text(
                  _typeLabel(attachment.type),
                  style: TextStyle(
                    color:
                        isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                    fontSize: 12,
                  ),
                ),
                onTap: () => onSelected(attachment),
              ),
            );
          },
        ),
      ),
    );
  }
}
