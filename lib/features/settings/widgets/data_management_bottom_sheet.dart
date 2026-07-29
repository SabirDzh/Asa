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
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildTile(
              icon: Iconsax.export,
              title: settings.tr('export_data'),
              onTap: () async {
                Navigator.pop(ctx);
                final result = await ExportImportService.exportAndShare(taskProvider);
                if (context.mounted) {
                  final message = result.success
                      ? settings.tr('export_success')
                      : result.error != null
                          ? '${settings.tr('export_failed')}: ${result.error}'
                          : settings.tr('export_failed');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(message)),
                  );
                }
              },
            ),
            _buildTile(
              icon: Iconsax.import,
              title: settings.tr('import_data'),
              onTap: () async {
                Navigator.pop(ctx);
                final result = await ExportImportService.importFromFile(taskProvider);
                if (context.mounted) {
                  final message = result.success
                      ? settings.tr('import_success')
                      : result.error != null
                          ? '${settings.tr('import_failed')}: ${result.error}'
                          : settings.tr('import_failed');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(message)),
                  );
                }
              },
            ),
            _buildTile(
              icon: Iconsax.send_2,
              title: settings.tr('send_logs'),
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
            const Divider(color: Colors.white24, height: 16),
            _buildTile(
              icon: Iconsax.trash,
              title: settings.tr('clear_tasks'),
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

Widget _buildTile({
  required IconData icon,
  required String title,
  required VoidCallback onTap,
  Color? titleColor,
}) {
  return Material(
    color: Colors.transparent,
    child: ListTile(
      leading: Icon(icon, color: titleColor ?? Colors.white),
      title: Text(
        title,
        style: TextStyle(
          color: titleColor ?? Colors.white,
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
