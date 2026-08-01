import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// The attachment operation selected in the editor.
enum AttachmentAction { link, image, file }

class AttachmentActionMenu extends StatelessWidget {
  final AttachmentAction selectedAction;
  final ValueChanged<AttachmentAction> onActionChanged;
  final VoidCallback onAdd;
  final String linkLabel;
  final String imageLabel;
  final String fileLabel;
  final String addLabel;
  final bool enabled;

  const AttachmentActionMenu({
    super.key,
    required this.selectedAction,
    required this.onActionChanged,
    required this.onAdd,
    required this.linkLabel,
    required this.imageLabel,
    required this.fileLabel,
    required this.addLabel,
    this.enabled = true,
  });

  String _label(AttachmentAction action) {
    switch (action) {
      case AttachmentAction.link:
        return linkLabel;
      case AttachmentAction.image:
        return imageLabel;
      case AttachmentAction.file:
        return fileLabel;
    }
  }

  IconData _icon(AttachmentAction action) {
    switch (action) {
      case AttachmentAction.link:
        return Icons.link;
      case AttachmentAction.image:
        return Icons.image_outlined;
      case AttachmentAction.file:
        return Icons.attach_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return Row(
      key: const ValueKey('attachment-action-menu'),
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: PopupMenuButton<AttachmentAction>(
              enabled: enabled,
              tooltip: _label(selectedAction),
              onSelected: onActionChanged,
              constraints: const BoxConstraints(minWidth: 240),
              itemBuilder:
                  (context) => [
                    for (final action in AttachmentAction.values)
                      PopupMenuItem<AttachmentAction>(
                        value: action,
                        height: 48,
                        child: SizedBox(
                          width: double.infinity,
                          child: Row(
                            children: [
                              Icon(_icon(action), size: 18),
                              const SizedBox(width: 10),
                              Expanded(child: Text(_label(action))),
                            ],
                          ),
                        ),
                      ),
                  ],
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: outline),
                  borderRadius: BorderRadius.circular(AppTheme.pillRadius),
                ),
                child: Row(
                  children: [
                    Icon(_icon(selectedAction), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _label(selectedAction),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            key: const ValueKey('attachment-action-add'),
            tooltip: addLabel,
            onPressed: enabled ? onAdd : null,
            icon: const Icon(Icons.add),
            style: IconButton.styleFrom(
              side: BorderSide(color: outline),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.pillRadius),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
