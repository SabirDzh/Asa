import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../core/input_utils.dart';
import '../../../core/bottom_sheet.dart';
import '../../../core/folder_icons.dart';
import '../../../core/home_widget_service.dart';
import '../../../core/responsive_center.dart';
import '../../../core/scroll_hide_mixin.dart';
import '../models/task_model.dart';
import '../providers/task_provider.dart';
import '../widgets/task_card.dart';
import '../widgets/folder_card.dart';
import '../../settings/providers/settings_provider.dart';

class FolderDetailScreen extends StatefulWidget {
  final FolderItem folder;
  const FolderDetailScreen({super.key, required this.folder});

  @override
  State<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<FolderDetailScreen> with ScrollHideMixin<FolderDetailScreen> {
  final ScrollController _breadcrumbScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final provider = context.read<TaskProvider>();
    provider.setLastViewedFolderName(widget.folder.name);
    HomeWidgetService.updateData(provider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_breadcrumbScroll.hasClients) {
        _breadcrumbScroll.jumpTo(_breadcrumbScroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _breadcrumbScroll.dispose();
    super.dispose();
  }

  void _showCreateSheet(BuildContext context, {required bool isTask}) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final controller = TextEditingController();
    String? selectedIcon;
    showInputSheet(
      context: context,
      icon: isTask ? Iconsax.clipboard_tick : Iconsax.folder_minus,
      hintText: isTask ? settings.tr('new_task') : settings.tr('new_folder'),
      controller: controller,
      paste: InputPasteOptions(
        tooltip: settings.tr('paste'),
        errorText: settings.tr('paste_error'),
      ),
      folderIconAssets: isTask ? null : folderIconAssets,
      onIconSelected: (asset) => selectedIcon = asset,
      noIconLabel: settings.tr('default_icon'),
      iconLabels: isTask ? null : folderIconLabels(settings.tr),
      iconPickerTitle: settings.tr('folder_icon'),
      onSubmit: (val, sheetCtx) {
        final v = sanitizeText(val);
        if (v.isNotEmpty) {
          try {
            if (isTask) {
              context.read<TaskProvider>().addTask(
                v,
                folderId: widget.folder.id,
              );
            } else {
              context.read<TaskProvider>().addFolder(
                v,
                parentFolderId: widget.folder.id,
                iconAsset: selectedIcon,
              );
            }
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgDark : AppColors.bgLight;
    final textColor = isDark ? AppColors.textDark : AppColors.textLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Scaffold(
      backgroundColor: bg,
      body: ResponsiveCenter(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity != null &&
                (details.primaryVelocity! > 250 ||
                    details.primaryVelocity! < -250)) {
              Navigator.pop(context);
            }
          },
          child: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.screenPad,
                        AppTheme.screenPad,
                        AppTheme.screenPad,
                        AppTheme.screenPad * 2,
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color:
                                    isDark
                                        ? AppColors.surfaceDark
                                        : AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.arrow_back,
                                color: textColor,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _Breadcrumbs(
                              folder: widget.folder,
                              textColor: textColor,
                              textSecondary: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: handleScrollNotification,
                    child: _FolderContent(folder: widget.folder),
                  ),
                ),
              ],
            ),
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: fabVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: IgnorePointer(
                  ignoring: !fabVisible,
                  child: _FolderFloatingMenu(
                    onMenuClose: () {},
                    showCreateSheet: _showCreateSheet,
                    bottomOffset: AppTheme.navHeight,
                    isVisible: fabVisible,
                  ),
                ),
              ),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  final FolderItem folder;
  final Color textColor;
  final Color textSecondary;

  const _Breadcrumbs({
    required this.folder,
    required this.textColor,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TaskProvider>();
    final allFolders = provider.folders;
    List<FolderItem> path = [folder];
    String? currentParentId = folder.parentFolderId;
    while (currentParentId != null) {
      final matches = allFolders.where((f) => f.id == currentParentId).toList();
      if (matches.isNotEmpty) {
        final parent = matches.first;
        path.insert(0, parent);
        currentParentId = parent.parentFolderId;
      } else {
        break;
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children:
            path.asMap().entries.map((entry) {
              final idx = entry.key;
              final f = entry.value;
              final isLast = idx == path.length - 1;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (idx > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: Icon(
                        Icons.chevron_right,
                        color: textSecondary,
                        size: 20,
                      ),
                    ),                    GestureDetector(
                    onTap: () {
                      if (!isLast) {
                        final pops = path.length - 1 - idx;
                        for (int i = 0; i < pops; i++) {
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          }
                        }
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isLast) ...[
                          _folderIcon(f, AppColors.primary),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          f.name,
                          style: TextStyle(
                            color: isLast ? textColor : textSecondary,
                            fontSize: isLast ? 20 : 16,
                            fontWeight:
                                isLast ? FontWeight.bold : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
      ),
    );
  }

  Widget _folderIcon(FolderItem folder, Color color) {
    if (folder.iconAsset != null && folder.iconAsset!.isNotEmpty) {
      return SvgPicture.asset(
        folder.iconAsset!,
        width: 24,
        height: 24,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    }
    return Icon(
      folder.isSystemStreak ? Iconsax.calendar_1 : Iconsax.folder_minus,
      color: color,
      size: 24,
    );
  }
}

class _FolderContent extends StatelessWidget {
  final FolderItem folder;
  const _FolderContent({required this.folder});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final provider = context.watch<TaskProvider>();
    final subfolders = provider.getSubfolders(folder.id);
    final folderTasks = provider.getFolderTasks(folder.id);

    final isEmpty = subfolders.isEmpty && folderTasks.isEmpty;

    if (isEmpty) {
      return Center(
        child: Text(
          settings.tr('no_tasks_in_folder'),
          style: TextStyle(
            color:
                isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
            fontSize: 16,
          ),
        ),
      );
    }

    final inProgress = folderTasks.where((t) => !t.isCompleted).toList();
    final completed = folderTasks.where((t) => t.isCompleted).toList();

    // Build task widgets. The first completed task carries the divider
    // above it so the divider is not an independent reorderable child.
    final completedWidgets = <Widget>[];
    for (var i = 0; i < completed.length; i++) {
      final t = completed[i];
      Widget taskWidget = Padding(
        key: ValueKey(t.id),
        padding: const EdgeInsets.only(bottom: 8),
        child: TaskRow(task: t),
      );
      if (inProgress.isNotEmpty && i == 0) {
        taskWidget = Column(
          key: ValueKey('completed_${t.id}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Align(
                alignment: Alignment.center,
                child:                SizedBox(
                  width: AppTheme.rowWidth,
                  child: Divider(
                    color: isDark ? Colors.white30 : AppColors.navLight,
                    thickness: 2,
                    height: 2,
                  ),
                ),
              ),
            ),
            taskWidget,
          ],
        );
      }
      completedWidgets.add(taskWidget);
    }

    return ReorderableListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.screenPad,
        12,
        AppTheme.screenPad,
        80,
      ),
      onReorderItem: (oldIndex, newIndex) {
        if (oldIndex < newIndex) newIndex -= 1;
        final sc = subfolders.length;
        final taskCount = inProgress.length + completed.length;
        final taskStart = sc;
        final taskEnd = sc + taskCount;
        if (oldIndex < sc && newIndex < sc) {
          context.read<TaskProvider>().reorderSubfolders(
            folder.id,
            oldIndex,
            newIndex,
          );
        } else if (oldIndex >= taskStart &&
            oldIndex < taskEnd &&
            newIndex >= taskStart &&
            newIndex < taskEnd) {
          context.read<TaskProvider>().reorderFolderTasks(
            folder.id,
            oldIndex - taskStart,
            newIndex - taskStart,
          );
        }
      },
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder:
              (context, child) => Transform.scale(scale: 1.03, child: child),
          child: child,
        );
      },
      children: [
        for (final sf in subfolders)
          Padding(
            key: ValueKey(sf.id),
            padding: const EdgeInsets.only(bottom: 8),
            child: FolderRow(folder: sf),
          ),
        for (final t in inProgress)
          Padding(
            key: ValueKey(t.id),
            padding: const EdgeInsets.only(bottom: 8),
            child: TaskRow(task: t),
          ),
        ...completedWidgets,
      ],
    );
  }
}

class _FolderFloatingMenu extends StatefulWidget {
  final VoidCallback onMenuClose;
  final void Function(BuildContext, {required bool isTask}) showCreateSheet;
  final double bottomOffset;
  final bool isVisible;

  const _FolderFloatingMenu({
    required this.onMenuClose,
    required this.showCreateSheet,
    this.bottomOffset = 0.0,
    this.isVisible = true,
  });

  @override
  State<_FolderFloatingMenu> createState() => _FolderFloatingMenuState();
}

class _FolderFloatingMenuState extends State<_FolderFloatingMenu> {
  bool _isOpen = false;

  @override
  void didUpdateWidget(covariant _FolderFloatingMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isVisible && _isOpen) {
      setState(() {
        _isOpen = false;
      });
      widget.onMenuClose();
    }
  }

  void _toggleMenu() {
    setState(() => _isOpen = !_isOpen);
    if (!_isOpen) widget.onMenuClose();
  }

  Widget _menuOption(
    SettingsProvider settings, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color onSurface,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.menuRadius),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.menuItemPad),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            Icon(icon, color: onSurface, size: 24),
            const SizedBox(width: AppTheme.menuItemGapInner),
            Text(
              label,
              textAlign: TextAlign.left,
              style: TextStyle(
                color: onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuColor = isDark ? AppColors.navDark : AppColors.navLight;
    final fabColor = isDark ? AppColors.navDark : AppColors.navLight;

    return Stack(
      children: [
        if (_isOpen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleMenu,
              child: Container(color: Colors.transparent),
            ),
          ),
        Positioned(
          right: AppTheme.screenPad,
          bottom:
              widget.bottomOffset + AppTheme.fabSize + AppTheme.screenPad + 12,
          child: IgnorePointer(
            ignoring: !_isOpen,
            child: TweenAnimationBuilder<double>(
              tween: Tween(
                begin: _isOpen ? 0.0 : 1.0,
                end: _isOpen ? 1.0 : 0.0,
              ),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.scale(
                    scale: value,
                    alignment: Alignment.bottomRight,
                    child: child,
                  ),
                );
              },
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: menuColor,
                    borderRadius: BorderRadius.circular(AppTheme.menuRadius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),                    child: IntrinsicWidth(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _menuOption(
                          settings,
                          icon: Iconsax.folder_minus,
                          label: settings.tr('create_folder'),
                          onTap: () {
                            _toggleMenu();
                            widget.showCreateSheet(context, isTask: false);
                          },
                          onSurface: Theme.of(context).colorScheme.onSurface,
                        ),
                        SizedBox(height: AppTheme.menuItemGap),
                        _menuOption(
                          settings,
                          icon: Iconsax.clipboard_tick,
                          label: settings.tr('create_task'),
                          onTap: () {
                            _toggleMenu();
                            widget.showCreateSheet(context, isTask: true);
                          },
                          onSurface: Theme.of(context).colorScheme.onSurface,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: AppTheme.screenPad,
          bottom: widget.bottomOffset + AppTheme.screenPad,
          child: GestureDetector(
            onTap: _toggleMenu,
            child: Container(
              width: AppTheme.fabSize,
              height: AppTheme.fabSize,
              decoration: BoxDecoration(
                color: fabColor,
                borderRadius: BorderRadius.circular(AppTheme.fabRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: AnimatedRotation(
                  turns: _isOpen ? 0.125 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: Icon(Icons.add, color: Theme.of(context).colorScheme.onSurface, size: 28),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
