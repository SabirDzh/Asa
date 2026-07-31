import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../models/task_model.dart';
import '../providers/task_provider.dart';
import '../../settings/providers/settings_provider.dart';

/// Shows a bottom sheet to set the start and end period for [task].
Future<void> showTaskTimeSheet(BuildContext context, TaskItem task) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _TaskTimeSheet(task: task),
  );
}

class _TaskTimeSheet extends StatefulWidget {
  final TaskItem task;
  const _TaskTimeSheet({required this.task});

  @override
  State<_TaskTimeSheet> createState() => _TaskTimeSheetState();
}

class _TaskTimeSheetState extends State<_TaskTimeSheet> {
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  @override
  void initState() {
    super.initState();
    if (widget.task.startTime != null) {
      final dt = widget.task.startTime!;
      _startTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
    }
    if (widget.task.endTime != null) {
      final dt = widget.task.endTime!;
      _endTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
    }
  }

  bool get _hasCompletePeriod => _startTime != null && _endTime != null;

  Future<void> _pickTime(bool isStart) async {
    final current = isStart ? _startTime : _endTime;
    final initial = current ?? TimeOfDay.now();
    final titleKey = isStart ? 'start_time' : 'end_time';
    final picked = await _showWheelTimePicker(context, initial, titleKey);
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  Future<TimeOfDay?> _showWheelTimePicker(
    BuildContext context,
    TimeOfDay initialTime,
    String titleKey,
  ) async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? AppColors.sheetDark : AppColors.sheetLight;
    final textColor = isDark ? AppColors.textDark : AppColors.textLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    int hour = initialTime.hour;
    int minute = initialTime.minute;

    return showModalBottomSheet<TimeOfDay>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => Container(
            decoration: BoxDecoration(
              color: sheetBg,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    settings.tr(titleKey),
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 180,
                    child: Row(
                      children: [
                        Expanded(
                          child: _WheelList(
                            initialIndex: hour,
                            itemCount: 24,
                            label: (i) => i.toString().padLeft(2, '0'),
                            onChanged: (i) => hour = i,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            ':',
                            style: TextStyle(color: textColor, fontSize: 24),
                          ),
                        ),
                        Expanded(
                          child: _WheelList(
                            initialIndex: minute,
                            itemCount: 60,
                            label: (i) => i.toString().padLeft(2, '0'),
                            onChanged: (i) => minute = i,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                            foregroundColor: textSecondary,
                          ),
                          child: Text(settings.tr('cancel')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed:
                              () => Navigator.pop(
                                ctx,
                                TimeOfDay(hour: hour, minute: minute),
                              ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                          ),
                          child: Text(
                            settings.tr('save'),
                            style: const TextStyle(color: AppColors.textDark),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );
  }

  DateTime? _toDateTime(TimeOfDay? time) {
    if (time == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, time.hour, time.minute);
  }

  String _formatTime(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  void _save(BuildContext context) {
    if (!_hasCompletePeriod) return;
    if (_startTime!.hour == _endTime!.hour &&
        _startTime!.minute == _endTime!.minute) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Provider.of<SettingsProvider>(
              context,
              listen: false,
            ).tr('invalid_period'),
          ),
        ),
      );
      return;
    }
    final provider = context.read<TaskProvider>();
    provider.setTaskTime(
      widget.task.id,
      startTime: _toDateTime(_startTime),
      endTime: _toDateTime(_endTime),
    );
    Navigator.pop(context);
  }

  void _clear(BuildContext context) {
    context.read<TaskProvider>().setTaskTime(
      widget.task.id,
      startTime: null,
      endTime: null,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? AppColors.sheetDark : AppColors.sheetLight;
    final textColor = isDark ? AppColors.textDark : AppColors.textLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    final animationDuration = Duration(
      milliseconds: (300 * settings.animationSpeed).round(),
    );

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSize(
                duration: animationDuration,
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
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
                      settings.tr('set_time'),
                      style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _sectionTitle(Iconsax.clock, settings.tr('time_period')),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _timeButton(
                            label:
                                _startTime != null
                                    ? _formatTime(_startTime!)
                                    : settings.tr('start_time'),
                            onTap: () => _pickTime(true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _timeButton(
                            label:
                                _endTime != null
                                    ? _formatTime(_endTime!)
                                    : settings.tr('end_time'),
                            onTap: () => _pickTime(false),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => _clear(context),
                      style: TextButton.styleFrom(
                        foregroundColor: textSecondary,
                        minimumSize: const Size(
                          double.infinity,
                          AppTheme.rowHeight,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.pillRadius,
                          ),
                        ),
                      ),
                      child: Text(settings.tr('clear')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          _hasCompletePeriod ? () => _save(context) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _hasCompletePeriod
                                ? AppColors.primary
                                : AppColors.primary.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.pillRadius,
                          ),
                        ),
                      ),
                      child: Text(
                        settings.tr('save'),
                        style: const TextStyle(color: AppColors.textDark),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.textDark : AppColors.textLight;
    return Row(
      children: [
        Icon(icon, color: textColor, size: 20),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _timeButton({required String label, required VoidCallback onTap}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: AppTheme.rowHeight,
        decoration: BoxDecoration(
          color:
              isDark
                  ? AppColors.surfaceSecondaryDark
                  : AppColors.surfaceSecondaryLight,
          borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isDark ? AppColors.textDark : AppColors.textLight,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class _WheelList extends StatefulWidget {
  final int initialIndex;
  final int itemCount;
  final String Function(int) label;
  final ValueChanged<int> onChanged;

  const _WheelList({
    required this.initialIndex,
    required this.itemCount,
    required this.label,
    required this.onChanged,
  });

  @override
  State<_WheelList> createState() => _WheelListState();
}

class _WheelListState extends State<_WheelList> {
  late final FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(initialItem: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.textDark : AppColors.textLight;

    final selectedColor =
        isDark
            ? AppColors.surfaceSecondaryDark
            : AppColors.surfaceSecondaryLight;

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          height: 44,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selectedColor,
            borderRadius: BorderRadius.circular(AppTheme.pillRadius),
          ),
        ),
        ListWheelScrollView.useDelegate(
          controller: _controller,
          itemExtent: 44,
          diameterRatio: 1.2,
          perspective: 0.005,
          overAndUnderCenterOpacity: 0.45,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: (index) => widget.onChanged(index),
          childDelegate: ListWheelChildLoopingListDelegate(
            children: List.generate(
              widget.itemCount,
              (index) => Container(
                height: 44,
                alignment: Alignment.center,
                child: Text(
                  widget.label(index),
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
