import 'package:flutter_test/flutter_test.dart';
import 'package:asa/core/input_utils.dart';

void main() {
  group('sanitizeText', () {
    test('strips null and control characters (except \\n, \\r)', () {
      expect(sanitizeText('hello\x00world'), 'helloworld');
      expect(sanitizeText('line1\x01line2'), 'line1line2');
    });

    test('trims whitespace', () {
      expect(sanitizeText('  hello  '), 'hello');
    });

    test('preserves normal text', () {
      expect(sanitizeText('Hello World!'), 'Hello World!');
    });
  });

  group('numericInputFormatter', () {
    final formatter = numericInputFormatter();

    test('allows digits', () {
      final result = formatter.formatEditUpdate(
        const TextEditingValue(text: ''),
        const TextEditingValue(text: '123'),
      );
      expect(result.text, '123');
    });

    test('allows one decimal point', () {
      final result = formatter.formatEditUpdate(
        const TextEditingValue(text: '12'),
        const TextEditingValue(text: '12.5'),
      );
      expect(result.text, '12.5');
    });

    test('strips second decimal point', () {
      final result = formatter.formatEditUpdate(
        const TextEditingValue(text: '12.5'),
        const TextEditingValue(text: '12.5.3'),
      );
      expect(result.text, '12.53');
    });

    test('strips non-numeric characters', () {
      final result = formatter.formatEditUpdate(
        const TextEditingValue(text: ''),
        const TextEditingValue(text: 'abc12x3'),
      );
      expect(result.text, '123');
    });

    test('prefixes dot with zero', () {
      final result = formatter.formatEditUpdate(
        const TextEditingValue(text: ''),
        const TextEditingValue(text: '.5'),
      );
      expect(result.text, '0.5');
    });
  });

  group('textInputFormatter', () {
    test('caps at 250 characters by default', () {
      final formatter = textInputFormatter();
      final long = 'a' * 300;
      final result = formatter.formatEditUpdate(
        const TextEditingValue(text: ''),
        TextEditingValue(text: long),
      );
      expect(result.text.length, 250);
    });
  });
}
