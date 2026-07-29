import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../core/export_import_service.dart';
import '../../../core/logger_service.dart';
import '../providers/settings_provider.dart';
import '../../tasks/providers/task_provider.dart';

void showDataManagementSheet(BuildContext context) {
  final settings = Provider.of<SettingsProvider>(context, listen: false);
  final taskProvider = Provider.of<TaskProvider>(context, listen: false);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final sheetBg = isDark ? AppColors.sheetDark : AppColors.sheetLight;
  final textColor = _sheetTextColor(sheetBg);

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(ctx).size.height * 0.7,
      ),
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              settings.tr('data_management'),
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildTile(
              icon: Iconsax.export,
              title: settings.tr('export_data'),
              defaultColor: textColor,
              onTap: () async {
                Navigator.pop(ctx);
                final result = await ExportImportService.exportAndShare(taskProvider);
                if (context.mounted) {
                  final message = _formatResultMessage(
                    success: result.success,
                    error: result.error,
                    successKey: 'export_success',
                    failedKey: 'export_failed',
                    settings: settings,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(message)),
                  );
                }
              },
            ),
            _buildTile(
              icon: Iconsax.import,
              title: settings.tr('import_data'),
              defaultColor: textColor,
              onTap: () async {
                Navigator.pop(ctx);
                final result = await ExportImportService.importFromFile(taskProvider);
                if (context.mounted && !result.cancelled) {
                  final message = _formatResultMessage(
                    success: result.success,
                    error: result.error,
                    successKey: 'import_success',
                    failedKey: 'import_failed',
                    settings: settings,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(message)),
                  );
                }
              },
            ),
            _buildTile(
              icon: Iconsax.send_2,
              title: settings.tr('send_logs'),
              defaultColor: textColor,
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await LoggerService.instance.sendToTelegram();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ok ? settings.tr('logs_sent') : settings.tr('logs_failed'),
                      ),
                    ),
                  );
                }
              },
            ),
            Divider(color: textColor.withAlpha(24), height: 16),
            _buildTile(
              icon: Iconsax.trash,
              title: settings.tr('clear_tasks'),
              defaultColor: textColor,
              onTap: () {
                Navigator.pop(ctx);
                _confirmAction(context, settings.tr('clear_tasks'), () {
                  taskProvider.clearAllTasks();
                });
              },
            ),
            _buildTile(
              icon: Iconsax.folder_minus,
              title: settings.tr('clear_folders'),
              defaultColor: textColor,
              onTap: () {
                Navigator.pop(ctx);
                _confirmAction(context, settings.tr('clear_folders'), () {
                  taskProvider.clearAllFolders();
                });
              },
            ),
            _buildTile(
              icon: Iconsax.refresh,
              title: settings.tr('clear_all'),
              defaultColor: textColor,
              titleColor: Colors.redAccent,
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
    ),
  );
}

/// Returns a text color that is readable against the given sheet background.
Color _sheetTextColor(Color background) {
  return background.computeLuminance() > 0.5 ? AppColors.textLight : AppColors.textDark;
}

/// Formats a success/failure message for export/import operations.
/// [error] may be a localization key or a raw exception string.
String _formatResultMessage({
  required bool success,
  required String? error,
  required String successKey,
  required String failedKey,
  required SettingsProvider settings,
}) {
  if (success) return settings.tr(successKey);
  final base = settings.tr(failedKey);
  if (error == null || error.isEmpty) return base;
  final translated = settings.tr(error);
  if (translated != error) return '$base: $translated';
  return '$base: $error';
}

Widget _buildTile({
  required IconData icon,
  required String title,
  required VoidCallback onTap,
  required Color defaultColor,
  Color? titleColor,
}) {
  return Material(
    color: Colors.transparent,
    child: ListTile(
      leading: Icon(icon, color: titleColor ?? defaultColor),
      title: Text(
        title,
        style: TextStyle(
          color: titleColor ?? defaultColor,
          fontSize: 16,
        ),
      ),
      onTap: onTap,
    ),
  );
}

void _confirmAction(BuildContext context, String title, VoidCallback onConfirm) {
  final settings = Provider.of<SettingsProvider>(context, listen: false);
  showDialog(
    context: context,
    builder: (ctx) {
      final cancelColor = Theme.of(ctx).brightness == Brightness.dark
          ? AppColors.textSecondaryDark
          : AppColors.textSecondaryLight;
      return AlertDialog(
        title: Text(title),
        content: Text(settings.tr('confirm_clear')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(settings.tr('cancel'), style: TextStyle(color: cancelColor)),
          ),
          TextButton(
            onPressed: () {
              onConfirm();
              Navigator.pop(ctx);
            },
            child: Text(settings.tr('delete'), style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      );
    },
  );
}
