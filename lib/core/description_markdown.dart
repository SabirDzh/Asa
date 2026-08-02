import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'description_format.dart';
import 'task_attachment_validation.dart';
import 'theme.dart';
import '../features/tasks/models/task_info_block.dart';

export 'description_format.dart';

const int kDescriptionPreviewLength = 150;
const String kAttachmentMentionScheme = 'attachment';

bool isSafeDescriptionHref(String href) {
  return normalizeTaskAttachmentLink(href) != null;
}

/// Returns a Unicode-safe visual preview. The full source is never mutated.
String descriptionPreview(
  String source, {
  int maxCodePoints = kDescriptionPreviewLength,
}) {
  final value = source.trim();
  final codePoints = value.runes.toList();
  if (codePoints.length <= maxCodePoints) return value;
  return '${String.fromCharCodes(codePoints.take(maxCodePoints))}…';
}

class AttachmentMention {
  final String id;
  final String label;

  const AttachmentMention({required this.id, required this.label});
}

AttachmentMention? extractAttachmentMention(String href, String label) {
  final uri = Uri.tryParse(href.trim());
  if (uri == null || uri.scheme.toLowerCase() != kAttachmentMentionScheme) {
    return null;
  }
  final id = uri.host.isNotEmpty ? uri.host : uri.path;
  if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) return null;
  return AttachmentMention(id: id, label: label.trim());
}

String _escapeMentionLabel(String value) {
  return value
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
      .replaceAll('\\', r'\\')
      .replaceAll(']', r'\]')
      .trim();
}

String attachmentMentionMarkdown(TaskAttachment attachment) {
  final label = _escapeMentionLabel(attachment.name);
  return '[@$label]($kAttachmentMentionScheme://${Uri.encodeComponent(attachment.id)})';
}

class MentionTrigger {
  final int start;
  final int end;
  final String query;

  const MentionTrigger({
    required this.start,
    required this.end,
    required this.query,
  });

  @override
  bool operator ==(Object other) {
    return other is MentionTrigger &&
        other.start == start &&
        other.end == end &&
        other.query == query;
  }

  @override
  int get hashCode => Object.hash(start, end, query);
}

MentionTrigger? findMentionTrigger(String text, int cursorOffset) {
  if (cursorOffset < 0 || cursorOffset > text.length) return null;
  final beforeCursor = text.substring(0, cursorOffset);
  final at = beforeCursor.lastIndexOf('@');
  if (at == -1) return null;
  if (at > 0 && !RegExp(r'[\s]').hasMatch(beforeCursor[at - 1])) return null;
  final query = beforeCursor.substring(at + 1);
  if (query.contains(RegExp(r'[\s\n\r]'))) return null;
  return MentionTrigger(start: at, end: cursorOffset, query: query);
}

TextEditingValue replaceMentionTrigger(
  TextEditingValue value,
  MentionTrigger trigger,
  TaskAttachment attachment,
) {
  final token = '${attachmentMentionMarkdown(attachment)} ';
  final nextText = value.text.replaceRange(trigger.start, trigger.end, token);
  final nextOffset = trigger.start + token.length;
  return TextEditingValue(
    text: nextText,
    selection: TextSelection.collapsed(offset: nextOffset),
  );
}

typedef DescriptionAttachmentTap = void Function(TaskAttachment attachment);
typedef DescriptionExternalLinkTap =
    void Function(String href, {String? title});

class DescriptionLinkBuilder extends MarkdownElementBuilder {
  final List<TaskAttachment> attachments;
  final DescriptionAttachmentTap onAttachmentTap;
  final DescriptionExternalLinkTap? onExternalLinkTap;
  final Color accentColor;

  DescriptionLinkBuilder({
    required this.attachments,
    required this.onAttachmentTap,
    required this.onExternalLinkTap,
    required this.accentColor,
  });

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final href = element.attributes['href'];
    final label = element.textContent;
    if (href == null) return null;

    final mention = extractAttachmentMention(href, label);
    if (mention != null) {
      TaskAttachment? attachment;
      for (final candidate in attachments) {
        if (candidate.id == mention.id) {
          attachment = candidate;
          break;
        }
      }
      if (attachment == null) {
        return Text(
          '@${mention.label}',
          style: (preferredStyle ?? parentStyle)?.copyWith(
            color: (preferredStyle ?? parentStyle)?.color?.withValues(
              alpha: 0.5,
            ),
          ),
        );
      }
      final attachmentIcon = switch (attachment.type) {
        TaskAttachmentType.link => Icons.link,
        TaskAttachmentType.image => Icons.image_outlined,
        TaskAttachmentType.file => Icons.attach_file,
      };
      return Semantics(
        button: true,
        label: '@${attachment.name}',
        child: InkWell(
          key: ValueKey('markdown-attachment-${attachment.id}'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => onAttachmentTap(attachment!),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(attachmentIcon, size: 14, color: accentColor),
                const SizedBox(width: 4),
                Text(
                  '@${attachment.name}',
                  style:
                      (preferredStyle ?? parentStyle)?.copyWith(
                        color: accentColor,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ) ??
                      TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!isSafeDescriptionHref(href)) {
      return Text(label, style: preferredStyle ?? parentStyle);
    }

    return InkWell(
      key: ValueKey('markdown-link-$href'),
      onTap:
          onExternalLinkTap == null
              ? null
              : () =>
                  onExternalLinkTap!(href, title: element.attributes['title']),
      child: Text(
        label,
        style:
            (preferredStyle ?? parentStyle)?.copyWith(
              color: accentColor,
              decoration: TextDecoration.underline,
            ) ??
            TextStyle(color: accentColor, decoration: TextDecoration.underline),
      ),
    );
  }
}

class DescriptionBody extends StatelessWidget {
  final String text;
  final DescriptionFormat format;
  final List<TaskAttachment> attachments;
  final DescriptionAttachmentTap onAttachmentTap;
  final DescriptionExternalLinkTap? onExternalLinkTap;
  final bool selectable;

  const DescriptionBody({
    super.key,
    required this.text,
    required this.format,
    required this.attachments,
    required this.onAttachmentTap,
    required this.onExternalLinkTap,
    this.selectable = false,
  });

  @override
  Widget build(BuildContext context) {
    final textColor =
        Theme.of(context).brightness == Brightness.dark
            ? AppColors.textDark
            : AppColors.textLight;
    if (format == DescriptionFormat.plainText) {
      return SelectableText(text.trim(), style: TextStyle(color: textColor));
    }

    return MarkdownBody(
      data: text,
      selectable: selectable,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: TextStyle(color: textColor),
        a: TextStyle(color: AppColors.primary),
      ),
      // Never let user-authored Markdown trigger an arbitrary network/image
      // request. Images are represented as text until an attachment-specific
      // image flow is added with an explicit allowlist.
      imageBuilder:
          (uri, title, alt) => Text(
            '[${alt?.trim().isNotEmpty == true ? alt!.trim() : 'image'}]',
          ),
      builders: {
        'a': DescriptionLinkBuilder(
          attachments: attachments,
          onAttachmentTap: onAttachmentTap,
          onExternalLinkTap: onExternalLinkTap,
          accentColor: AppColors.primary,
        ),
      },
    );
  }
}
