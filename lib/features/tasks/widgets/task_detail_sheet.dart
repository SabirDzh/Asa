import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/drag_close_sheet.dart';
import '../../../core/task_attachment_service.dart';
import '../../../core/theme.dart';
import '../../browser/screens/in_app_browser_screen.dart';
import '../screens/task_image_viewer_screen.dart';
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
    enableDrag: false,
    builder:
        (ctx) => DragToCloseSheet(
          trackScrollableDrag: true,
          child: _TaskDetailSheet(task: task),
        ),
  );
}

class _LiveActualTimeLine extends StatefulWidget {
  final String taskId;
  final String label;
  final Color textColor;
  final bool isTimerRunning;
  final Duration initialElapsed;

  const _LiveActualTimeLine({
    required this.taskId,
    required this.label,
    required this.textColor,
    required this.isTimerRunning,
    required this.initialElapsed,
  });

  @override
  State<_LiveActualTimeLine> createState() => _LiveActualTimeLineState();
}

class _LiveActualTimeLineState extends State<_LiveActualTimeLine> {
  Timer? _timer;
  late Duration _elapsed;

  @override
  void initState() {
    super.initState();
    _elapsed = widget.initialElapsed;
    _syncTimer();
  }

  @override
  void didUpdateWidget(_LiveActualTimeLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    final taskChanged = oldWidget.taskId != widget.taskId;
    final timerStateChanged = oldWidget.isTimerRunning != widget.isTimerRunning;
    final elapsedChanged = oldWidget.initialElapsed != widget.initialElapsed;
    if (taskChanged || timerStateChanged || elapsedChanged) {
      _elapsed = widget.initialElapsed;
      if (taskChanged || timerStateChanged) _syncTimer();
    }
  }

