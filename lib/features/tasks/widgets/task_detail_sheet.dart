import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../settings/providers/settings_provider.dart';
import '../models/task_model.dart';
import '../providers/task_provider.dart';

/// Shows a read-only bottom sheet with detailed task information.
Future<void> showTaskDetailSheet(BuildContext context, TaskItem task) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _TaskDetailSheet(task: task),
  );
}

class _TaskDetailSheet extends StatelessWidget {
  final TaskItem task;

  const _TaskDetailSheet({required this.task});

  String _folderName(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    if (task.folderId == null) return settings.tr('no_folder');
    final folder = Provider.of<TaskProvider>(
      context,
      listen: false,
    ).folders.firstWhere(
      (f) => f.id == task.folderId,
      orElse: () => FolderItem(id: '', name: ''),
    );
    return folder.name.isNotEmpty ? folder.name : settings.tr('no_folder');
  }

  String _statusText(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    return task.isCompleted
        ? settings.tr('status_completed')
        : settings.tr('status_active');
  }

  /// The system streak folder is regenerated every day, so tasks inside it
  /// cannot be linked to calendar events.
  bool get _isInStreakFolder => task.folderId == 'system_streak_folder';

  String _formatDateTime(DateTime date) {
    final d =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    final t =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return '$d $t';
  }

  String _formatDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '$h:${m.toString().padLeft(2, '0')}';
  }

  String _timeInfo(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final buffer = StringBuffer();
    final duration = task.effectiveDurationMinutes;
    if (duration != null) {
      buffer.write('${settings.tr('duration')}: ${_formatDuration(duration)}');
    }
    if (task.startTime != null || task.endTime != null) {
      if (buffer.isNotEmpty) buffer.write('  ·  ');
      final start =
          task.startTime != null
              ? '${task.startTime!.hour.toString().padLeft(2, '0')}:${task.startTime!.minute.toString().padLeft(2, '0')}'
              : '–';
      final end =
          task.endTime != null
              ? '${task.endTime!.hour.toString().padLeft(2, '0')}:${task.endTime!.minute.toString().padLeft(2, '0')}'
              : '–';
      buffer.write('${settings.tr('time_period')}: $start – $end');
    }
    if (buffer.isEmpty) return settings.tr('no_duration');
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final taskProvider = context.watch<TaskProvider>();
    final isTimerRunning = taskProvider.isTimerRunning(task.id);
    final elapsed = taskProvider.elapsedForTask(task.id);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? AppColors.sheetDark : AppColors.sheetLight;
    final textColor = isDark ? AppColors.textDark : AppColors.textLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 4,
                    decoration: BoxDecoration(
                      color: textSecondary,
                      borderRadius: BorderRadius.circular(
                        AppTheme.sheetHandleRadius,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  settings.tr('task_details'),
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                _infoTile(
                  Iconsax.clipboard_tick,
                  task.title,
                  textColor,
                  bold: true,
                ),
                _infoTile(
                  Iconsax.folder_minus,
                  '${settings.tr('folder')}: ${_folderName(context)}',
                  textColor,
                ),
                _infoTile(
                  Iconsax.clock,
                  '${settings.tr('task_status')}: ${_statusText(context)}',
                  textColor,
                ),
                _infoTile(Iconsax.timer_1, _timeInfo(context), textColor),
                if (task.effectiveDurationMinutes != null &&
                    task.effectiveDurationMinutes! > 0)
                  _infoTile(
                    isTimerRunning ? Iconsax.pause_circle : Iconsax.play_circle,
                    '${settings.tr(isTimerRunning ? 'timer_running' : 'timer_ready')}: ${_formatDuration(elapsed.inMinutes)}',
                    textColor,
                  ),
                if (!_isInStreakFolder)
                  _infoTile(
                    task.calendarEventId != null
                        ? Iconsax.calendar
                        : Iconsax.calendar_remove,
                    '${settings.tr('calendar_status')}: ${task.calendarEventId != null ? settings.tr('calendar_linked') : settings.tr('calendar_not_linked')}',
                    textColor,
                  ),
                _infoTile(
                  Iconsax.calendar_1,
                  '${settings.tr('created_at')}: ${_formatDateTime(task.createdAt)}',
                  textSecondary,
                ),
                _infoTile(
                  Iconsax.refresh,
                  '${settings.tr('updated_at')}: ${_formatDateTime(task.updatedAt)}',
                  textSecondary,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoTile(
    IconData icon,
    String text,
    Color color, {
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
