import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/theme.dart';
import '../../../core/image_utils.dart';
import '../providers/settings_provider.dart';

class AvatarSection extends StatefulWidget {
  const AvatarSection({super.key});

  @override
  State<AvatarSection> createState() => _AvatarSectionState();
}

class _AvatarSectionState extends State<AvatarSection> {
  bool _isPickingAvatar = false;

  Future<void> _pickAvatar(BuildContext context) async {
    if (_isPickingAvatar) return;
    setState(() => _isPickingAvatar = true);

    try {
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: null,
      );
      if (pickedFile == null || !mounted) return;

      final format = await detectImageFormat(pickedFile.path);
      if (format == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(settings.tr('avatar_invalid_format'))),
          );
        }
        return;
      }

      final withinLimit = await isImageFileWithinLimit(pickedFile.path);
      if (!withinLimit) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(settings.tr('avatar_too_large'))),
          );
        }
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final ext = format == ImageFormat.gif ? 'gif' : 'webp';
      final targetPath =
          '${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';

      String? resultPath;

      if (format == ImageFormat.gif) {
        final sourceBytes = await readValidatedImageBytes(pickedFile.path);
        if (sourceBytes == null) return;
        final dst = File(targetPath);
        await dst.writeAsBytes(sourceBytes);
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
        String? previousPath;
        try {
          previousPath = await settings.setAvatarPath(resultPath);
        } catch (_) {
          try {
            final newFile = File(resultPath);
            if (await newFile.exists()) await newFile.delete();
          } catch (_) {}
          return;
        }
        if (previousPath != null && previousPath != resultPath) {
          try {
            final oldFile = File(previousPath);
            if (await oldFile.exists()) await oldFile.delete();
          } catch (_) {}
        }
      }
    } finally {
      if (mounted) setState(() => _isPickingAvatar = false);
    }
  }

  void _showFullScreen(BuildContext context, String imagePath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black,
                iconTheme: const IconThemeData(color: Colors.white),
                elevation: 0,
              ),
              body: LayoutBuilder(
                builder: (context, constraints) {
                  final pixelRatio = MediaQuery.devicePixelRatioOf(context);
                  final decodeWidth =
                      constraints.maxWidth.isFinite
                          ? (constraints.maxWidth * pixelRatio).round()
                          : null;
                  final decodeHeight =
                      constraints.maxHeight.isFinite
                          ? (constraints.maxHeight * pixelRatio).round()
                          : null;
                  return Center(
                    child: InteractiveViewer(
                      child: Hero(
                        tag: 'avatar_hero',
                        child: Image.file(
                          File(imagePath),
                          cacheWidth:
                              decodeWidth != null && decodeWidth > 0
                                  ? decodeWidth
                                  : null,
                          cacheHeight:
                              decodeHeight != null && decodeHeight > 0
                                  ? decodeHeight
                                  : null,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatarPath = context.select<SettingsProvider, String?>(
      (s) => s.avatarPath,
    );
    final hasAvatar = avatarPath != null;
    final changeAvatarLabel = context.select<SettingsProvider, String>(
      (s) => s.tr('change_avatar'),
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Column(
      children: [
        Center(
          child: GestureDetector(
            onTap:
                _isPickingAvatar
                    ? null
                    : () {
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
                child:
                    hasAvatar
                        ? Image.file(
                          File(avatarPath),
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                          cacheWidth: 240,
                          errorBuilder:
                              (context, error, stackTrace) => Center(
                                child: Icon(
                                  Icons.person,
                                  size: 52,
                                  color: textSecondary,
                                ),
                              ),
                        )
                        : Center(
                          child: Icon(
                            Icons.person,
                            size: 52,
                            color: textSecondary,
                          ),
                        ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: ElevatedButton(
            onPressed: _isPickingAvatar ? null : () => _pickAvatar(context),
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
