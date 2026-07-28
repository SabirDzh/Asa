import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../models/task_model.dart';
import '../providers/task_provider.dart';
import '../../settings/providers/settings_provider.dart';

/// Single task row with smooth animated checkbox and LongPressDraggable support
class TaskRow extends StatelessWidget {
  final TaskItem task;
  final bool enableDrag;
  const TaskRow({super.key, required this.task, this.enableDrag = true});

  void _showEditDialog(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final controller = TextEditingController(text: task.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(settings.tr('edit_task')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            border: UnderlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(settings.tr('cancel'), style: TextStyle(color: AppColors.textSecondaryLight)),
          ),
          TextButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) {
                try {
                  context.read<TaskProvider>().updateTask(task.id, v);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
                  );
                }
              }
              Navigator.pop(ctx);
            },
            child: Text(settings.tr('save'), style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _showPopupMenu(BuildContext iconContext) async {
    final settings = Provider.of<SettingsProvider>(iconContext, listen: false);
    final isDark = Theme.of(iconContext).brightness == Brightness.dark;
    
    final RenderBox renderBox = iconContext.findRenderObject() as RenderBox;
    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final Rect positionRect = offset & renderBox.size;
    final RelativeRect position = RelativeRect.fromLTRB(
      positionRect.left,
      positionRect.bottom + 8, // Directly below the icon
      positionRect.right,
      positionRect.bottom + 8,
    );

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
              const Icon(Iconsax.edit_2, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Text(
                settings.tr('edit'),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const Icon(Iconsax.trash, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Text(
                settings.tr('delete'),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      ],
    );

    if (!iconContext.mounted) return;
    if (value == 'edit') {
      _showEditDialog(iconContext);
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
        iconContext.read<TaskProvider>().removeTask(task.id);
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
              task.title,
              style: TextStyle(
                color: textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w400,
                decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                decorationColor: textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!task.isCompleted)
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
            isCompleted: task.isCompleted,
            onTap: () => context.read<TaskProvider>().toggleTask(task.id),
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

    if (!enableDrag) return cardChild;

    return LongPressDraggable<TaskItem>(
      data: task,
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
                    task.title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                      decorationColor: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!task.isCompleted)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: AppTheme.rowGap,
                      top: 16,
                      bottom: 16,
                    ),
                    child: Icon(Iconsax.more_square, color: Colors.white, size: 24),
                  ),
                AnimatedTaskCheckbox(
                  isCompleted: task.isCompleted,
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
        child: cardChild,
      ),
      child: cardChild,
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
