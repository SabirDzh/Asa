import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../core/scale_utils.dart';
import '../providers/settings_provider.dart';

const double _kStep = 0.05;
const double _kSmallPreset = 0.8;
const double _kDefaultPreset = 1.0;
const double _kLargePreset = 1.2;

String appScaleLabel(BuildContext context, SettingsProvider settings) {
  final storedScale = settings.appScale;
  final effectiveScale = effectiveAppScale(context, storedScale);

  String? presetLabel;
  if ((storedScale - _kSmallPreset).abs() < _kStep / 2) {
    presetLabel = settings.tr('scale_small');
  } else if ((storedScale - _kDefaultPreset).abs() < _kStep / 2) {
    presetLabel = settings.tr('scale_default');
  } else if ((storedScale - _kLargePreset).abs() < _kStep / 2) {
    presetLabel = settings.tr('scale_large');
  }

  if (presetLabel != null) {
    return presetLabel;
  }
  return '${settings.tr('scale_custom')} (${effectiveScale.toStringAsFixed(2)})';
}

void showAppScaleSheet(BuildContext context) {
  final settings = Provider.of<SettingsProvider>(context, listen: false);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final sheetBg = isDark ? AppColors.sheetDark : AppColors.sheetLight;
  final textColor = isDark ? AppColors.textDark : AppColors.textLight;
  final range = getAdaptiveScaleRange(context);

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    enableDrag: true,
    builder:
        (ctx) => Container(
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(20),
          child: ListenableBuilder(
            listenable: settings,
            builder:
                (context, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      settings.tr('app_scale'),
                      style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_kSmallPreset >= range.min &&
                        _kSmallPreset <= range.max)
                      _scaleTile(
                        ctx,
                        settings,
                        value: _kSmallPreset,
                        labelKey: 'scale_small',
                        textColor: textColor,
                      ),
                    if (_kDefaultPreset >= range.min &&
                        _kDefaultPreset <= range.max)
                      _scaleTile(
                        ctx,
                        settings,
                        value: _kDefaultPreset,
                        labelKey: 'scale_default',
                        textColor: textColor,
                      ),
                    if (_kLargePreset >= range.min &&
                        _kLargePreset <= range.max)
                      _scaleTile(
                        ctx,
                        settings,
                        value: _kLargePreset,
                        labelKey: 'scale_large',
                        textColor: textColor,
                      ),
                    if (settings.customAppScales.isNotEmpty) ...[
                      Divider(
                        color: textColor.withValues(alpha: 0.15),
                        height: 16,
                      ),
                      for (final scale in settings.customAppScales)
                        _scaleTile(
                          ctx,
                          settings,
                          value: scale,
                          labelKey: 'scale_custom',
                          textColor: textColor,
                          suffix: scale.toStringAsFixed(2),
                          onLongPress:
                              () => _confirmRemoveCustomScale(
                                ctx,
                                settings,
                                scale,
                              ),
                        ),
                    ],
                    Divider(
                      color: textColor.withValues(alpha: 0.15),
                      height: 16,
                    ),
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        leading: Icon(Iconsax.add, color: textColor, size: 24),
                        title: Text(
                          settings.tr('scale_custom'),
                          style: TextStyle(color: textColor, fontSize: 16),
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
        ),
  );
}

Widget _scaleTile(
  BuildContext ctx,
  SettingsProvider settings, {
  required double value,
  required String labelKey,
  required Color textColor,
  String? suffix,
  VoidCallback? onLongPress,
}) {
  final isSelected = (settings.appScale - value).abs() < _kStep / 2;
  final label =
      suffix != null
          ? '${settings.tr(labelKey)} ($suffix)'
          : settings.tr(labelKey);
  return Material(
    color: Colors.transparent,
    child: ListTile(
      title: Text(label, style: TextStyle(color: textColor, fontSize: 16)),
      trailing:
          isSelected ? const Icon(Icons.check, color: AppColors.primary) : null,
      onTap: () {
        settings.setAppScale(value);
        Navigator.pop(ctx);
      },
      onLongPress: onLongPress,
    ),
  );
}

Future<void> _confirmRemoveCustomScale(
  BuildContext context,
  SettingsProvider settings,
  double scale,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: Text(settings.tr('delete_custom_value_title')),
          content: Text(settings.tr('delete_custom_value_content')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(settings.tr('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                settings.tr('delete'),
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
  );
  if (confirmed == true) {
    await settings.removeCustomAppScale(scale);
  }
}

void _showCustomScaleSheet(
  BuildContext context,
  SettingsProvider settings,
  AdaptiveAppScaleRange range,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final sheetBg = isDark ? AppColors.sheetDark : AppColors.sheetLight;
  final textColor = isDark ? AppColors.textDark : AppColors.textLight;
  final textSecondary =
      isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
  final divisions = ((range.max - range.min) / _kStep).round();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      double value = settings.appScale.clamp(range.min, range.max);
      return StatefulBuilder(
        builder: (context, setState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
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
                    settings.tr('app_scale'),
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    value.toStringAsFixed(2),
                    style: TextStyle(
                      color: textColor,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${range.min.toStringAsFixed(2)} – ${range.max.toStringAsFixed(2)}',
                    style: TextStyle(color: textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor:
                          isDark ? Colors.white24 : Colors.black12,
                      thumbColor: AppColors.primary,
                      overlayColor: AppColors.primary.withValues(alpha: 0.12),
                      tickMarkShape: const RoundSliderTickMarkShape(
                        tickMarkRadius: 2,
                      ),
                      activeTickMarkColor: Colors.transparent,
                      inactiveTickMarkColor: Colors.transparent,
                    ),
                    child: Slider(
                      value: value,
                      min: range.min,
                      max: range.max,
                      divisions: divisions,
                      label: value.toStringAsFixed(2),
                      onChanged: (v) => setState(() => value = v),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: ElevatedButton(
                      onPressed: () {
                        settings.addCustomAppScale(value, range.min, range.max);
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.pillRadius,
                          ),
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
