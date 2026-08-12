import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/calendar_service.dart';
import '../../../core/anchored_popup_menu.dart';
import '../../../core/snackbar_deduper.dart';
import '../../../core/responsive_center.dart';
import '../../../core/theme.dart';
import 'task_editor_sheet.dart';
import '../models/task_model.dart';
import '../providers/task_provider.dart';
import '../../settings/providers/settings_provider.dart';
import 'task_time_sheet.dart';
import 'task_detail_sheet.dart';

/// Single task row with smooth animated checkbox, entrance/exit animations, and LongPressDraggable support.
/// Editing actions are available from the ellipsis menu; the detail view is read-only.

class TaskRow extends StatefulWidget {
  final TaskItem task;
  final bool enableDrag;
  final int? reorderIndex;
  final bool showReorderHandle;
  final VoidCallback? onSwipeToParent;

  const TaskRow({
    super.key,
    required this.task,
    this.enableDrag = true,
    this.reorderIndex,
    this.showReorderHandle = false,
    this.onSwipeToParent,
  });

  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> with SingleTickerProviderStateMixin {
  late final AnimationController _exitController;
  bool _isExiting = false;
  bool? _previousCompleted;
  // Anchor of the "..." menu: the task card itself, so the menu is pinned
  // to the right edge of the row with a 6 px gap (AppTheme.popupMenuGap).
  final GlobalKey _cardKey = GlobalKey();

  /// The system streak folder is regenerated every day, so tasks inside it
  /// cannot be linked to calendar events.
  bool get _isInStreakFolder => widget.task.folderId == 'system_streak_folder';

  @override
  void initState() {
    super.initState();
    _previousCompleted = widget.task.isCompleted;
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _exitController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        context.read<TaskProvider>().toggleTask(widget.task.id);
      }
    });
  }

  @override
  void dispose() {
    _exitController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TaskRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.task.isCompleted != _previousCompleted) {
      // Completion is a state update, not a new row insertion. Keep the
      // entrance animation state stable so a toggle does not replay the
      // entrance transition or recreate the row subtree.
      _isExiting = false;
      _previousCompleted = widget.task.isCompleted;
    }
  }

  void _handleToggle() {
    if (_isExiting) return;
    setState(() => _isExiting = true);
    _exitController.forward(from: 0.0);
  }

  void _showEditSheet(BuildContext context) {
    showTaskEditorSheet(
      context,
      folderId: widget.task.folderId,
      task: widget.task,
    );
  }

  void _showPopupMenu(BuildContext iconContext) async {
    final settings = Provider.of<SettingsProvider>(iconContext, listen: false);
    final isDark = Theme.of(iconContext).brightness == Brightness.dark;
    final menuIconColor = Theme.of(iconContext).colorScheme.onSurface;
    final String? value = await showAnchoredPopupMenu<String>(
      context: iconContext,
      anchorContext: iconContext,
      gap: AppTheme.popupMenuGap,
      color: isDark ? AppColors.navDark : AppColors.navLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.menuRadius),
      ),
      items: [
        AnchoredPopupMenuItem<String>(
          value: 'edit',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Icon(Iconsax.edit_2, color: menuIconColor, size: 22),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  settings.tr('edit'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: menuIconColor, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
        AnchoredPopupMenuItem<String>(
          value: 'time',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Icon(Iconsax.timer_1, color: menuIconColor, size: 22),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  settings.tr('set_time'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: menuIconColor, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
        if (!_isInStreakFolder)
          AnchoredPopupMenuItem<String>(
            value: 'calendar',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Icon(Iconsax.calendar, color: menuIconColor, size: 22),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    widget.task.calendarEventId != null
                        ? settings.tr('remove_from_calendar')
                        : settings.tr('add_to_calendar'),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: menuIconColor, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        AnchoredPopupMenuItem<String>(
          value: 'delete',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Icon(Iconsax.trash, color: menuIconColor, size: 22),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  settings.tr('delete'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: menuIconColor, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (!iconContext.mounted) return;
    if (value == 'edit') {
      _showEditSheet(iconContext);
    } else if (value == 'time') {
      showTaskTimeSheet(iconContext, widget.task);
    } else if (value == 'calendar') {
      if (widget.task.calendarEventId != null) {
        await iconContext.read<TaskProvider>().unlinkTaskFromCalendar(
          widget.task.id,
        );
      } else {
        await _linkToCalendar(iconContext);
      }
    } else if (value == 'delete') {
      final isDark = Theme.of(iconContext).brightness == Brightness.dark;
      final bg = isDark ? AppColors.navDark : AppColors.navLight;
      final text =
          isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

      final confirmed = await showDialog<bool>(
        context: iconContext,
        builder:
            (ctx) => AlertDialog(
              backgroundColor: bg,
              title: Text(
                settings.tr('confirm_delete_title'),
                style: TextStyle(
                  color: isDark ? AppColors.textDark : AppColors.textLight,
                ),
              ),
              content: Text(
                settings.tr('confirm_delete_content'),
                style: TextStyle(color: text),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(
                    settings.tr('cancel'),
                    style: TextStyle(color: text),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(
                    settings.tr('delete'),
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
      );

      if (confirmed == true && iconContext.mounted) {
        iconContext.read<TaskProvider>().removeTask(widget.task.id);
      }
    }
  }

  Future<void> _linkToCalendar(BuildContext context) async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !context.mounted) return;

    final permissionGranted = await CalendarService.requestPermission();
    if (!permissionGranted) {
      if (!context.mounted) return;
      await _showCalendarPermissionDialog(context, settings);
      return;
    }

    final calendars =
        (await CalendarService.getCalendars(
          permissionAlreadyGranted: true,
        )).where((c) => c.id != null && c.id!.isNotEmpty).toList();
    if (calendars.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(settings.tr('calendar_no_calendars'))),
      );
      return;
    }

    Calendar? selected;
    if (calendars.length == 1) {
      selected = calendars.first;
    } else if (context.mounted) {
      selected = await showDialog<Calendar>(
        context: context,
        builder: (ctx) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: isDark ? AppColors.navDark : AppColors.navLight,
            title: Text(
              settings.tr('calendar_select'),
              style: TextStyle(
                color: isDark ? AppColors.textDark : AppColors.textLight,
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: calendars.length,
                itemBuilder: (context, index) {
                  final calendar = calendars[index];
                  return ListTile(
                    title: Text(
                      calendar.name ?? '',
                      style: TextStyle(
                        color:
                            isDark ? AppColors.textDark : AppColors.textLight,
                      ),
                    ),
                    onTap: () => Navigator.pop(context, calendar),
                  );
                },
              ),
            ),
          );
        },
      );
    }

    if (selected == null || !context.mounted) return;
    await context.read<TaskProvider>().linkTaskToCalendar(
      widget.task.id,
      selected.id!,
      date,
    );
  }

  Future<void> _showCalendarPermissionDialog(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? AppColors.navDark : AppColors.navLight;
    final textColor = isDark ? AppColors.textDark : AppColors.textLight;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            backgroundColor: background,
            title: Text(
              settings.tr('calendar_no_permission'),
              style: TextStyle(color: textColor),
            ),
            content: Text(
              settings.tr('calendar_permission_hint'),
              style: TextStyle(color: secondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(
                  settings.tr('cancel'),
                  style: TextStyle(color: secondary),
                ),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await CalendarService.openAppSettings();
                },
                child: Text(settings.tr('open_settings')),
              ),
            ],
          ),
    );
  }

  /// Allows the swipe-to-parent gesture only when the task can actually move
  /// up. When the move would land the task at the root (its folder has no
  /// parent), the swipe is cancelled and the user is told why.
  Future<bool> _confirmSwipeToParent(BuildContext context) async {
    final provider = context.read<TaskProvider>();
    if (provider.canMoveTaskToParent(widget.task.id)) return true;
    if (!context.mounted) return false;
    final settings = context.read<SettingsProvider>();
    SnackBarDeduper.show(
      context,
      settings.tr('task_move_to_root_denied'),
      baseDuration: const Duration(seconds: 2),
    );
    return false;
  }

  Widget _swipeBackground(Color color) {
    final settings = context.read<SettingsProvider>();
    return Container(
      constraints: const BoxConstraints(minHeight: AppTheme.rowHeight),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: AppTheme.rowPadH),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            settings.tr('move_to_parent'),
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Icon(Icons.reply, color: color, size: 22),
        ],
      ),
    );
  }

  Widget _reorderHandle(Color color) {
    final settings = context.read<SettingsProvider>();
    return ReorderableDragStartListener(
      index: widget.reorderIndex!,
      child: Semantics(
        button: true,
        label: settings.tr('reorder_item'),
        child: Tooltip(
          message: settings.tr('reorder_item'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              Icons.drag_handle,
              key: const ValueKey('task-reorder-handle'),
              color: color,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleIndicator(BuildContext context) {
    final hasCalendar =
        widget.task.calendarEventId != null && !_isInStreakFolder;
    final hasTime =
        widget.task.startTime != null || widget.task.endTime != null;
    if (!hasCalendar && !hasTime) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    if (hasCalendar) {
      return Padding(
        padding: const EdgeInsets.only(
          left: AppTheme.rowGap,
          top: 16,
          bottom: 16,
        ),
        child: Icon(
          Iconsax.calendar,
          key: const ValueKey('task_calendar_icon'),
          color: AppColors.primary,
          size: 20,
        ),
      );
    }

    final settings = Provider.of<SettingsProvider>(context, listen: false);
    return Semantics(
      button: true,
      label: settings.tr('set_time'),
      child: Tooltip(
        message: settings.tr('set_time'),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showTaskTimeSheet(context, widget.task),
          child: Padding(
            padding: const EdgeInsets.only(
              left: AppTheme.rowGap,
              top: AppTheme.rowPadV,
              bottom: AppTheme.rowPadV,
            ),
            child: Icon(
              Iconsax.timer_1,
              key: const ValueKey('task_timer_icon'),
              color: iconColor,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    context.select<SettingsProvider, String>(
      (settings) => settings.languageCode,
    );
    final settings = context.read<SettingsProvider>();

    final cardChild = Container(
      key: _cardKey,
      constraints: const BoxConstraints(minHeight: AppTheme.rowHeight),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
      ),
      padding: const EdgeInsets.only(left: AppTheme.rowPadH),
      child: Row(
        children: [
          Icon(Iconsax.clipboard_tick, color: textSecondary, size: 24),
          const SizedBox(width: AppTheme.rowGap),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showTaskDetailSheet(context, widget.task),
              child: Padding(
                padding: const EdgeInsets.only(right: AppTheme.rowGap),
                child: Text(
                  widget.task.title,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    decoration:
                        widget.task.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                    decorationColor: textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildScheduleIndicator(context),
              if (widget.showReorderHandle && widget.reorderIndex != null)
                _reorderHandle(textSecondary),
              if (!widget.task.isCompleted)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    // Anchor to the task card itself so the menu right edge
                    // aligns with the row, not the "..." icon.
                    final anchor = _cardKey.currentContext;
                    if (anchor == null) return;
                    _showPopupMenu(anchor);
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: AppTheme.rowGap,
                      right: 0,
                      top: AppTheme.rowPadV,
                      bottom: AppTheme.rowPadV,
                    ),
                    child: Semantics(
                      button: true,
                      label: settings.tr('more_options'),
                      child: KeyedSubtree(
                        key: const ValueKey('task-row-menu'),
                        child: Icon(
                          Iconsax.more_square,
                          color: textSecondary,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: AppTheme.rowGap),
              AnimatedTaskCheckbox(
                key: const ValueKey('task-row-checkbox'),
                isCompleted: widget.task.isCompleted,
                onTap: _handleToggle,
                textSecondary: textSecondary,
                padding: const EdgeInsets.only(
                  left: 0,
                  right: AppTheme.rowPadH,
                  top: AppTheme.rowPadV,
                  bottom: AppTheme.rowPadV,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    Widget animatedChild;
    if (_isExiting) {
      animatedChild = FadeTransition(
        opacity: Tween(begin: 1.0, end: 0.0).animate(_exitController),
        child: AnimatedBuilder(
          animation: _exitController,
          builder:
              (context, child) => Transform.scale(
                scale: 1.0 - 0.08 * _exitController.value,
                alignment: Alignment.centerRight,
                child: child,
              ),
          child: cardChild,
        ),
      );
    } else {
      animatedChild = TweenAnimationBuilder<double>(
        key: const ValueKey('task-row-entrance'),
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        builder:
            (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: child,
              ),
            ),
        child: cardChild,
      );
    }

    Widget swipeChild = animatedChild;
    if (widget.onSwipeToParent != null) {
      swipeChild = Dismissible(
        key: ValueKey('swipe-task-${widget.task.id}'),
        direction: DismissDirection.endToStart,
        movementDuration: const Duration(milliseconds: 220),
        resizeDuration: const Duration(milliseconds: 180),
        background: const ColoredBox(color: Colors.transparent),
        secondaryBackground: _swipeBackground(textSecondary),
        // Reject the swipe when the task cannot move up (for example, its
        // folder lives at the root level, so moving up would drop the task at
        // the root where it would disappear). Snap the row back and explain.
        confirmDismiss: (_) => _confirmSwipeToParent(context),
        onDismissed: (_) => widget.onSwipeToParent!(),
        child: swipeChild,
      );
    }

    if (!widget.enableDrag) return swipeChild;

    return LongPressDraggable<TaskItem>(
      data: widget.task,
      feedback: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: responsiveContentWidth(context),
            child: Container(
              constraints: const BoxConstraints(minHeight: AppTheme.rowHeight),
              decoration: BoxDecoration(
                color: isDark ? AppColors.navDark : AppColors.navLight,
                borderRadius: BorderRadius.circular(AppTheme.pillRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.only(left: AppTheme.rowPadH),
              child: Row(
                children: [
                  Icon(Iconsax.clipboard_tick, color: textSecondary, size: 24),
                  const SizedBox(width: AppTheme.rowGap),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: AppTheme.rowGap),
                      child: Text(
                        widget.task.title,
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          decoration:
                              widget.task.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                          decorationColor: textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (!widget.task.isCompleted)
                    Semantics(
                      excludeSemantics: true,
                      child: Padding(
                        key: const ValueKey('task-drag-feedback-menu'),
                        padding: const EdgeInsets.only(
                          left: AppTheme.rowGap,
                          right: 0,
                          top: AppTheme.rowPadV,
                          bottom: AppTheme.rowPadV,
                        ),
                        child: Icon(
                          Iconsax.more_square,
                          color: textSecondary,
                          size: 24,
                        ),
                      ),
                    ),
                  AnimatedTaskCheckbox(
                    key: const ValueKey('task-drag-feedback-checkbox'),
                    isCompleted: widget.task.isCompleted,
                    onTap: () {},
                    textSecondary: textSecondary,
                    padding: const EdgeInsets.only(
                      left: AppTheme.rowGap,
                      right: AppTheme.rowPadH,
                      top: AppTheme.rowPadV,
                      bottom: AppTheme.rowPadV,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: swipeChild),
      child: swipeChild,
    );
  }
}

/// Smooth animated checkbox widget with scale bounce & color transition
class AnimatedTaskCheckbox extends StatefulWidget {
  final bool isCompleted;
  final VoidCallback onTap;
  final Color textSecondary;
  final EdgeInsetsGeometry padding;

  const AnimatedTaskCheckbox({
    super.key,
    required this.isCompleted,
    required this.onTap,
    required this.textSecondary,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<AnimatedTaskCheckbox> createState() => _AnimatedTaskCheckboxState();
}

class _AnimatedTaskCheckboxState extends State<AnimatedTaskCheckbox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.25),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.25, end: 1.0),
        weight: 50,
      ),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _controller.forward(from: 0.0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);

    return Semantics(
      button: true,
      checked: widget.isCompleted,
      label:
          widget.isCompleted
              ? settings.tr('status_completed')
              : settings.tr('status_active'),
      child: GestureDetector(
        onTap: _handleTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: widget.padding,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color:
                    widget.isCompleted ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(
                  widget.isCompleted
                      ? AppTheme.checkRadiusDone
                      : AppTheme.checkRadius,
                ),
                border: Border.all(
                  color:
                      widget.isCompleted
                          ? AppColors.primary
                          : widget.textSecondary,
                  width: 2,
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder:
                    (child, anim) => ScaleTransition(scale: anim, child: child),
                child:
                    widget.isCompleted
                        ? const Icon(
                          Icons.check,
                          key: ValueKey('check'),
                          color: Colors.white,
                          size: 14,
                        )
                        : const SizedBox(key: ValueKey('empty')),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
