import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'app_strings.dart';
import 'description_document.dart';
import 'description_format.dart';
import 'description_reference_parser.dart';
import 'description_render_context.dart';
import 'task_attachment_service.dart' as attachment_service;
import 'task_attachment_validation.dart';
import 'theme.dart';
import '../features/tasks/models/task_info_block.dart';
import '../features/tasks/services/description_link_resolver.dart';

export 'description_format.dart';

const int kDescriptionPreviewLength = 150;
const String kAttachmentMentionScheme = 'attachment';
const String kDescriptionWikilinkScheme = 'asa-wikilink';
const String kDescriptionTagScheme = 'asa-tag';

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

String _attachmentMentionHref(String id) {
  final encodedId =
      RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)
          ? id
          : 'b64_${base64Url.encode(utf8.encode(id)).replaceAll('=', '')}';
  return encodedId.startsWith('b64_')
      ? '$kAttachmentMentionScheme:///$encodedId'
      : '$kAttachmentMentionScheme://$encodedId';
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
  final href = _attachmentMentionHref(attachment.id);
  return '[$label]($href)';
}

String attachmentEmbedMarkdown(TaskAttachment attachment) {
  final label = _escapeMentionLabel(attachmentDisplayName(attachment.name));
  return '![$label](${_attachmentMentionHref(attachment.id)})';
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

String _escapeMarkdownLabel(String value) {
  return value
      .replaceAll('\\', r'\\')
      .replaceAll('[', r'\[')
      .replaceAll(']', r'\]')
      .replaceAll('\n', ' ')
      .trim();
}

String _descriptionInternalHref(String scheme, String value) {
  return '$scheme://link?value=${Uri.encodeQueryComponent(value)}';
}

TaskAttachment? _findDescriptionAttachment(
  String target,
  List<TaskAttachment> attachments,
) {
  final normalizedTarget = attachmentDisplayName(target).trim().toLowerCase();
  for (final attachment in attachments) {
    if (attachment.id == target) return attachment;
    if (attachmentDisplayName(attachment.name).trim().toLowerCase() ==
        normalizedTarget) {
      return attachment;
    }
  }
  return null;
}

/// Converts supported Obsidian-like syntax to private Markdown schemes.
///
/// The stored source is never changed. Only references recognized by the
/// bounded parser are rewritten, and all targets stay in URI query data until
/// the custom link builder resolves them.
String prepareDescriptionMarkdown(
  String source,
  List<TaskAttachment> attachments,
) {
  final document = parseDescriptionDocument(source);
  final replacements = <({int start, int end, String value})>[];
  for (final reference in document.references) {
    switch (reference.type) {
      case DescriptionReferenceType.wikilink:
        final label = _escapeMarkdownLabel(
          reference.alias?.trim().isNotEmpty == true
              ? reference.alias!
              : reference.target,
        );
        replacements.add((
          start: reference.start,
          end: reference.end,
          value:
              '[$label](${_descriptionInternalHref(kDescriptionWikilinkScheme, reference.target)})',
        ));
      case DescriptionReferenceType.embed:
        final attachment = _findDescriptionAttachment(
          reference.target,
          attachments,
        );
        replacements.add((
          start: reference.start,
          end: reference.end,
          value:
              attachment == null
                  ? '[Missing attachment: ${_escapeMarkdownLabel(reference.target)}]'
                  : attachmentEmbedMarkdown(attachment),
        ));
      case DescriptionReferenceType.tag:
        final label = _escapeMarkdownLabel(reference.raw);
        replacements.add((
          start: reference.start,
          end: reference.end,
          value:
              '[$label](${_descriptionInternalHref(kDescriptionTagScheme, reference.target)})',
        ));
      case DescriptionReferenceType.blockReference:
        break;
    }
  }
  var prepared = source;
  for (final replacement in replacements.reversed) {
    if (replacement.start < 0 ||
        replacement.end > prepared.length ||
        replacement.start >= replacement.end) {
      continue;
    }
    prepared = prepared.replaceRange(
      replacement.start,
      replacement.end,
      replacement.value,
    );
  }
  return prepared;
}

String? _descriptionSchemeValue(String href, String scheme) {
  final uri = Uri.tryParse(href);
  if (uri == null || uri.scheme != scheme) return null;
  final value = uri.queryParameters['value'];
  return value?.trim().isEmpty == true ? null : value?.trim();
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
  final DescriptionRenderContext? renderContext;
  final Color accentColor;

  DescriptionLinkBuilder({
    required this.attachments,
    required this.onAttachmentTap,
    required this.onExternalLinkTap,
    required this.renderContext,
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

    final wikilinkTarget = _descriptionSchemeValue(
      href,
      kDescriptionWikilinkScheme,
    );
    if (wikilinkTarget != null) {
      final resolution =
          renderContext?.resolveLink?.call(wikilinkTarget) ??
          DescriptionLinkResolution(
            target: wikilinkTarget,
            task: null,
            candidates: const [],
          );
      final color =
          resolution.isResolved
              ? accentColor
              : resolution.isAmbiguous
              ? Colors.orange
              : (preferredStyle ?? parentStyle)?.color?.withValues(
                    alpha: 0.65,
                  ) ??
                  accentColor.withValues(alpha: 0.65);
      return Semantics(
        link: true,
        label: label,
        child: InkWell(
          key: ValueKey('markdown-wikilink-$wikilinkTarget'),
          onTap:
              renderContext?.onWikilinkTap == null
                  ? null
                  : () => renderContext!.onWikilinkTap!(resolution),
          child: Text(
            label,
            style:
                (preferredStyle ?? parentStyle)?.copyWith(
                  color: color,
                  decoration:
                      resolution.isUnresolved
                          ? TextDecoration.underline
                          : TextDecoration.none,
                  decorationStyle:
                      resolution.isUnresolved
                          ? TextDecorationStyle.dotted
                          : null,
                ) ??
                TextStyle(color: color),
          ),
        ),
      );
    }

    final tag = _descriptionSchemeValue(href, kDescriptionTagScheme);
    if (tag != null) {
      return Semantics(
        button: true,
        label: tag,
        child: InkWell(
          key: ValueKey('markdown-tag-$tag'),
          borderRadius: BorderRadius.circular(8),
          onTap:
              renderContext?.onTagTap == null
                  ? null
                  : () => renderContext!.onTagTap!(tag),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style:
                  (preferredStyle ?? parentStyle)?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ) ??
                  TextStyle(color: accentColor, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );
    }

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

String _markdownFromNode(md.Node node) {
  if (node is md.Element) {
    final children =
        (node.children ?? const <md.Node>[]).map(_markdownFromNode).join();
    return switch (node.tag) {
      'strong' => '**$children**',
      'em' => '*$children*',
      'del' => '~~$children~~',
      'code' => '`$children`',
      'br' => '\\n',
      'a' => '[${children.trim()}](${node.attributes['href'] ?? ''})',
      'p' => '$children\\n\\n',
      _ => children,
    };
  }
  return node.textContent;
}

class _DescriptionCalloutBuilder extends MarkdownElementBuilder {
  final Color textColor;
  final Color accentColor;
  final List<TaskAttachment> attachments;
  final DescriptionAttachmentTap onAttachmentTap;
  final DescriptionExternalLinkTap? onExternalLinkTap;
  final DescriptionRenderContext? renderContext;

  _DescriptionCalloutBuilder({
    required this.textColor,
    required this.accentColor,
    required this.attachments,
    required this.onAttachmentTap,
    required this.onExternalLinkTap,
    required this.renderContext,
  });

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final text =
        (element.children ?? const <md.Node>[])
            .map(_markdownFromNode)
            .join()
            .trim();
    final match = RegExp(
      r'^\[!([A-Za-z0-9_-]+)\]\s*(.*)$',
      dotAll: true,
    ).firstMatch(text);
    if (match == null) return null;
    final kind = match.group(1)!.toLowerCase();
    const supported = {'note', 'tip', 'warning', 'important', 'quote'};
    if (!supported.contains(kind)) return null;
    final body = match.group(2)!.trim();
    final title = AppStrings.get(
      'description_callout_$kind',
      Localizations.localeOf(context).languageCode,
    );
    final color = switch (kind) {
      'warning' || 'important' => Colors.orange,
      'tip' => Colors.green,
      'quote' => Colors.purple,
      _ => accentColor,
    };
    return Semantics(
      container: true,
      label: '$title: $body',
      child: Container(
        key: ValueKey('description-callout-$kind'),
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          border: Border(left: BorderSide(color: color, width: 3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: (preferredStyle ?? parentStyle)?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (body.isNotEmpty)
              DescriptionBody(
                text: body,
                format: DescriptionFormat.markdown,
                attachments: attachments,
                onAttachmentTap: onAttachmentTap,
                onExternalLinkTap: onExternalLinkTap,
                renderContext: renderContext,
              ),
          ],
        ),
      ),
    );
  }
}

Widget _descriptionAttachmentEmbed(
  TaskAttachment attachment,
  String? alt,
  Color accentColor,
  Future<void> Function(TaskAttachment attachment)? onTap,
) {
  return _DescriptionAttachmentEmbed(
    attachment: attachment,
    accentColor: accentColor,
    onTap: onTap,
  );
}

class _DescriptionAttachmentEmbed extends StatefulWidget {
  final TaskAttachment attachment;
  final Color accentColor;
  final Future<void> Function(TaskAttachment attachment)? onTap;

  const _DescriptionAttachmentEmbed({
    required this.attachment,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_DescriptionAttachmentEmbed> createState() =>
      _DescriptionAttachmentEmbedState();
}

class _DescriptionAttachmentEmbedState
    extends State<_DescriptionAttachmentEmbed> {
  Future<List<int>?>? _bytesFuture;

  @override
  void initState() {
    super.initState();
    _startLoading();
  }

  void _startLoading() {
    if (widget.attachment.type == TaskAttachmentType.image) {
      _bytesFuture = _loadBytes();
    }
  }

  Future<List<int>?> _loadBytes() async {
    try {
      return await attachment_service.readStoredTaskAttachmentBytes(
        widget.attachment.value,
      );
    } on Object {
      return null;
    }
  }

  Future<void> _handleTap() async {
    final callback = widget.onTap;
    if (callback == null) return;
    try {
      await callback(widget.attachment);
    } on Object {
      // The owning screen reports unavailable attachments. The renderer must
      // never surface an unhandled Future from a Markdown tap callback.
    }
  }

  @override
  void didUpdateWidget(_DescriptionAttachmentEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    final attachmentChanged =
        oldWidget.attachment.id != widget.attachment.id ||
        oldWidget.attachment.value != widget.attachment.value;
    if (attachmentChanged) {
      _bytesFuture = null;
      _startLoading();
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = attachmentDisplayName(widget.attachment.name);
    final child =
        widget.attachment.type == TaskAttachmentType.image
            ? FutureBuilder<List<int>?>(
              future: _bytesFuture,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes == null || bytes.isEmpty) {
                  return _missingAttachmentEmbed(
                    label,
                    widget.accentColor,
                    Localizations.localeOf(context).languageCode,
                  );
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    Uint8List.fromList(bytes),
                    fit: BoxFit.contain,
                    errorBuilder:
                        (_, _, _) => _missingAttachmentEmbed(
                          label,
                          widget.accentColor,
                          Localizations.localeOf(context).languageCode,
                        ),
                  ),
                );
              },
            )
            : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.attach_file, color: widget.accentColor, size: 18),
                const SizedBox(width: 6),
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            );
    return Semantics(
      button: widget.onTap != null,
      label: label,
      child: InkWell(
        key: ValueKey('markdown-embed-${widget.attachment.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: widget.onTap == null ? null : _handleTap,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: 220,
            maxWidth: MediaQuery.sizeOf(context).width - 32,
            minHeight: 32,
          ),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: widget.accentColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: child,
        ),
      ),
    );
  }
}

Widget _missingAttachmentEmbed(
  String label,
  Color accentColor,
  String languageCode,
) {
  final prefix = AppStrings.get('description_missing_attachment', languageCode);
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.broken_image_outlined, color: accentColor, size: 18),
      const SizedBox(width: 6),
      Text('$prefix: $label'),
    ],
  );
}

