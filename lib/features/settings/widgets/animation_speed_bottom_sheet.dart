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
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
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
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _speedTile(ctx, settings, 0.5, 'speed_fast'),
          _speedTile(ctx, settings, 1.0, 'speed_normal'),
          _speedTile(ctx, settings, 2.0, 'speed_slow'),
          if (settings.customAnimationSpeeds.isNotEmpty) ...[
            const Divider(color: Colors.white24, height: 16),
            for (final speed in settings.customAnimationSpeeds)
              _speedTile(
                ctx,
                settings,
                speed,
                'speed_custom',
                suffix: _formatSpeed(speed),
              ),
          ],
          const Divider(color: Colors.white24, height: 16),
          Material(
            color: Colors.transparent,
            child: ListTile(
              leading: const Icon(Iconsax.add, color: Colors.white, size: 24),
              title: Text(
                settings.tr('speed_custom'),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              onTap: () {
                Navigator.pop(ctx);
                showCustomSpeedSheet(context);
              },
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _speedTile(
  BuildContext ctx,
  SettingsProvider settings,
  double value,
  String labelKey, {
  String? suffix,
}) {
  final isSelected = (settings.animationSpeed - value).abs() < 0.01;
  final label = suffix != null
      ? '${settings.tr(labelKey)} ($suffix)'
      : settings.tr(labelKey);
  return Material(
    color: Colors.transparent,
    child: ListTile(
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      trailing: isSelected
          ? const Icon(Icons.check, color: AppColors.primary)
          : null,
      onTap: () {
        settings.setAnimationSpeed(value);
        Navigator.pop(ctx);
      },
    ),
  );
}

String _formatSpeed(double speed) {
  return speed == speed.truncateToDouble()
      ? speed.toInt().toString()
      : speed.toStringAsFixed(1);
}

void showCustomSpeedSheet(BuildContext context) {
  final settings = Provider.of<SettingsProvider>(context, listen: false);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final sheetBg = isDark ? AppColors.sheetDark : AppColors.sheetLight;
  final inputBg = isDark ? AppColors.surfaceSecondaryDark : AppColors.surfaceSecondaryLight;
  final controller = TextEditingController(text: settings.animationSpeed.toString());

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
                  color: isDark ? Colors.white : Colors.black26,
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
                  Icon(Iconsax.timer_1, color: isDark ? Colors.white70 : Colors.black54, size: 24),
                  const SizedBox(width: AppTheme.rowGap),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [numericInputFormatter()],
                      style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: '1.0',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black54,
                          fontSize: 16,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (val) => _trySaveCustom(ctx, controller, settings),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                settings.tr('speed_range'),
                style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 14),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: ElevatedButton(
                onPressed: () => _trySaveCustom(ctx, controller, settings),
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

void _trySaveCustom(
  BuildContext ctx,
  TextEditingController controller,
  SettingsProvider settings,
) {
  final v = controller.text.trim();
  final parsed = double.tryParse(v);
  if (parsed == null || parsed < 0.1 || parsed > 5.0) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(settings.tr('speed_error'))),
    );
    return;
  }
  settings.addCustomAnimationSpeed(parsed);
  Navigator.pop(ctx);
}
