import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../core/input_utils.dart';
import '../../../core/scale_utils.dart';
import '../providers/settings_provider.dart';

const double _kStep = 0.05;
const double _kSmallPreset = 0.8;
const double _kDefaultPreset = 1.0;
const double _kLargePreset = 1.2;

String appScaleLabel(BuildContext context, SettingsProvider settings) {
  final scale = effectiveAppScale(context, settings.appScale);
  if ((scale - _kSmallPreset).abs() < _kStep / 2) return settings.tr('scale_small');
  if ((scale - _kDefaultPreset).abs() < _kStep / 2) return settings.tr('scale_default');
  if ((scale - _kLargePreset).abs() < _kStep / 2) return settings.tr('scale_large');
  return '${settings.tr('scale_custom')} (${scale.toStringAsFixed(2)})';
}

void showAppScaleSheet(BuildContext context) {
  final settings = Provider.of<SettingsProvider>(context, listen: false);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final sheetBg = isDark ? AppColors.sheetDark : AppColors.sheetLight;
  final range = getAdaptiveScaleRange(context);

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
            settings.tr('app_scale'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (_kSmallPreset >= range.min && _kSmallPreset <= range.max)
            _scaleTile(ctx, settings, value: _kSmallPreset, labelKey: 'scale_small'),
          if (_kDefaultPreset >= range.min && _kDefaultPreset <= range.max)
            _scaleTile(ctx, settings, value: _kDefaultPreset, labelKey: 'scale_default'),
          if (_kLargePreset >= range.min && _kLargePreset <= range.max)
            _scaleTile(ctx, settings, value: _kLargePreset, labelKey: 'scale_large'),
          if (settings.customAppScales.isNotEmpty) ...[
            const Divider(color: Colors.white24, height: 16),
            for (final scale in settings.customAppScales)
              _scaleTile(
                ctx,
                settings,
                value: scale,
                labelKey: 'scale_custom',
                suffix: scale.toStringAsFixed(2),
              ),
          ],
          const Divider(color: Colors.white24, height: 16),
          Material(
            color: Colors.transparent,
            child: ListTile(
              leading: const Icon(Iconsax.add, color: Colors.white, size: 24),
              title: Text(
                settings.tr('scale_custom'),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _showCustomScaleSheet(context, settings, range);
              },
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _scaleTile(
  BuildContext ctx,
  SettingsProvider settings, {
  required double value,
  required String labelKey,
  String? suffix,
}) {
  final isSelected = (settings.appScale - value).abs() < _kStep / 2;
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
        settings.setAppScale(value);
        Navigator.pop(ctx);
      },
    ),
  );
}

void _showCustomScaleSheet(BuildContext context, SettingsProvider settings, AdaptiveAppScaleRange range) {
  final clamped = settings.appScale.clamp(range.min, range.max);
  final controller = TextEditingController(
    text: clamped.toStringAsFixed(2),
  );
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final sheetBg = isDark ? AppColors.sheetDark : AppColors.sheetLight;
  final inputBg = AppColors.surfaceSecondaryDark;

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
                  borderRadius:
                      BorderRadius.circular(AppTheme.sheetHandleRadius),
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
                  const Icon(Iconsax.maximize, color: Colors.white, size: 24),
                  const SizedBox(width: AppTheme.rowGap),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [numericInputFormatter()],
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: '1.00',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 16,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                '${range.min.toStringAsFixed(2)} – ${range.max.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: ElevatedButton(
                onPressed: () {
                  final parsed = double.tryParse(controller.text.trim());
                  if (parsed == null) return;
                  settings.addCustomAppScale(parsed, range.min, range.max);
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
