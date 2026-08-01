import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/task_attachment_service.dart';
import '../../../core/theme.dart';
import '../../browser/screens/in_app_browser_screen.dart';
import '../../settings/providers/settings_provider.dart';
import '../models/task_info_block.dart';
import '../models/task_model.dart';
import '../providers/task_provider.dart';
import 'description_full_sheet.dart';
import 'quantity_counter.dart';

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

  String _timeValue(DateTime? value) {
    if (value == null) return '–';
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildTimeBlock(
    BuildContext context,
    Color textColor,
    bool isTimerRunning,
    Duration elapsed,
  ) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final hasPlannedDuration = task.effectiveDurationMinutes != null;
    final hasPeriod = task.startTime != null || task.endTime != null;
    final hasActualTime =
        isTimerRunning ||
        task.timerElapsedSeconds > 0 ||
        hasPlannedDuration ||
        hasPeriod;
    if (!hasPlannedDuration && !hasPeriod && !hasActualTime) {
      return const SizedBox.shrink();
    }

    final lines = <({String label, String value})>[];
    if (hasPlannedDuration) {
      lines.add((
        label: settings.tr('duration'),
        value: _formatDuration(task.effectiveDurationMinutes!),
      ));
    }
    if (hasPeriod) {
      lines.add((
        label: settings.tr('time_period'),
        value: '${_timeValue(task.startTime)} - ${_timeValue(task.endTime)}',
      ));
    }
    if (hasActualTime) {
      lines.add((
        label: settings.tr('actual_time'),
        value: _formatDuration(elapsed.inMinutes),
      ));
    }

    return Container(
      key: const ValueKey('detail-time-block'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: textColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Iconsax.clock,
              key: const ValueKey('detail_timer_icon'),
              color: textColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in lines)
                  Padding(
                    key: ValueKey('detail-time-line-${line.label}'),
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Semantics(
                      label: '${line.label}: ${line.value}',
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(color: textColor, fontSize: 15),
                          children: [
                            TextSpan(
                              text: '${line.label}: ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(text: line.value),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentNamesLine(
    BuildContext context,
    List<TaskAttachment> attachments,
    Color textColor,
  ) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final names = attachments.map((attachment) => attachment.name).join(' · ');
    return Semantics(
      container: true,
      label:
          '${Provider.of<SettingsProvider>(context, listen: false).tr('attachments')}: $names',
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          names,
          key: const ValueKey('detail-attachment-names'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: textColor.withValues(alpha: 0.75),
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBlocks(
    BuildContext context,
    Color textColor,
    TaskItem currentTask,
  ) {
    if (currentTask.infoBlocks.isEmpty) return const SizedBox.shrink();
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        _sectionHeader(
          Iconsax.document_text,
          settings.tr('additional_information'),
          textColor,
        ),
        const SizedBox(height: 8),
        for (final block in currentTask.infoBlocks)
          _buildInfoBlock(context, currentTask, block, settings, textColor),
      ],
    );
  }

  Widget _buildInfoBlock(
    BuildContext context,
    TaskItem currentTask,
    TaskInfoBlock block,
    SettingsProvider settings,
    Color textColor,
  ) {
    final isQuantity = block.type == TaskInfoBlockType.quantity;
    final title =
        isQuantity
            ? (block.label.trim().isEmpty
                ? settings.tr('quantity_block')
                : block.label.trim())
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
              isQuantity ? Iconsax.chart_2 : Iconsax.document_text,
              title,
              textColor,
            ),
            if (isQuantity) ...[
              const SizedBox(height: 8),
              QuantityCounter(
                currentValue: block.currentValue,
                targetValue: block.targetValue,
                unit: block.unit,
                textColor: textColor,
                decreaseLabel: settings.tr('quantity_decrease'),
                increaseLabel: settings.tr('quantity_increase'),
                onAdjust:
                    (delta) => context.read<TaskProvider>().adjustQuantityBlock(
                      currentTask.id,
                      block.id,
                      delta,
                    ),
              ),
            ],
            if (block.type == TaskInfoBlockType.description &&
                block.text.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              DescriptionPreview(
                text: block.text,
                format: block.descriptionFormat,
                attachments: block.attachments,
                textColor: textColor,
                semanticsLabel: settings.tr('full_description'),
                onTap:
                    () => showFullDescriptionSheet(
                      context,
                      text: block.text,
                      format: block.descriptionFormat,
                      attachments: block.attachments,
                      title: settings.tr('full_description'),
                      onAttachmentTap:
                          (attachment) => _openAttachment(context, attachment),
                      onExternalLinkTap:
                          (href, {title}) =>
                              _openExternalLink(context, href, title: title),
                    ),
                onAttachmentTap:
                    (attachment) => _openAttachment(context, attachment),
                onExternalLinkTap:
                    (href, {title}) =>
                        _openExternalLink(context, href, title: title),
              ),
            ],
            if (block.attachments.isNotEmpty) ...[
              _buildAttachmentNamesLine(context, block.attachments, textColor),
              const SizedBox(height: 8),
              SizedBox(
                key: const ValueKey('detail-attachment-chips'),
                height: 40,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final attachment in block.attachments) ...[
                        ActionChip(
                          key: ValueKey('detail-attachment-${attachment.id}'),
                          avatar: Icon(
                            attachment.type == TaskAttachmentType.link
                                ? Icons.link
                                : attachment.type == TaskAttachmentType.image
                                ? Icons.image_outlined
                                : Icons.attach_file,
                            size: 18,
                          ),
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: Text(
                              attachment.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          onPressed: () => _openAttachment(context, attachment),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
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

  Future<void> _openExternalLink(
    BuildContext context,
    String href, {
    String? title,
  }) async {
    final normalized = normalizeTaskAttachmentLink(href);
    if (normalized == null) return;
    await openTaskLink(context, normalized, title: title);
  }

  Future<void> _openAttachment(
    BuildContext context,
    TaskAttachment attachment,
  ) async {
    final opened =
        attachment.type == TaskAttachmentType.link
            ? await openTaskLink(
              context,
              attachment.value,
              title: attachment.name,
            )
            : await openTaskAttachment(attachment);
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
    final currentTask = taskProvider.allTasks.firstWhere(
      (candidate) => candidate.id == task.id,
      orElse: () => task,
    );
    final isTimerRunning = taskProvider.isTimerRunning(currentTask.id);
    final elapsed = taskProvider.elapsedForTask(currentTask.id);
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
                _buildTimeBlock(context, textColor, isTimerRunning, elapsed),
                _buildInfoBlocks(context, textColor, currentTask),
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
    Widget? iconWidget,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          iconWidget ?? Icon(icon, color: color, size: 20),
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
