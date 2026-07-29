import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/theme.dart';
import '../../../core/image_utils.dart';
import '../providers/settings_provider.dart';

class AvatarSection extends StatelessWidget {
  const AvatarSection({super.key});

  Future<void> _pickAvatar(BuildContext context) async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: null);
    if (pickedFile == null) return;

    final format = await detectImageFormat(pickedFile.path);
    if (format == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Неподдерживаемый формат. Используйте JPEG, PNG, GIF или WebP')),
        );
      }
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final ext = format == ImageFormat.gif ? 'gif' : 'webp';
    final targetPath = '${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';

    String? resultPath;

    if (format == ImageFormat.gif) {
      final src = File(pickedFile.path);
      final dst = File(targetPath);
      await dst.writeAsBytes(await src.readAsBytes());
      resultPath = targetPath;
    } else {
      final result = await FlutterImageCompress.compressAndGetFile(
        pickedFile.path,
        targetPath,
        format: CompressFormat.webp,
        quality: 90,
      );
      resultPath = result?.path;
    }

    if (resultPath != null) {
      if (settings.avatarPath != null) {
        try {
          final oldFile = File(settings.avatarPath!);
          if (await oldFile.exists()) await oldFile.delete();
        } catch (_) {}
      }
      settings.setAvatarPath(resultPath);
    }
  }

  void _showFullScreen(BuildContext context, String imagePath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(
              child: Hero(
                tag: 'avatar_hero',
                child: Image.file(File(imagePath)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatarPath = context.select<SettingsProvider, String?>((s) => s.avatarPath);
    final hasAvatar = avatarPath != null;
    final changeAvatarLabel = context.select<SettingsProvider, String>((s) => s.tr('change_avatar'));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Column(
      children: [
        Center(
          child: GestureDetector(
            onTap: () {
              if (hasAvatar) {
                _showFullScreen(context, avatarPath);
              } else {
                _pickAvatar(context);
              }
            },
            child: Hero(
              tag: 'avatar_hero',
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                    width: 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: hasAvatar
                    ? Image.file(
                        File(avatarPath),
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                        cacheWidth: 240,
                        errorBuilder: (context, error, stackTrace) => Center(
                          child: Icon(Icons.person, size: 52, color: textSecondary),
                        ),
                      )
                    : Center(
                        child: Icon(Icons.person, size: 52, color: textSecondary),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: ElevatedButton(
            onPressed: () => _pickAvatar(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: surface,
              foregroundColor: textSecondary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.pillRadius),
              ),
            ),
            child: Text(
              changeAvatarLabel,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }
}
