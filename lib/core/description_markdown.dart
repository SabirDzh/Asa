import 'dart:convert';

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
  final encodedId =
      uri.host.isNotEmpty
          ? uri.host
          : uri.pathSegments.isNotEmpty
          ? uri.pathSegments.first
          : '';
  if (encodedId.length > 2048 ||
      RegExp(r'[\x00-\x1F\x7F]').hasMatch(encodedId)) {
    return null;
  }

  final id =
      encodedId.startsWith('b64_')
          ? _decodeAttachmentMentionId(encodedId.substring(4))
          : RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(encodedId)
          ? encodedId
          : null;
  if (id == null || id.isEmpty || id.length > 2048) return null;
  return AttachmentMention(id: id, label: label.trim());
}

String _attachmentMentionId(TaskAttachment attachment) {
  final id = attachment.id;
  if (RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) return id;
  return 'b64_${base64Url.encode(utf8.encode(id)).replaceAll('=', '')}';
}

String? _decodeAttachmentMentionId(String encoded) {
  try {
    final padded = '$encoded${'=' * ((4 - encoded.length % 4) % 4)}';
    final decoded = utf8.decode(
      base64Url.decode(padded),
      allowMalformed: false,
    );
    return decoded.length <= 2048 ? decoded : null;
  } on Object {
    return null;
  }
}

String _escapeMentionLabel(String value) {
  return value
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
      .replaceAll('\\', r'\\')
      .replaceAll(']', r'\]')
      .trim();
}

String attachmentMentionMarkdown(TaskAttachment attachment) {
  // Keep the attachment id only in the internal href. The visible label must
  // never expose a stored path or other implementation detail.
  final label = _escapeMentionLabel(attachmentDisplayName(attachment.name));
  final mentionId = _attachmentMentionId(attachment);
  final href =
      mentionId.startsWith('b64_')
          ? '$kAttachmentMentionScheme:///$mentionId'
          : '$kAttachmentMentionScheme://$mentionId';
  return '[$label]($href)';
}

/// Converts the editor-friendly `@file.name` form into a clickable Markdown
/// link immediately before rendering. The editor therefore never exposes
/// internal IDs, paths, or Markdown syntax, while older saved Markdown links
/// remain supported by [DescriptionLinkBuilder].
String expandAttachmentMentions(String text, List<TaskAttachment> attachments) {
  final sorted = [...attachments]..sort(
    (a, b) => attachmentDisplayName(
      b.name,
    ).length.compareTo(attachmentDisplayName(a.name).length),
  );
  final result = StringBuffer();
  String? fencedChar;
  var fencedLength = 0;
  var inlineCodeDelimiter = '';
  var squareBracketDepth = 0;
  var lineStart = true;
  var index = 0;

  while (index < text.length) {
    if (lineStart) {
      final lineEnd = text.indexOf('\n', index);
      final end = lineEnd == -1 ? text.length : lineEnd;
      final line = text.substring(index, end);
      final fence = RegExp(r'^\s*(`{3,}|~{3,})').firstMatch(line);
      if (fencedChar != null) {
        result.write(line);
        if (fence != null &&
            fence.group(1)!.startsWith(fencedChar) &&
            fence.group(1)!.length >= fencedLength) {
          fencedChar = null;
          fencedLength = 0;
        }
        if (lineEnd != -1) result.write('\n');
        index = lineEnd == -1 ? text.length : lineEnd + 1;
        lineStart = true;
        continue;
      }
      if (fence != null) {
        fencedChar = fence.group(1)![0];
        fencedLength = fence.group(1)!.length;
        result.write(line);
        if (lineEnd != -1) result.write('\n');
        index = lineEnd == -1 ? text.length : lineEnd + 1;
        lineStart = true;
        continue;
      }
    }

    final character = text[index];
    if (character == '\n') {
      result.write(character);
      index++;
      lineStart = true;
      continue;
    }

    if (character == '`' && (index == 0 || text[index - 1] != '\\')) {
      var runLength = 1;
      while (index + runLength < text.length &&
          text[index + runLength] == '`') {
        runLength++;
      }
      final delimiter = '`' * runLength;
      result.write(delimiter);
      if (inlineCodeDelimiter.isEmpty) {
        inlineCodeDelimiter = delimiter;
      } else if (inlineCodeDelimiter == delimiter) {
        inlineCodeDelimiter = '';
      }
      index += runLength;
      lineStart = false;
      continue;
    }

    if (inlineCodeDelimiter.isNotEmpty) {
      result.write(character);
      index++;
      lineStart = false;
      continue;
    }
    if (character == '[' && (index == 0 || text[index - 1] != '\\')) {
      squareBracketDepth++;
      result.write(character);
      index++;
      lineStart = false;
      continue;
    }
    if (character == ']' && squareBracketDepth > 0) {
      squareBracketDepth--;
      result.write(character);
      index++;
      lineStart = false;
      continue;
    }
    if (squareBracketDepth > 0 || character != '@') {
      result.write(character);
      index++;
      lineStart = false;
      continue;
    }

    TaskAttachment? match;
    String? matchedName;
    for (final attachment in sorted) {
      final name = attachmentDisplayName(attachment.name);
      final token = '@$name';
      final tokenEnd = index + token.length;
      final hasBoundaryBefore =
          index == 0 || RegExp(r'\s').hasMatch(text[index - 1]);
      final hasBoundaryAfter =
          tokenEnd == text.length ||
          (tokenEnd < text.length &&
              RegExp(r'[\s.,!?;:)\]]').hasMatch(text[tokenEnd]));
      if (name.isNotEmpty &&
          tokenEnd <= text.length &&
          text.startsWith(token, index) &&
          hasBoundaryBefore &&
          hasBoundaryAfter) {
        match = attachment;
        matchedName = name;
        break;
      }
    }

    if (match == null || matchedName == null) {
      result.write(character);
      index++;
      lineStart = false;
      continue;
    }
    result.write(attachmentMentionMarkdown(match));
    index += matchedName.length + 1;
    lineStart = false;
  }
  return result.toString();
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
  final token = '@${attachmentDisplayName(attachment.name)} ';
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
          attachmentDisplayName(mention.label),
          style: (preferredStyle ?? parentStyle)?.copyWith(
            color: (preferredStyle ?? parentStyle)?.color?.withValues(
              alpha: 0.5,
            ),
          ),
        );
      }
      final displayName = attachmentDisplayName(attachment.name);
      final attachmentIcon = switch (attachment.type) {
        TaskAttachmentType.link => Icons.link,
        TaskAttachmentType.image => Icons.image_outlined,
        TaskAttachmentType.file => Icons.attach_file,
      };
      return Semantics(
        button: true,
        label: displayName,
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
                  displayName,
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
      data: expandAttachmentMentions(text, attachments),
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
