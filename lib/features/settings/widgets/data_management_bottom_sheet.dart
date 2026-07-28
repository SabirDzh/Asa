import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
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
            Material(color: Colors.transparent, child: ListTile(
              leading: const Icon(Iconsax.trash, color: Colors.white),
              title: Text(settings.tr('clear_tasks'), style: const TextStyle(color: Colors.white, fontSize: 16)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmAction(context, settings.tr('clear_tasks'), () {
                  taskProvider.clearAllTasks();
                });
              },
            )),
            Material(color: Colors.transparent, child: ListTile(
              leading: const Icon(Iconsax.folder_minus, color: Colors.white),
              title: Text(settings.tr('clear_folders'), style: const TextStyle(color: Colors.white, fontSize: 16)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmAction(context, settings.tr('clear_folders'), () {
                  taskProvider.clearAllFolders();
                });
              },
            )),
            Material(color: Colors.transparent, child: ListTile(
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
            )),
          ],
      ),
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