  void _syncTimer() {
    _timer?.cancel();
    _timer = null;
    if (!widget.isTimerRunning) return;

    final provider = context.read<TaskProvider>();
    final currentElapsed = provider.elapsedForTask(widget.taskId);
    final elapsedSeconds = currentElapsed.inSeconds % 60;
    final secondsUntilNextMinute =
        elapsedSeconds == 0 ? 60 : 60 - elapsedSeconds;
    _timer = Timer(Duration(seconds: secondsUntilNextMinute), () {
      if (!mounted) return;
      final nextElapsed = provider.elapsedForTask(widget.taskId);
      if (nextElapsed.inMinutes != _elapsed.inMinutes) {
        setState(() => _elapsed = nextElapsed);
      }
      _syncTimer();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final totalMinutes = duration.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return '$hours:${minutes.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey('detail-time-line-${widget.label}'),
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        label: '${widget.label}: ${_formatDuration(_elapsed)}',
        child: RichText(
          key: const ValueKey('detail-actual-time-value'),
          text: TextSpan(
            style: TextStyle(color: widget.textColor, fontSize: 15),
            children: [
              TextSpan(
                text: '${widget.label}: ',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(text: _formatDuration(_elapsed)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskDetailSheet extends StatelessWidget {
  final TaskItem task;

  const _TaskDetailSheet({required this.task});

  String _folderName(BuildContext context, TaskItem currentTask) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    if (currentTask.folderId == null) return settings.tr('no_folder');
    final folder = Provider.of<TaskProvider>(
      context,
      listen: false,
    ).folders.firstWhere(
      (f) => f.id == currentTask.folderId,
      orElse: () => FolderItem(id: '', name: ''),
    );
    return folder.name.isNotEmpty ? folder.name : settings.tr('no_folder');
  }

  String _statusText(BuildContext context, TaskItem currentTask) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    return currentTask.isCompleted
        ? settings.tr('status_completed')
        : settings.tr('status_active');
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  String _formatDateTime(DateTime date) {
    final d = _formatDate(date);
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
    TaskItem currentTask,
    Color textColor,
    bool isTimerRunning,
    Duration elapsed,
  ) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final hasPlannedDuration = currentTask.effectiveDurationMinutes != null;
    final hasPeriod =
        currentTask.startTime != null || currentTask.endTime != null;
    final hasActualTime =
        isTimerRunning ||
        currentTask.timerElapsedSeconds > 0 ||
        hasPlannedDuration ||
        hasPeriod;
    if (!hasPlannedDuration && !hasPeriod && !hasActualTime) {
      return const SizedBox.shrink();
    }

    final lines = <({String label, String value})>[];
    if (hasPlannedDuration) {
      lines.add((
        label: settings.tr('duration'),
        value: _formatDuration(currentTask.effectiveDurationMinutes!),
      ));
    }
    if (hasPeriod) {
      lines.add((
        label: settings.tr('time_period'),
        value:
            '${_timeValue(currentTask.startTime)} - ${_timeValue(currentTask.endTime)}',
      ));
    }
    final actualTimeLabel = settings.tr('actual_time');

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
              currentTask.calendarEventId != null &&
                      currentTask.folderId != 'system_streak_folder'
                  ? Iconsax.calendar
                  : Iconsax.timer_1,
              key: ValueKey(
                currentTask.calendarEventId != null &&
                        currentTask.folderId != 'system_streak_folder'
                    ? 'detail_calendar_icon'
                    : 'detail_timer_icon',
              ),
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
                if (hasActualTime)
                  _LiveActualTimeLine(
                    taskId: currentTask.id,
                    label: actualTimeLabel,
                    textColor: textColor,
                    isTimerRunning: isTimerRunning,
                    initialElapsed: elapsed,
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
                unit: displayQuantityUnit(block.unit, settings.tr),
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
            : attachment.type == TaskAttachmentType.image
            ? await openTaskImageViewer(context, attachment)
            : await openTaskAttachment(attachment);
    if (!context.mounted || opened) return;
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(settings.tr('attachment_unavailable'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.select<SettingsProvider, String>(
      (settings) => settings.languageCode,
    );
    final settings = context.read<SettingsProvider>();
    final taskProvider = context.watch<TaskProvider>();
    final currentTask = taskProvider.allTasks.firstWhere(
      (candidate) => candidate.id == task.id,
      orElse: () => task,
    );
    final hasProviderTask = taskProvider.allTasks.any(
      (candidate) => candidate.id == currentTask.id,
    );
    final isTimerRunning =
        hasProviderTask && taskProvider.isTimerRunning(currentTask.id);
    final elapsed =
        hasProviderTask
            ? taskProvider.elapsedForTask(currentTask.id)
            : Duration(seconds: currentTask.timerElapsedSeconds);
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
                  currentTask.title,
                  textColor,
                  bold: true,
                ),
                _infoTile(
                  Iconsax.folder_minus,
                  '${settings.tr('folder')}: ${_folderName(context, currentTask)}',
                  textColor,
                ),
                _infoTile(
                  Iconsax.clock,
                  '${settings.tr('task_status')}: ${_statusText(context, currentTask)}',
                  textColor,
                ),
                _buildTimeBlock(
                  context,
                  currentTask,
                  textColor,
                  isTimerRunning,
                  elapsed,
                ),
                if (currentTask.dueDate != null)
                  _infoTile(
                    Iconsax.calendar_1,
                    '${settings.tr('due_date')}: ${_formatDate(currentTask.dueDate!)}',
                    textColor,
                  ),
                _buildInfoBlocks(context, textColor, currentTask),
                if (currentTask.folderId != 'system_streak_folder')
                  _infoTile(
                    currentTask.calendarEventId != null
                        ? Iconsax.calendar
                        : Iconsax.calendar_remove,
                    '${settings.tr('calendar_status')}: ${currentTask.calendarEventId != null ? settings.tr('calendar_linked') : settings.tr('calendar_not_linked')}',
                    textColor,
                  ),
                _infoTile(
                  Iconsax.calendar_1,
                  '${settings.tr('created_at')}: ${_formatDateTime(currentTask.createdAt)}',
                  textSecondary,
                ),
                _infoTile(
                  Iconsax.refresh,
                  '${settings.tr('updated_at')}: ${_formatDateTime(currentTask.updatedAt)}',
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
