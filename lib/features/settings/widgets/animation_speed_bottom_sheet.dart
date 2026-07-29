import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
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
  final textColor = isDark ? AppColors.textDark : AppColors.textLight;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    enableDrag: true,
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
            style: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _speedTile(ctx, settings, 0.5, 'speed_fast', textColor),
          _speedTile(ctx, settings, 1.0, 'speed_normal', textColor),
          _speedTile(ctx, settings, 2.0, 'speed_slow', textColor),              if (settings.customAnimationSpeeds.isNotEmpty) ...[
            Divider(color: textColor.withValues(alpha: 0.15), height: 16),
            for (final speed in settings.customAnimationSpeeds)
              _speedTile(
                ctx,
                settings,
                speed,
                'speed_custom',
                textColor,
                suffix: _formatSpeed(speed),
              ),
          ],
          Divider(color: textColor.withValues(alpha: 0.15), height: 16),
          Material(
            color: Colors.transparent,
            child: ListTile(
              leading: Icon(Iconsax.add, color: textColor, size: 24),
              title: Text(
                settings.tr('speed_custom'),
                style: TextStyle(color: textColor, fontSize: 16),
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
  String labelKey,
  Color textColor, {
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
        style: TextStyle(color: textColor, fontSize: 16),
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

  const minSpeed = 0.1;
  const maxSpeed = 5.0;

  final textColor = isDark ? AppColors.textDark : AppColors.textLight;
  final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      double value = settings.animationSpeed.clamp(minSpeed, maxSpeed);
      return StatefulBuilder(
        builder: (context, setState) {
          return Padding(
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
                  const SizedBox(height: 8),
                  Text(
                    settings.tr('animation_speed'),
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '${_formatSpeed(value)}x',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    settings.tr('speed_range'),
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: isDark ? Colors.white24 : Colors.black12,
                      thumbColor: AppColors.primary,
                      overlayColor: AppColors.primary.withValues(alpha: 0.12),
                      tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2),
                      activeTickMarkColor: Colors.transparent,
                      inactiveTickMarkColor: Colors.transparent,
                    ),
                    child: Slider(
                      value: value,
                      min: minSpeed,
                      max: maxSpeed,
                      divisions: 49,
                      label: _formatSpeed(value),
                      onChanged: (v) => setState(() => value = v),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: ElevatedButton(
                      onPressed: () {
                        settings.addCustomAnimationSpeed(value);
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
          );
        },
      );
    },
  );
}
