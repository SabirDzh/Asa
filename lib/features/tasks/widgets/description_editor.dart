import 'package:flutter/material.dart';

import '../../../core/app_strings.dart';
import '../../../core/description_markdown.dart';
import '../../../core/description_render_context.dart';
import '../../../core/input_utils.dart';
import '../models/task_info_block.dart';
import 'description_toolbar.dart';

TextEditingValue wrapSelection(
  TextEditingValue value,
  String prefix,
  String suffix,
) {
  final selection = _safeSelection(value);
  final selected = value.text.substring(selection.start, selection.end);
  final replacement = '$prefix$selected$suffix';
  final text = value.text.replaceRange(
    selection.start,
    selection.end,
    replacement,
  );
  final start = selection.start + prefix.length;
  final end = start + selected.length;
  return TextEditingValue(
    text: text,
    selection:
        selected.isEmpty
            ? TextSelection.collapsed(offset: start)
            : TextSelection(baseOffset: start, extentOffset: end),
  );
}

TextEditingValue prefixSelectedLines(TextEditingValue value, String prefix) {
  final selection = _safeSelection(value);
  final lineStart = value.text.lastIndexOf('\n', selection.start - 1) + 1;
  final nextNewline = value.text.indexOf('\n', selection.end);
  final lineEnd = nextNewline == -1 ? value.text.length : nextNewline;
  final selected = value.text.substring(lineStart, lineEnd);
  final replacement = selected
      .split('\n')
      .map((line) => '$prefix$line')
      .join('\n');
  final text = value.text.replaceRange(lineStart, lineEnd, replacement);
  int adjust(int offset) {
    var adjusted = offset;
    if (offset >= lineStart) adjusted += prefix.length;
    for (var index = lineStart; index < offset && index < lineEnd; index++) {
      if (value.text[index] == '\n') adjusted += prefix.length;
    }
    return adjusted;
  }

  return TextEditingValue(
    text: text,
    selection: TextSelection(
      baseOffset: adjust(selection.baseOffset),
      extentOffset: adjust(selection.extentOffset),
    ),
  );
}

TextSelection _safeSelection(TextEditingValue value) {
  final selection = value.selection;
  if (!selection.isValid ||
      selection.start < 0 ||
      selection.end > value.text.length) {
    return TextSelection.collapsed(offset: value.text.length);
  }
  return selection;
}

class DescriptionEditor extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final List<TaskAttachment> attachments;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final int maxLength;
  final Key? fieldKey;
  final DescriptionRenderContext? renderContext;
  final DescriptionAttachmentTap? onAttachmentTap;
  final DescriptionExternalLinkTap? onExternalLinkTap;
  final String? labelText;

  const DescriptionEditor({
    super.key,
    required this.controller,
    this.focusNode,
    this.attachments = const [],
    this.onChanged,
    this.validator,
    this.maxLength = kMaxTaskDescriptionLength,
    this.fieldKey,
    this.renderContext,
    this.onAttachmentTap,
    this.onExternalLinkTap,
    this.labelText,
  });

  @override
  State<DescriptionEditor> createState() => _DescriptionEditorState();
}

class _DescriptionEditorState extends State<DescriptionEditor> {
  bool _preview = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    _attachFocusNode(widget.focusNode);
  }

  @override
  void didUpdateWidget(covariant DescriptionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      _detachFocusNode(oldWidget.focusNode);
      _attachFocusNode(widget.focusNode);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _detachFocusNode(widget.focusNode);
    super.dispose();
  }

  void _attachFocusNode(FocusNode? focusNode) {
    if (focusNode == null) {
      _focused = false;
      return;
    }
    _focused = focusNode.hasFocus;
    focusNode.addListener(_handleFocusChanged);
  }

  void _detachFocusNode(FocusNode? focusNode) {
    focusNode?.removeListener(_handleFocusChanged);
    if (focusNode == widget.focusNode) _focused = false;
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  void _handleFocusChanged() {
    if (mounted) setState(() => _focused = widget.focusNode?.hasFocus ?? false);
  }

  bool get _showControls => widget.focusNode == null || _focused || _preview;

  void _apply(TextEditingValue Function(TextEditingValue) transform) {
    widget.controller.value = transform(widget.controller.value);
    widget.onChanged?.call(widget.controller.text);
    if (mounted) setState(() {});
  }

  void _wrap(String prefix, String suffix) {
    _apply((value) => wrapSelection(value, prefix, suffix));
    widget.focusNode?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final languageCode = Localizations.localeOf(context).languageCode;
    final attachmentTap = widget.onAttachmentTap ?? (_) {};
    final linkTap = widget.onExternalLinkTap;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_showControls) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<bool>(
              key: const ValueKey('description-editor-mode'),
              segments: [
                ButtonSegment<bool>(
                  value: false,
                  label: Text(
                    AppStrings.get('description_source', languageCode),
                  ),
                  icon: const Icon(Icons.code),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text(
                    AppStrings.get('description_preview', languageCode),
                  ),
                  icon: const Icon(Icons.visibility_outlined),
                ),
              ],
              selected: {_preview},
              onSelectionChanged: (selection) {
                setState(() => _preview = selection.first);
              },
            ),
          ),
          const SizedBox(height: 4),
        ],
        if (!_preview) ...[
          if (_showControls)
            DescriptionToolbar(
              onBold: () => _wrap('**', '**'),
              onItalic: () => _wrap('*', '*'),
              onCode: () => _wrap('`', '`'),
              onBulletedList:
                  () => _apply((value) => prefixSelectedLines(value, '- ')),
              onQuote:
                  () => _apply((value) => prefixSelectedLines(value, '> ')),
              onLink: () => _wrap('[', '](https://)'),
            ),
          TextFormField(
            key: widget.fieldKey,
            controller: widget.controller,
            focusNode: widget.focusNode,
            maxLength: widget.maxLength,
            maxLines: 8,
            minLines: 4,
            keyboardType: TextInputType.multiline,
            inputFormatters: [textInputFormatter(maxLength: widget.maxLength)],
            validator: widget.validator,
            onChanged: widget.onChanged,
            decoration: InputDecoration(
              labelText: widget.labelText,
              alignLabelWithHint: true,
            ),
          ),
        ] else
          Container(
            key: const ValueKey('description-editor-preview'),
            constraints: const BoxConstraints(minHeight: 132),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: textColor.withValues(alpha: 0.18)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              child: DescriptionBody(
                text: widget.controller.text,
                format: DescriptionFormat.markdown,
                attachments: widget.attachments,
                onAttachmentTap: attachmentTap,
                onExternalLinkTap: linkTap,
                renderContext: widget.renderContext,
              ),
            ),
          ),
      ],
    );
  }
}
