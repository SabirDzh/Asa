import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'input_utils.dart';

/// Reads plain text from the system clipboard.
///
/// Returns `null` if the clipboard is empty or does not contain text.
/// The returned text is sanitized and trimmed.
Future<String?> getClipboardText() async {
  if (await Clipboard.hasStrings()) {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      return sanitizeText(data.text!);
    }
  }
  return null;
}

/// Inserts [text] into [controller] at the current cursor position,
/// replacing the current selection if any.
void insertTextAtCursor(TextEditingController controller, String text) {
  final selection = controller.selection;
  final currentText = controller.text;

  if (!selection.isValid ||
      selection.start < 0 ||
      selection.end > currentText.length) {
    controller.text = currentText + text;
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    return;
  }

  final newText = currentText.replaceRange(
    selection.start,
    selection.end,
    text,
  );
  controller.text = newText;
  final newOffset = selection.start + text.length;
  controller.selection = TextSelection.collapsed(offset: newOffset);
}
