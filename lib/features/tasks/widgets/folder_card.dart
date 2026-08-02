import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/anchored_popup_menu.dart';
import '../../../core/snackbar_deduper.dart';
import '../../../core/theme.dart';
import '../../../core/input_utils.dart';
import '../../../core/bottom_sheet.dart';
import '../../../core/folder_icons.dart';
import '../models/task_model.dart';
import '../providers/task_provider.dart';
import '../screens/folder_detail_screen.dart';
import '../../settings/providers/settings_provider.dart';

/// Folder row — opens folder on tap, supports DragTarget (drop tasks/folders into folder) and LongPressDraggable
class FolderRow extends StatefulWidget {
  final FolderItem folder;
  final bool enableDrag;
  final int? reorderIndex;
  final bool showReorderHandle;
  final VoidCallback? onSwipeToParent;

  const FolderRow({
    super.key,
    required this.folder,
    this.enableDrag = true,
    this.reorderIndex,
    this.showReorderHandle = false,
    this.onSwipeToParent,
  });

  @override
  State<FolderRow> createState() => _FolderRowState();
}

class _FolderRowState extends State<FolderRow> {
  bool _isDragHovered = false;
  final GlobalKey _rowKey = GlobalKey();
  // Anchor of the "..." menu: the folder card itself, so the menu is
  // pinned to the right edge of the row with a 6 px gap.
  final GlobalKey _cardKey = GlobalKey();

