import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../core/input_utils.dart';
import '../providers/settings_provider.dart';

const double _kMinScale = 0.8;
const double _kMaxScale = 1.3;
const double _kStep = 0.05;

String appScaleLabel(SettingsProvider settings) {
  final scale = settings.appScale;
  if ((scale - 0.8).abs() < _kStep / 2) return settings.tr('scale_small');
  if ((scale - 1.0).abs() < _kStep / 2) return settings.tr('scale_default');
  if ((scale - 1.2).abs() < _kStep / 2) return settings.tr('scale_large');
  return '${settings.tr('scale_custom')} (${scale.toStringAsFixed(2)})';
}

void showAppScaleSheet(BuildContext context) {
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
            settings.tr('app_scale'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _scaleTile(ctx, settings, value: 0.8, labelKey: 'scale_small'),
          _scaleTile(ctx, settings, value: 1.0, labelKey: 'scale_default'),
          _scaleTile(ctx, settings, value: 1.2, labelKey: 'scale_large'),
          _customTile(ctx, settings),
          const SizedBox(height: 8),
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
}) {
  final isSelected = (settings.appScale - value).abs() < _kStep / 2;
  return Material(
    color: Colors.transparent,
    child: ListTile(
      title: Text(
        settings.tr(labelKey),
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

Widget _customTile(BuildContext ctx, SettingsProvider settings) {
  final isCustom = !((settings.appScale - 0.8).abs() < _kStep / 2) &&
      !((settings.appScale - 1.0).abs() < _kStep / 2) &&
      !((settings.appScale - 1.2).abs() < _kStep / 2);
  return Material(
    color: Colors.transparent,
    child: ListTile(
      title: Text(
        '${settings.tr('scale_custom')} (${settings.appScale.toStringAsFixed(2)})',
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      trailing: isCustom
          ? const Icon(Icons.check, color: AppColors.primary)
          : null,
      onTap: () {
        Navigator.pop(ctx);
        _showCustomScaleSheet(ctx, settings);
      },
    ),
  );
}

void _showCustomScaleSheet(BuildContext context, SettingsProvider settings) {
  final controller = TextEditingController(
    text: settings.appScale.toStringAsFixed(2),
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
                '$_kMinScale – $_kMaxScale',
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
                  settings.setAppScale(parsed);
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
