import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../core/input_utils.dart';
import '../../../core/bottom_sheet.dart';
import '../models/task_model.dart';
import '../providers/task_provider.dart';
import '../../settings/providers/settings_provider.dart';

/// Single task row with smooth animated checkbox, entrance/exit animations, and LongPressDraggable support
class TaskRow extends StatefulWidget {
  final TaskItem task;
  final bool enableDrag;
  const TaskRow({super.key, required this.task, this.enableDrag = true});

  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> with SingleTickerProviderStateMixin {
  late final AnimationController _exitController;
  int _entranceKey = 0;
  bool _isExiting = false;
  bool? _previousCompleted;

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
      _entranceKey++;
      _isExiting = false;
      _exitController.value = 0.0;
      _previousCompleted = widget.task.isCompleted;
    }
  }

  void _handleToggle() {
    if (_isExiting) return;
    setState(() => _isExiting = true);
    _exitController.forward(from: 0.0);
  }

  void _showEditSheet(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final controller = TextEditingController(text: widget.task.title);
    showInputSheet(
      context: context,
      icon: Iconsax.clipboard_tick,
      hintText: settings.tr('edit_task'),
      controller: controller,
      paste: InputPasteOptions(
        tooltip: settings.tr('paste'),
        errorText: settings.tr('paste_error'),
      ),
      onSubmit: (val, sheetCtx) {
        final v = sanitizeText(val);
        if (v.isNotEmpty) {
          try {
            context.read<TaskProvider>().updateTask(widget.task.id, v);
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
            );
          }
        }
        Navigator.pop(sheetCtx);
      },
    );
  }

  void _showPopupMenu(BuildContext iconContext) async {
    final settings = Provider.of<SettingsProvider>(iconContext, listen: false);
    final isDark = Theme.of(iconContext).brightness == Brightness.dark;
    
    final RenderBox? renderBox = iconContext.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final size = MediaQuery.of(iconContext).size;
    final Rect positionRect = offset & renderBox.size;
    final RelativeRect position = RelativeRect.fromRect(
      positionRect.shift(const Offset(0, 8)),
      Offset.zero & size,
    );

    final menuIconColor = Theme.of(iconContext).colorScheme.onSurface;
    final String? value = await showMenu<String>(
      context: iconContext,
      position: position,
      color: isDark ? AppColors.navDark : AppColors.navLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.menuRadius)),
      items: [
        PopupMenuItem<String>(
          value: 'edit',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Icon(Iconsax.edit_2, color: menuIconColor, size: 22),
              const SizedBox(width: 10),
              Text(
                settings.tr('edit'),
                style: TextStyle(color: menuIconColor, fontSize: 16),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Icon(Iconsax.trash, color: menuIconColor, size: 22),
              const SizedBox(width: 10),
              Text(
                settings.tr('delete'),
                style: TextStyle(color: menuIconColor, fontSize: 16),
              ),
            ],
          ),
        ),
      ],
    );

    if (!iconContext.mounted) return;
    if (value == 'edit') {
      _showEditSheet(iconContext);
    } else if (value == 'delete') {
      final isDark = Theme.of(iconContext).brightness == Brightness.dark;
      final bg = isDark ? AppColors.navDark : AppColors.navLight;
      final text = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
      
      final confirmed = await showDialog<bool>(
        context: iconContext,
        builder: (ctx) => AlertDialog(
          backgroundColor: bg,
          title: Text(settings.tr('confirm_delete_title'), style: const TextStyle(color: Colors.white)),
          content: Text(
            settings.tr('confirm_delete_content'),
            style: TextStyle(color: text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(settings.tr('cancel'), style: TextStyle(color: text)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(settings.tr('delete'), style: const TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (confirmed == true && iconContext.mounted) {
        iconContext.read<TaskProvider>().removeTask(widget.task.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    final cardChild = Container(
      height: AppTheme.rowHeight,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
      ),
      padding: const EdgeInsets.only(
        left: AppTheme.rowPadH,
      ),
      child: Row(
        children: [
          Icon(
            Iconsax.clipboard_tick,
            color: textSecondary,
            size: 24,
          ),
          const SizedBox(width: AppTheme.rowGap),
          Expanded(
            child: Text(
              widget.task.title,
              style: TextStyle(
                color: textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w400,
                decoration: widget.task.isCompleted ? TextDecoration.lineThrough : null,
                decorationColor: textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!widget.task.isCompleted)
            Builder(
              builder: (iconCtx) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showPopupMenu(iconCtx),
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: AppTheme.rowGap,
                    top: 16,
                    bottom: 16,
                  ),
                  child: Icon(Iconsax.more_square, color: textSecondary, size: 24),
                ),
              ),
            ),
          AnimatedTaskCheckbox(
            isCompleted: widget.task.isCompleted,
            onTap: _handleToggle,
            textSecondary: textSecondary,
            padding: const EdgeInsets.only(
              left: AppTheme.rowGap,
              right: AppTheme.rowPadH,
              top: 16,
              bottom: 16,
            ),
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
          builder: (context, child) => Transform.scale(
            scale: 1.0 - 0.08 * _exitController.value,
            alignment: Alignment.centerRight,
            child: child,
          ),
          child: cardChild,
        ),
      );
    } else {
      animatedChild = TweenAnimationBuilder<double>(
        key: ValueKey('entrance_$_entranceKey'),
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        ),
        child: cardChild,
      );
    }

    if (!widget.enableDrag) return animatedChild;

    return LongPressDraggable<TaskItem>(
      data: widget.task,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: MediaQuery.of(context).size.width - 32,
          child: Container(
            height: AppTheme.rowHeight,
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
            padding: const EdgeInsets.only(
              left: AppTheme.rowPadH,
            ),
            child: Row(
              children: [
                const Icon(Iconsax.clipboard_tick, color: Colors.white, size: 24),
                const SizedBox(width: AppTheme.rowGap),
                Expanded(
                  child: Text(
                    widget.task.title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      decoration: widget.task.isCompleted ? TextDecoration.lineThrough : null,
                      decorationColor: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!widget.task.isCompleted)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: AppTheme.rowGap,
                      top: 16,
                      bottom: 16,
                    ),
                    child: Icon(Iconsax.more_square, color: Colors.white, size: 24),
                  ),
                AnimatedTaskCheckbox(
                  isCompleted: widget.task.isCompleted,
                  onTap: () {},
                  textSecondary: Colors.white,
                  padding: const EdgeInsets.only(
                    left: AppTheme.rowGap,
                    right: AppTheme.rowPadH,
                    top: 16,
                    bottom: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: animatedChild,
      ),
      child: animatedChild,
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
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.25), weight: 50),
      TweenSequenceItem(tween: Tween<double>(begin: 1.25, end: 1.0), weight: 50),
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
    return GestureDetector(
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
              color: widget.isCompleted ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(
                widget.isCompleted ? AppTheme.checkRadiusDone : AppTheme.checkRadius,
              ),
              border: Border.all(
                color: widget.isCompleted ? AppColors.primary : widget.textSecondary,
                width: 2,
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
              child: widget.isCompleted
                  ? const Icon(Icons.check, key: ValueKey('check'), color: Colors.white, size: 14)
                  : const SizedBox(key: ValueKey('empty')),
            ),
          ),
        ),
      ),
    );
  }
}
