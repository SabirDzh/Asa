import 'package:flutter/services.dart';

/// Default maximum length for task/folder titles and search input.
const int kMaxTextInputLength = 250;

TextInputFormatter numericInputFormatter() =>
    TextInputFormatter.withFunction((oldValue, newValue) {
      final text = newValue.text;
      if (text.isEmpty) return newValue;
      final filtered = text.replaceAll(RegExp(r'[^\d.]'), '');
      final dotCount = '.'.allMatches(filtered).length;
      String result = filtered;
      if (dotCount > 1) {
        final firstDot = filtered.indexOf('.');
        result =
            filtered.substring(0, firstDot + 1) +
            filtered.substring(firstDot + 1).replaceAll('.', '');
      }
      if (result.startsWith('.')) result = '0$result';
      return TextEditingValue(
        text: result,
        selection: TextSelection.collapsed(offset: result.length),
      );
    });

String sanitizeText(String value) {
  return value.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '').trim();
}

TextInputFormatter textInputFormatter({int maxLength = kMaxTextInputLength}) =>
    LengthLimitingTextInputFormatter(maxLength);
