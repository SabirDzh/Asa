import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/export_import_service.dart';
import '../../../core/theme.dart';
import '../providers/settings_provider.dart';
import '../../tasks/providers/task_provider.dart';

/// Shows a preview of the selected import file. If the user confirms, the
/// import is performed and the result is reported via the [onResult] callback.
void showImportPreviewBottomSheet(
  BuildContext context, {
  required ImportPreview preview,
  required List<int> bytes,
  required TaskProvider taskProvider,
  required ValueChanged<ImportResult> onResult,
}) {
  final settings = Provider.of<SettingsProvider>(context, listen: false);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final sheetBg = isDark ? AppColors.sheetDark : AppColors.sheetLight;
  final textColor = isDark ? AppColors.textDark : AppColors.textLight;
  final textSecondary =
      isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    enableDrag: true,
    builder:
        (ctx) => Padding(
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
            padding: const EdgeInsets.all(20),
            child: SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      settings.tr('import_preview_title'),
                      style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildInfoTile(
                      icon: Iconsax.document,
                      label: settings.tr('import_preview_file'),
                      value: preview.fileName,
                      textColor: textColor,
                      textSecondary: textSecondary,
                    ),
                    _buildInfoTile(
                      icon: Iconsax.size,
                      label: settings.tr('import_preview_size'),
                      value: preview.fileSizeLabel,
                      textColor: textColor,
                      textSecondary: textSecondary,
                    ),
                    if (preview.isValid) ...[
                      _buildInfoTile(
                        icon: Iconsax.task_square,
                        label: settings.tr('import_preview_tasks'),
                        value: preview.taskCount.toString(),
                        textColor: textColor,
                        textSecondary: textSecondary,
                      ),
                      _buildInfoTile(
                        icon: Iconsax.folder,
                        label: settings.tr('import_preview_folders'),
                        value: preview.folderCount.toString(),
                        textColor: textColor,
                        textSecondary: textSecondary,
                      ),
                      _buildInfoTile(
                        icon: Iconsax.code,
                        label: settings.tr('import_preview_version'),
                        value: preview.version ?? '-',
                        textColor: textColor,
                        textSecondary: textSecondary,
                      ),
                      if (preview.exportedAt != null)
                        _buildInfoTile(
                          icon: Iconsax.calendar,
                          label: settings.tr('import_preview_exported_at'),
                          value: _formatDate(preview.exportedAt!.toLocal()),
                          textColor: textColor,
                          textSecondary: textSecondary,
                        ),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            preview.isValid
                                ? AppColors.primary.withValues(alpha: 0.1)
                                : Colors.redAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            preview.isValid
                                ? Iconsax.tick_circle
                                : Iconsax.warning_2,
                            color:
                                preview.isValid
                                    ? AppColors.primary
                                    : Colors.redAccent,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              preview.isValid
                                  ? settings.tr('import_preview_valid')
                                  : settings.tr('import_preview_invalid'),
                              style: TextStyle(
                                color:
                                    preview.isValid
                                        ? textColor
                                        : Colors.redAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!preview.isValid && preview.errorKey != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        settings.tr(preview.errorKey!),
                        style: TextStyle(color: textSecondary, fontSize: 14),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: textColor,
                              side: BorderSide(
                                color: textSecondary.withValues(alpha: 0.3),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.pillRadius,
                                ),
                              ),
                            ),
                            child: Text(settings.tr('import_preview_cancel')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed:
                                preview.isValid
                                    ? () async {
                                      Navigator.pop(ctx);
                                      final result =
                                          preview.snapshot == null
                                              ? const ImportResult(
                                                error: 'error_import_failed',
                                              )
                                              : await ExportImportService.importFromSnapshot(
                                                taskProvider,
                                                preview.snapshot!,
                                              );
                                      onResult(result);
                                    }
                                    : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: textSecondary.withValues(
                                alpha: 0.2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.pillRadius,
                                ),
                              ),
                            ),
                            child: Text(settings.tr('import_preview_confirm')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
  );
}

String _formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year;
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day.$month.$year $hour:$minute';
}

Widget _buildInfoTile({
  required IconData icon,
  required String label,
  required String value,
  required Color textColor,
  required Color textSecondary,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Icon(icon, color: textSecondary, size: 20),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(color: textSecondary, fontSize: 14),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            value,
            style: TextStyle(
              color: textColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    ),
  );
}
