import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../core/input_utils.dart';
import '../providers/settings_provider.dart';

String animationSpeedLabel(SettingsProvider settings) {
  if (settings.animationSpeed == 0.5) return settings.tr('speed_fast');
  if (settings.animationSpeed == 1.0) return settings.tr('speed_normal');
  if (settings.animationSpeed == 2.0) return settings.tr('speed_slow');
  final formatted = settings.animationSpeed == settings.animationSpeed.truncateToDouble()
      ? settings.animationSpeed.toInt().toString()
      : settings.animationSpeed.toStringAsFixed(1);
  return '${settings.tr('speed_custom')} ($formatted)';
}

void showAnimationSpeedSheet(BuildContext context) {
  final settings = Provider.of<SettingsProvider>(context, listen: false);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final sheetBg = isDark ? AppColors.sheetDark : AppColors.sheetLight;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,      builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: sheetBg,
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
            Material(color: Colors.transparent, child: ListTile(
              title: Text(settings.tr('speed_fast'), style: const TextStyle(color: Colors.white, fontSize: 16)),
              trailing: settings.animationSpeed == 0.5
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                settings.setAnimationSpeed(0.5);
                Navigator.pop(ctx);
              },
            )),
            Material(color: Colors.transparent, child: ListTile(
              title: Text(settings.tr('speed_normal'), style: const TextStyle(color: Colors.white, fontSize: 16)),
              trailing: settings.animationSpeed == 1.0
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                settings.setAnimationSpeed(1.0);
                Navigator.pop(ctx);
              },
            )),
            Material(color: Colors.transparent, child: ListTile(
              title: Text(settings.tr('speed_slow'), style: const TextStyle(color: Colors.white, fontSize: 16)),
              trailing: settings.animationSpeed == 2.0
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                settings.setAnimationSpeed(2.0);
                Navigator.pop(ctx);
              },
            )),
            Material(color: Colors.transparent, child: ListTile(
              title: Text(settings.tr('speed_custom'), style: const TextStyle(color: Colors.white, fontSize: 16)),
              trailing: settings.animationSpeed != 0.5 && settings.animationSpeed != 1.0 && settings.animationSpeed != 2.0
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                showCustomSpeedSheet(context);
              },
            )),
          ],
      ),
    ),
  );
}

void showCustomSpeedSheet(BuildContext context) {
  final settings = Provider.of<SettingsProvider>(context, listen: false);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final sheetBg = isDark ? AppColors.sheetDark : AppColors.sheetLight;
  final inputBg = AppColors.surfaceSecondaryDark;
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
                            SnackBar(content: Text(settings.tr('speed_error'))),
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
                settings.tr('speed_range'),
                style: const TextStyle(color: Colors.white70, fontSize: 14),
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
                      SnackBar(content: Text(settings.tr('speed_error'))),
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
                child: Text(settings.tr('save_btn')),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