class DescriptionBody extends StatelessWidget {
  final String text;
  final DescriptionFormat format;
  final List<TaskAttachment> attachments;
  final DescriptionAttachmentTap onAttachmentTap;
  final DescriptionExternalLinkTap? onExternalLinkTap;
  final DescriptionRenderContext? renderContext;
  final bool selectable;

  const DescriptionBody({
    super.key,
    required this.text,
    required this.format,
    required this.attachments,
    required this.onAttachmentTap,
    required this.onExternalLinkTap,
    this.renderContext,
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
      data: prepareDescriptionMarkdown(
        expandAttachmentMentions(text, attachments),
        attachments,
      ),
      selectable: selectable,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: TextStyle(color: textColor),
        a: TextStyle(color: AppColors.primary),
      ),
      // Never let user-authored Markdown trigger an arbitrary network/image
      // request. Images are represented as text until an attachment-specific
      // image flow is added with an explicit allowlist.
      imageBuilder: (uri, title, alt) {
        final mention = extractAttachmentMention(uri.toString(), alt ?? '');
        final attachment =
            mention == null
                ? null
                : _findDescriptionAttachment(mention.id, attachments);
        if (attachment == null) {
          return Text(
            '[${alt?.trim().isNotEmpty == true ? alt!.trim() : 'image'}]',
          );
        }
        return _descriptionAttachmentEmbed(
          attachment,
          alt,
          AppColors.primary,
          renderContext?.onAttachmentEmbedTap,
        );
      },
      builders: {
        'a': DescriptionLinkBuilder(
          attachments: attachments,
          onAttachmentTap: onAttachmentTap,
          onExternalLinkTap: onExternalLinkTap,
          renderContext: renderContext,
          accentColor: AppColors.primary,
        ),
        'blockquote': _DescriptionCalloutBuilder(
          textColor: textColor,
          accentColor: AppColors.primary,
          attachments: attachments,
          onAttachmentTap: onAttachmentTap,
          onExternalLinkTap: onExternalLinkTap,
          renderContext: renderContext,
        ),
      },
    );
  }
}
