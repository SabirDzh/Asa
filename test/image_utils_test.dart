import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:asa/core/image_utils.dart';

void main() {
  group('detectImageFormat', () {
    test('detects JPEG from magic bytes', () async {
      final file = await _createTempFile([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46]);
      final format = await detectImageFormat(file.path);
      expect(format, ImageFormat.jpeg);
      await file.delete();
    });

    test('detects PNG from magic bytes', () async {
      final file = await _createTempFile([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      final format = await detectImageFormat(file.path);
      expect(format, ImageFormat.png);
      await file.delete();
    });

    test('detects GIF from magic bytes', () async {
      final file = await _createTempFile([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]);
      final format = await detectImageFormat(file.path);
      expect(format, ImageFormat.gif);
      await file.delete();
    });

    test('detects WebP from magic bytes', () async {
      final file = await _createTempFile([0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50]);
      final format = await detectImageFormat(file.path);
      expect(format, ImageFormat.webp);
      await file.delete();
    });

    test('returns null for unknown format', () async {
      final file = await _createTempFile([0x00, 0x00, 0x00, 0x00]);
      final format = await detectImageFormat(file.path);
      expect(format, isNull);
      await file.delete();
    });

    test('returns null for non-existent file', () async {
      final format = await detectImageFormat('/nonexistent/file.jpg');
      expect(format, isNull);
    });
  });
}

Future<File> _createTempFile(List<int> bytes) async {
  final dir = Directory.systemTemp;
  final file = File('${dir.path}/test_${DateTime.now().millisecondsSinceEpoch}.bin');
  await file.writeAsBytes(bytes);
  return file;
}
