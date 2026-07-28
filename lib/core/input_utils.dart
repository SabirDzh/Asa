import 'package:flutter/services.dart';

const double _speedMin = 0.1;
const double _speedMax = 5.0;

TextInputFormatter numericInputFormatter() => TextInputFormatter.withFunction((oldValue, newValue) {
      final text = newValue.text;
      if (text.isEmpty) return newValue;
      final filtered = text.replaceAll(RegExp(r'[^\d.]'), '');
      final dotCount = '.'.allMatches(filtered).length;
      String result = filtered;
      if (dotCount > 1) {
        final firstDot = filtered.indexOf('.');
        result = filtered.substring(0, firstDot + 1) +
            filtered.substring(firstDot + 1).replaceAll('.', '');
      }
      if (result.startsWith('.')) result = '0$result';
      return TextEditingValue(
        text: result,
        selection: TextSelection.collapsed(offset: result.length),
      );
    });

double? parseAndClampSpeed(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return null;
  final parsed = double.tryParse(v);
  if (parsed == null) return null;
  return parsed.clamp(_speedMin, _speedMax);
}

String sanitizeText(String value) {
  return value
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .trim();
}

TextInputFormatter textInputFormatter({int maxLength = 250}) =>
    LengthLimitingTextInputFormatter(maxLength);
