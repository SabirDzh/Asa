import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

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
  const FolderRow({super.key, required this.folder, this.enableDrag = true});

  @override
  State<FolderRow> createState() => _FolderRowState();
}

class _FolderRowState extends State<FolderRow> {
  bool _isDragHovered = false;
  final GlobalKey _rowKey = GlobalKey();

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
    // Anchor the menu to the bottom-right of the ... button so it always
    // appears below the icon and scales with the row.
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromLTWH(
        positionRect.right - 4,
        positionRect.bottom + 4,
        4,
        0,
      ),
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
          title: Text(settings.tr('confirm_delete_title'), style: TextStyle(color: isDark ? AppColors.textDark : AppColors.textLight)),
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
        iconContext.read<TaskProvider>().removeFolder(widget.folder.id);
      }
    }
  }

  void _showStreakPopup() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final renderBox = _rowKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = MediaQuery.of(context).size;
    final positionRect = offset & renderBox.size;
    final menuIconColor = Theme.of(context).colorScheme.onSurface;

    final String? value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          positionRect.right - 4,
          positionRect.bottom + 4,
          4,
          0,
        ),
        Offset.zero & size,
      ),
      color: isDark ? AppColors.navDark : AppColors.navLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.menuRadius)),
      items: [
        PopupMenuItem<String>(
          value: 'info',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Icon(Iconsax.information, color: menuIconColor, size: 22),
              const SizedBox(width: 10),
              Text(
                settings.tr('streak_info'),
                style: TextStyle(color: menuIconColor, fontSize: 16),
              ),
            ],
          ),
        ),
      ],
    );

    if (!mounted) return;
    if (value == 'info') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.folder.name)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

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
        onLongPress: widget.folder.isSystemStreak ? _showStreakPopup : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: AppTheme.rowHeight,
          decoration: BoxDecoration(
            color: _isDragHovered ? AppColors.primary.withValues(alpha: 0.25) : surface,
            borderRadius: BorderRadius.circular(AppTheme.pillRadius),
            border: Border.all(
              color: _isDragHovered ? AppColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
          padding: const EdgeInsets.only(
            left: AppTheme.rowPadH,
          ),
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
                    fontWeight: widget.folder.isSystemStreak ? FontWeight.w600 : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (!widget.folder.isSystemStreak)
              Builder(
                builder: (iconCtx) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showPopupMenu(iconCtx),
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: AppTheme.rowGap,
                      right: AppTheme.rowPadH,
                      top: AppTheme.rowPadV,
                      bottom: AppTheme.rowPadV,
                    ),
                    child: Icon(Iconsax.more_square, color: textSecondary, size: 24),
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
        if (data is TaskItem) {
          provider.moveTaskToFolder(data.id, widget.folder.id);
          final settings = context.read<SettingsProvider>();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${settings.tr('task_moved')} ${widget.folder.name}'),
              duration: const Duration(seconds: 2),
            ),
          );
        } else if (data is FolderItem) {
          provider.moveFolderToFolder(data.id, widget.folder.id);
          final settings = context.read<SettingsProvider>();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${settings.tr('folder_moved')} ${widget.folder.name}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      builder: (context, candidateData, rejectedData) => rowChild,
    );

    if (!widget.enableDrag || widget.folder.isSystemStreak) {
      return dragTargetChild;
    }

    return LongPressDraggable<FolderItem>(
      data: widget.folder,
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
                    child: Icon(Iconsax.more_square, color: textSecondary, size: 24),
                  )
                else
                  const SizedBox(width: AppTheme.rowPadH),
              ],
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: dragTargetChild,
      ),
      child: dragTargetChild,
    );
  }

  Widget _dragIcon(Color textSecondary) => _buildFolderIcon(color: textSecondary);

  Widget _folderIcon(Color textSecondary) =>
      _buildFolderIcon(color: widget.folder.isSystemStreak ? AppColors.primary : textSecondary);

  Widget _buildFolderIcon({required Color color}) {
    if (widget.folder.iconAsset != null && widget.folder.iconAsset!.isNotEmpty) {
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
