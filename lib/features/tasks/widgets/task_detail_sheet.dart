import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/task_attachment_service.dart';
import '../../../core/theme.dart';
import '../../settings/providers/settings_provider.dart';
import '../models/task_info_block.dart';
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

  String _quantityText(TaskInfoBlock block, SettingsProvider settings) {
    final name =
        block.label.trim().isEmpty
            ? settings.tr('quantity_block')
            : block.label.trim();
    final current = _formatNumber(block.currentValue);
    final target = _formatNumber(block.targetValue);
    return '$name: $current / $target ${block.unit.trim()}';
  }

  String _formatNumber(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  Widget _buildInfoBlocks(BuildContext context, Color textColor) {
    if (task.infoBlocks.isEmpty) return const SizedBox.shrink();
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        _sectionHeader(
          Iconsax.document_text,
          settings.tr('add_information'),
          textColor,
        ),
        const SizedBox(height: 8),
        for (final block in task.infoBlocks)
          _buildInfoBlock(context, block, settings, textColor),
      ],
    );
  }

  Widget _buildInfoBlock(
    BuildContext context,
    TaskInfoBlock block,
    SettingsProvider settings,
    Color textColor,
  ) {
    final title =
        block.type == TaskInfoBlockType.quantity
            ? _quantityText(block, settings)
            : settings.tr('description_block');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: textColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              block.type == TaskInfoBlockType.quantity
                  ? Iconsax.chart_2
                  : Iconsax.document_text,
              title,
              textColor,
            ),
            if (block.type == TaskInfoBlockType.description &&
                block.text.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(block.text.trim(), style: TextStyle(color: textColor)),
            ],
            if (block.attachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final attachment in block.attachments)
                    ActionChip(
                      key: ValueKey('detail-attachment-${attachment.id}'),
                      avatar: Icon(
                        attachment.type == TaskAttachmentType.link
                            ? Icons.link
                            : Icons.attach_file,
                        size: 18,
                      ),
                      label: Text(attachment.name),
                      onPressed: () => _openAttachment(context, attachment),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Future<void> _openAttachment(
    BuildContext context,
    TaskAttachment attachment,
  ) async {
    final opened = await openTaskAttachment(attachment);
    if (!context.mounted || opened) return;
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(settings.tr('attachment_unavailable'))),
    );
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
                _buildInfoBlocks(context, textColor),
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
