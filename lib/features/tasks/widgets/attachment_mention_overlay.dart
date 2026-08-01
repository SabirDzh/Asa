import 'package:flutter/material.dart';

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
    return Card(
      key: const ValueKey('attachment-mention-suggestions'),
      margin: const EdgeInsets.only(top: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 216),
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
                minTileHeight: 48,
                dense: true,
                leading: Icon(_icon(attachment.type)),
                title: Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  _typeLabel(attachment.type),
                  style: Theme.of(context).textTheme.bodySmall,
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
