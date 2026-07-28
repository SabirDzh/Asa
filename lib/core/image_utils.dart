import 'dart:io';

class ImageFormat {
  final String name;
  final String extension;
  final bool supportsAnimation;

  const ImageFormat(this.name, this.extension, this.supportsAnimation);

  static const jpeg = ImageFormat('JPEG', 'jpg', false);
  static const png = ImageFormat('PNG', 'png', false);
  static const gif = ImageFormat('GIF', 'gif', true);
  static const webp = ImageFormat('WebP', 'webp', false);

  static const List<ImageFormat> all = [jpeg, png, gif, webp];

  static const List<String> allowedExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
}

Future<ImageFormat?> detectImageFormat(String path) async {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    final bytes = await file.openRead(0, 12).first;

    if (bytes.length < 4) return null;

    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return ImageFormat.jpeg;
    }
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return ImageFormat.png;
    }
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) {
      return ImageFormat.gif;
    }
    if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46) {
      if (bytes.length >= 12 && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
        return ImageFormat.webp;
      }
    }

    return null;
  } catch (_) {
    return null;
  }
}
