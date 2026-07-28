import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/theme.dart';
import '../../../core/theme_switcher.dart';
import '../../../core/input_utils.dart';
import '../providers/settings_provider.dart';
import '../../tasks/providers/task_provider.dart';

/// Settings screen — Figma 29:371 with interactive bottom sheets for Language, Data, and About
class SettingsScreen extends StatelessWidget {
  final bool standalone;
  const SettingsScreen({super.key, this.standalone = true});

  Future<void> _pickAvatar(BuildContext context) async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final targetPath = '${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.webp';

    final result = await FlutterImageCompress.compressAndGetFile(
      pickedFile.path,
      targetPath,
      format: CompressFormat.webp,
      quality: 90,
    );

    if (result != null) {
      if (settings.avatarPath != null) {
        try {
          final oldFile = File(settings.avatarPath!);
          if (oldFile.existsSync()) oldFile.deleteSync();
        } catch (_) {}
      }
      settings.setAvatarPath(result.path);
    }
  }

  void _showAvatarFullScreen(BuildContext context, String imagePath) {
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

  // ── Bottom sheet: Language ──────────────────────────────────
  void _showLanguageSheet(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navBg = isDark ? AppColors.navDark : AppColors.navLight;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: navBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              settings.tr('language'),
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Русский', style: TextStyle(color: Colors.white, fontSize: 16)),
              trailing: settings.languageCode == 'ru'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                settings.setLanguage('ru');
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: const Text('English', style: TextStyle(color: Colors.white, fontSize: 16)),
              trailing: settings.languageCode == 'en'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                settings.setLanguage('en');
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom sheet: Animation Speed ────────────────────────────
  String _getAnimationSpeedLabel(SettingsProvider settings) {
    if (settings.animationSpeed == 0.5) return settings.tr('speed_fast');
    if (settings.animationSpeed == 1.0) return settings.tr('speed_normal');
    if (settings.animationSpeed == 2.0) return settings.tr('speed_slow');
    return '${settings.tr('speed_custom')} (${settings.animationSpeed})';
  }

  void _showAnimationSpeedSheet(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navBg = isDark ? AppColors.navDark : AppColors.navLight;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: navBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              settings.tr('animation_speed'),
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: Text(settings.tr('speed_fast'), style: const TextStyle(color: Colors.white, fontSize: 16)),
              trailing: settings.animationSpeed == 0.5
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                settings.setAnimationSpeed(0.5);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: Text(settings.tr('speed_normal'), style: const TextStyle(color: Colors.white, fontSize: 16)),
              trailing: settings.animationSpeed == 1.0
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                settings.setAnimationSpeed(1.0);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: Text(settings.tr('speed_slow'), style: const TextStyle(color: Colors.white, fontSize: 16)),
              trailing: settings.animationSpeed == 2.0
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                settings.setAnimationSpeed(2.0);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              title: Text(settings.tr('speed_custom'), style: const TextStyle(color: Colors.white, fontSize: 16)),
              trailing: settings.animationSpeed != 0.5 && settings.animationSpeed != 1.0 && settings.animationSpeed != 2.0
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                _showCustomSpeedSheet(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom sheet: Custom Speed ──────────────────────────────
  void _showCustomSpeedSheet(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? AppColors.navDark : AppColors.navLight;
    final inputBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final controller = TextEditingController(text: settings.animationSpeed.toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AnimatedPadding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        child: Container(
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.only(
            top: AppTheme.sheetPadTop,
            left: AppTheme.sheetPadH,
            right: AppTheme.sheetPadH,
            bottom: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.sheetHandleRadius),
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.sheetGap),
              Container(
                height: AppTheme.rowHeight,
                decoration: BoxDecoration(
                  color: inputBg,
                  borderRadius: BorderRadius.circular(AppTheme.pillRadius),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.rowPadH,
                  vertical: AppTheme.rowPadV,
                ),
                child: Row(
                  children: [
                    const Icon(Iconsax.timer_1, color: Colors.white, size: 24),
                    const SizedBox(width: AppTheme.rowGap),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [numericInputFormatter()],
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: '1.0',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 16,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: (val) {
                          final v = val.trim();
                          final parsed = double.tryParse(v);
                          if (parsed == null || parsed < 0.1 || parsed > 5.0) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: const Text('Значение должно быть от 0.1 до 5.0')),
                            );
                            return;
                          }
                          context.read<SettingsProvider>().setAnimationSpeed(parsed);
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'от 0.1 до 5.0',
                  style: TextStyle(color: textSecondary, fontSize: 14),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    final v = controller.text.trim();
                    final parsed = double.tryParse(v);
                    if (parsed == null || parsed < 0.1 || parsed > 5.0) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: const Text('Значение должно быть от 0.1 до 5.0')),
                      );
                      return;
                    }
                    context.read<SettingsProvider>().setAnimationSpeed(parsed);
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.pillRadius),
                    ),
                  ),
                  child: const Text('Сохранить'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bottom sheet: Data Management ───────────────────────────
  void _showDataManagementSheet(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navBg = isDark ? AppColors.navDark : AppColors.navLight;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: navBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              settings.tr('data_management'),
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Iconsax.trash, color: Colors.white),
              title: Text(settings.tr('clear_tasks'), style: const TextStyle(color: Colors.white, fontSize: 16)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmAction(context, settings.tr('clear_tasks'), () {
                  taskProvider.clearAllTasks();
                });
              },
            ),
            ListTile(
              leading: const Icon(Iconsax.folder_minus, color: Colors.white),
              title: Text(settings.tr('clear_folders'), style: const TextStyle(color: Colors.white, fontSize: 16)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmAction(context, settings.tr('clear_folders'), () {
                  taskProvider.clearAllFolders();
                });
              },
            ),
            ListTile(
              leading: const Icon(Iconsax.refresh, color: Colors.redAccent),
              title: Text(
                settings.tr('clear_all'),
                style: const TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _confirmAction(context, settings.tr('clear_all'), () {
                  taskProvider.clearAllData();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmAction(BuildContext context, String title, VoidCallback onConfirm) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(settings.tr('confirm_clear')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(settings.tr('cancel'), style: TextStyle(color: AppColors.textSecondaryLight)),
          ),
          TextButton(
            onPressed: () {
              onConfirm();
              Navigator.pop(ctx);
            },
            child: Text(settings.tr('delete'), style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  // ── Bottom sheet: About ─────────────────────────────────────
  void _showAboutSheet(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navBg = isDark ? AppColors.navDark : AppColors.navLight;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: navBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Iconsax.task_square, color: Colors.white, size: 36),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              settings.tr('about_title'),
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              settings.tr('version'),
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Text(
              settings.tr('about_desc'),
              style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgDark : AppColors.bgLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const SizedBox(height: 40),

            // ── Avatar circle ────
            Center(
              child: GestureDetector(
                onTap: () {
                  if (settings.avatarPath != null && File(settings.avatarPath!).existsSync()) {
                    _showAvatarFullScreen(context, settings.avatarPath!);
                  } else {
                    _pickAvatar(context);
                  }
                },
                child: Hero(
                  tag: 'avatar_hero',
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: surface,
                      border: Border.all(
                        color: isDark ? Colors.white24 : Colors.black26,
                        width: 2,
                      ),
                      image: (settings.avatarPath != null && File(settings.avatarPath!).existsSync())
                          ? DecorationImage(
                              image: FileImage(File(settings.avatarPath!)),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: (settings.avatarPath == null || !File(settings.avatarPath!).existsSync())
                        ? Icon(
                            Icons.person,
                            size: 52,
                            color: textSecondary,
                          )
                        : null,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── "Сменить аватар" button ──
            Center(
              child: GestureDetector(
                onTap: () => _pickAvatar(context),
                child: Container(
                  height: AppTheme.rowHeight,
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(AppTheme.pillRadius),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.rowPadH,
                    vertical: AppTheme.rowPadV,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Iconsax.profile_circle, color: textSecondary, size: 24),
                      const SizedBox(width: AppTheme.rowGap),
                      Text(
                        settings.tr('change_avatar'),
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // ── Settings options ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.screenPad),
              child: Column(
                children: [
                  // Уведомления
                  _settingRow(
                    context,
                    surface: surface,
                    icon: Iconsax.notification,
                    label: settings.tr('notifications'),
                    textColor: textSecondary,
                    trailing: Switch(
                      value: settings.notificationsEnabled,
                      onChanged: settings.toggleNotifications,
                      activeThumbColor: AppColors.primary,
                      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Тема приложения
                  _settingRow(
                    context,
                    surface: surface,
                    icon: Iconsax.sun_1,
                    label: settings.tr('theme'),
                    textColor: textSecondary,
                    trailing: Builder(
                      builder: (switchCtx) {
                        return Switch(
                          value: settings.isDarkMode,
                          onChanged: (_) {
                            final box = switchCtx.findRenderObject() as RenderBox?;
                            final center = box != null
                                ? box.localToGlobal(box.size.center(Offset.zero))
                                : Offset(MediaQuery.of(context).size.width / 2, MediaQuery.of(context).size.height / 2);
                            
                            ThemeSwitcher.switchTheme(
                              context: context,
                              center: center,
                              onToggle: () => settings.toggleTheme(),
                              animationSpeed: settings.animationSpeed,
                            );
                          },
                          activeThumbColor: AppColors.primary,
                          trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Управление данными
                  _settingRow(
                    context,
                    surface: surface,
                    icon: Iconsax.data,
                    label: settings.tr('data_management'),
                    textColor: textSecondary,
                    onTap: () => _showDataManagementSheet(context),
                    trailing: Icon(Icons.chevron_right, color: textSecondary, size: 22),
                  ),
                  const SizedBox(height: 8),

                  // Язык
                  _settingRow(
                    context,
                    surface: surface,
                    icon: Iconsax.language_square,
                    label: '${settings.tr('language')}: ${settings.tr('lang_name')}',
                    textColor: textSecondary,
                    onTap: () => _showLanguageSheet(context),
                    trailing: Icon(Icons.chevron_right, color: textSecondary, size: 22),
                  ),
                  const SizedBox(height: 8),

                  // Плавность анимации
                  _settingRow(
                    context,
                    surface: surface,
                    icon: Iconsax.timer_1, // Using a timer/clock icon
                    label: '${settings.tr('animation_speed')}: ${_getAnimationSpeedLabel(settings)}',
                    textColor: textSecondary,
                    onTap: () => _showAnimationSpeedSheet(context),
                    trailing: Icon(Icons.chevron_right, color: textSecondary, size: 22),
                  ),
                  const SizedBox(height: 8),

                  // О приложении
                  _settingRow(
                    context,
                    surface: surface,
                    icon: Iconsax.info_circle,
                    label: settings.tr('about'),
                    textColor: textSecondary,
                    onTap: () => _showAboutSheet(context),
                    trailing: Icon(Icons.chevron_right, color: textSecondary, size: 22),
                  ),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingRow(
    BuildContext context, {
    required Color surface,
    required IconData icon,
    required String label,
    required Color textColor,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: AppTheme.rowHeight,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.rowPadH,
          vertical: AppTheme.rowPadV,
        ),
        child: Row(
          children: [
            Icon(icon, color: textColor, size: 24),
            const SizedBox(width: AppTheme.rowGap),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}
