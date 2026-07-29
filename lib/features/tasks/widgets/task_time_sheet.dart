import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../core/input_utils.dart';
import '../models/task_model.dart';
import '../providers/task_provider.dart';
import '../../settings/providers/settings_provider.dart';

/// Shows a bottom sheet to set either a duration or a time period for [task].
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
  int? _durationMinutes;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  @override
  void initState() {
    super.initState();
    _durationMinutes = widget.task.expectedDuration;
    if (widget.task.startTime != null) {
      final dt = widget.task.startTime!;
      _startTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
    }
    if (widget.task.endTime != null) {
      final dt = widget.task.endTime!;
      _endTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
    }
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? TimeOfDay.now(),
    );
    if (picked == null) return;
    setState(() => _startTime = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime ?? TimeOfDay.now(),
    );
    if (picked == null) return;
    setState(() => _endTime = picked);
  }

  void _setDuration(int minutes) {
    setState(() => _durationMinutes = minutes);
  }

  Future<void> _showDurationPicker() async {
    final controller = TextEditingController(
      text: _durationMinutes != null ? _formatDuration(_durationMinutes!) : '',
    );
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? AppColors.navDark : AppColors.navLight,
          title: Text(
            settings.tr('duration'),
            style: TextStyle(color: isDark ? AppColors.textDark : AppColors.textLight),
          ),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.text,
            inputFormatters: [textInputFormatter()],
            style: TextStyle(color: isDark ? AppColors.textDark : AppColors.textLight),
            decoration: InputDecoration(
              hintText: '1:30',
              hintStyle: TextStyle(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.pillRadius)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(settings.tr('cancel'), style: TextStyle(color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(settings.tr('save'), style: const TextStyle(color: AppColors.primary)),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    if (confirmed != true) return;

    final text = controller.text.trim();
    if (text.isEmpty) {
      setState(() => _durationMinutes = null);
      return;
    }
    final parsed = _parseDuration(text);
    if (parsed != null) {
      _setDuration(parsed);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            settings.tr('duration_error'),
            style: const TextStyle(color: AppColors.textDark),
          ),
        ),
      );
    }
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

  String _formatDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '$h:${m.toString().padLeft(2, '0')}';
  }

  int? _parseDuration(String text) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return null;
    // Support "1:30" -> 90 min, "90" -> 90 min, "1h30" -> 90 min
    final colon = cleaned.split(':');
    if (colon.length == 2) {
      final h = int.tryParse(colon[0].trim()) ?? 0;
      final m = int.tryParse(colon[1].trim()) ?? 0;
      return h * 60 + m;
    }
    final digits = int.tryParse(cleaned);
    if (digits != null) return digits;
    final hMatch = RegExp(r'(\d+)\s*h\s*(\d+)?', caseSensitive: false).firstMatch(cleaned);
    if (hMatch != null) {
      final h = int.tryParse(hMatch.group(1)!) ?? 0;
      final m = int.tryParse(hMatch.group(2) ?? '0') ?? 0;
      return h * 60 + m;
    }
    return null;
  }

  void _save(BuildContext context) {
    final start = _toDateTime(_startTime);
    final end = _toDateTime(_endTime);
    if (start != null && end != null && (end.isBefore(start) || end.isAtSameMomentAs(start))) {
      if (!mounted) return;
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(settings.tr('invalid_period'))),
      );
      return;
    }
    final provider = context.read<TaskProvider>();
    provider.setTaskTime(
      widget.task.id,
      startTime: start,
      endTime: end,
      expectedDuration: _durationMinutes,
    );
    Navigator.pop(context);
  }

  void _clear(BuildContext context) {
    context.read<TaskProvider>().setTaskTime(
      widget.task.id,
      startTime: null,
      endTime: null,
      expectedDuration: null,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? AppColors.sheetDark : AppColors.sheetLight;
    final textColor = isDark ? AppColors.textDark : AppColors.textLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Container(
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 48, height: 4, decoration: BoxDecoration(color: textSecondary, borderRadius: BorderRadius.circular(AppTheme.sheetHandleRadius))),
              const SizedBox(height: 20),
              Text(
                settings.tr('set_time'),
                style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              _sectionTitle(Iconsax.timer_1, settings.tr('duration')),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _showDurationPicker,
                child: Container(
                  height: AppTheme.rowHeight,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceSecondaryDark : AppColors.surfaceSecondaryLight,
                    borderRadius: BorderRadius.circular(AppTheme.pillRadius),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _durationMinutes != null ? _formatDuration(_durationMinutes!) : settings.tr('no_duration'),
                    style: TextStyle(color: _durationMinutes != null ? textColor : textSecondary, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _sectionTitle(Iconsax.clock, settings.tr('time_period')),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _timeButton(
                      label: _startTime != null ? _formatTime(_startTime!) : settings.tr('start_time'),
                      onTap: _pickStartTime,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _timeButton(
                      label: _endTime != null ? _formatTime(_endTime!) : settings.tr('end_time'),
                      onTap: _pickEndTime,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => _clear(context),
                      child: Text(settings.tr('clear'), style: TextStyle(color: textSecondary)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _save(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.pillRadius)),
                      ),
                      child: Text(settings.tr('save'), style: const TextStyle(color: AppColors.textDark)),
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
        Text(label, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w500)),
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
          color: isDark ? AppColors.surfaceSecondaryDark : AppColors.surfaceSecondaryLight,
          borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(color: isDark ? AppColors.textDark : AppColors.textLight, fontSize: 16)),
      ),
    );
  }
}