  void _showEditSheet(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final controller = TextEditingController(text: widget.folder.name);
    String? selectedIcon = widget.folder.iconAsset;
    showInputSheet(
      context: context,
      icon: Iconsax.folder_minus,
      hintText: settings.tr('edit_folder'),
      controller: controller,
      paste: InputPasteOptions(
        tooltip: settings.tr('paste'),
        errorText: settings.tr('paste_error'),
      ),
      folderIconAssets: folderIconAssets,
      selectedIconAsset: selectedIcon,
      onIconSelected: (asset) => selectedIcon = asset,
      noIconLabel: settings.tr('default_icon'),
      iconLabels: folderIconLabels(settings.tr),
      iconPickerTitle: settings.tr('folder_icon'),
      onSubmit: (val, sheetCtx) {
        final v = sanitizeText(val);
        if (v.isNotEmpty) {
          try {
            context.read<TaskProvider>().updateFolder(
              widget.folder.id,
              v,
              iconAsset: selectedIcon,
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(e.toString().replaceAll('Exception: ', '')),
              ),
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
        iconContext.read<TaskProvider>().removeFolder(widget.folder.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.select<SettingsProvider, String>(
      (settings) => settings.languageCode,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    final rowChild = Material(
      key: _rowKey,
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FolderDetailScreen(folder: widget.folder),
            ),
          );
        },
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        onLongPress: null,
        child: AnimatedContainer(
          key: _cardKey,
          duration: const Duration(milliseconds: 200),
          height: AppTheme.rowHeight,
          decoration: BoxDecoration(
            color:
                _isDragHovered
                    ? AppColors.primary.withValues(alpha: 0.25)
                    : surface,
            borderRadius: BorderRadius.circular(AppTheme.pillRadius),
            border: Border.all(
              color: _isDragHovered ? AppColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
          padding: const EdgeInsets.only(left: AppTheme.rowPadH),
          child: Row(
            children: [
              _folderIcon(textSecondary),
              const SizedBox(width: AppTheme.rowGap),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: AppTheme.rowGap),
                  child: Text(
                    widget.folder.name,
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 16,
                      fontWeight:
                          widget.folder.isSystemStreak
                              ? FontWeight.w600
                              : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (widget.showReorderHandle && widget.reorderIndex != null)
                _reorderHandle(textSecondary),
              if (!widget.folder.isSystemStreak)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final anchor = _cardKey.currentContext;
                    if (anchor == null) return;
                    _showPopupMenu(anchor);
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: AppTheme.rowGap,
                      right: AppTheme.rowPadH,
                      top: AppTheme.rowPadV,
                      bottom: AppTheme.rowPadV,
                    ),
                    child: Semantics(
                      button: true,
                      label: context.read<SettingsProvider>().tr(
                        'more_options',
                      ),
                      child: KeyedSubtree(
                        key: const ValueKey('folder-row-menu-icon'),
                        child: Icon(
                          Iconsax.more_square,
                          color: textSecondary,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(width: AppTheme.rowPadH),
            ],
          ),
        ),
      ),
    );

    // Wrap as DragTarget to receive tasks or subfolders dropped into this folder
    Widget dragTargetChild = DragTarget<Object>(
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        if (data is FolderItem && data.id == widget.folder.id) {
          return false;
        }
        setState(() => _isDragHovered = true);
        return true;
      },
      onLeave: (_) => setState(() => _isDragHovered = false),
      onAcceptWithDetails: (details) {
        setState(() => _isDragHovered = false);
        final data = details.data;
        final provider = context.read<TaskProvider>();
        final settings = context.read<SettingsProvider>();
        // Report success only when the move actually applied. The streak
        // folder, folder cycles, and missing targets silently reject moves,
        // so show an honest denial instead of a fake success message.
        bool moved = false;
        String message = settings.tr('move_denied');
        if (data is TaskItem) {
          moved = provider.moveTaskToFolder(data.id, widget.folder.id);
          if (moved) {
            message = '${settings.tr('task_moved')} ${widget.folder.name}';
          }
        } else if (data is FolderItem) {
          moved = provider.moveFolderToFolder(data.id, widget.folder.id);
          if (moved) {
            message = '${settings.tr('folder_moved')} ${widget.folder.name}';
          }
        }
        SnackBarDeduper.show(
          context,
          message,
          baseDuration: const Duration(seconds: 2),
        );
      },
      builder: (context, candidateData, rejectedData) => rowChild,
    );

    Widget swipeChild = dragTargetChild;
    if (widget.onSwipeToParent != null) {
      swipeChild = Dismissible(
        key: ValueKey('swipe-folder-${widget.folder.id}'),
        direction: DismissDirection.endToStart,
        movementDuration: const Duration(milliseconds: 220),
        resizeDuration: const Duration(milliseconds: 180),
        background: const ColoredBox(color: Colors.transparent),
        secondaryBackground: _swipeBackground(textSecondary),
        onDismissed: (_) => widget.onSwipeToParent!(),
        child: swipeChild,
      );
    }

    if (!widget.enableDrag || widget.showReorderHandle) {
      return swipeChild;
    }

    return LongPressDraggable<FolderItem>(
      data: widget.folder,
      feedback: ExcludeSemantics(
        child: Material(
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
              padding: const EdgeInsets.only(left: AppTheme.rowPadH),
              child: Row(
                children: [
                  _dragIcon(textSecondary),
                  const SizedBox(width: AppTheme.rowGap),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: AppTheme.rowGap),
                      child: Text(
                        widget.folder.name,
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (!widget.folder.isSystemStreak)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: AppTheme.rowGap,
                        right: AppTheme.rowPadH,
                        top: AppTheme.rowPadV,
                        bottom: AppTheme.rowPadV,
                      ),
                      child: Semantics(
                        excludeSemantics: true,
                        child: Icon(
                          Iconsax.more_square,
                          color: textSecondary,
                          size: 24,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: AppTheme.rowPadH),
                ],
              ),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: swipeChild),
      child: swipeChild,
    );
  }

  Widget _swipeBackground(Color color) {
    final settings = context.read<SettingsProvider>();
    return Container(
      height: AppTheme.rowHeight,
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
              key: const ValueKey('folder-reorder-handle'),
              color: color,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget _dragIcon(Color textSecondary) =>
      _buildFolderIcon(color: textSecondary);

  Widget _folderIcon(Color textSecondary) => _buildFolderIcon(
    color: widget.folder.isSystemStreak ? AppColors.primary : textSecondary,
  );

  Widget _buildFolderIcon({required Color color}) {
    if (widget.folder.iconAsset != null &&
        widget.folder.iconAsset!.isNotEmpty) {
      return SvgPicture.asset(
        widget.folder.iconAsset!,
        width: 24,
        height: 24,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    }
    return Icon(
      widget.folder.isSystemStreak ? Iconsax.calendar_1 : Iconsax.folder_minus,
      color: color,
      size: 24,
    );
  }
}
