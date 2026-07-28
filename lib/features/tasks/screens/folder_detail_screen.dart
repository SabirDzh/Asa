import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../core/input_utils.dart';
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

class _FolderDetailScreenState extends State<FolderDetailScreen> {

  final ScrollController _breadcrumbScroll = ScrollController();

  @override
  void initState() {
    super.initState();
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

  List<FolderItem> _buildPath(TaskProvider provider) {
    List<FolderItem> path = [widget.folder];
    String? currentParentId = widget.folder.parentFolderId;
    while (currentParentId != null) {
      final matches = provider.folders.where((f) => f.id == currentParentId).toList();
      if (matches.isNotEmpty) {
        final parent = matches.first;
        path.insert(0, parent);
        currentParentId = parent.parentFolderId;
      } else {
        break;
      }
    }
    return path;
  }

  Widget _buildBreadcrumbs(BuildContext context, Color textColor, Color textSecondary) {
    final provider = Provider.of<TaskProvider>(context, listen: false);
    final path = _buildPath(provider);

    return SingleChildScrollView(
      controller: _breadcrumbScroll,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: path.asMap().entries.map((entry) {
          final idx = entry.key;
          final f = entry.value;
          final isLast = idx == path.length - 1;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (idx > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                  child: Icon(Icons.chevron_right, color: textSecondary, size: 20),
                ),
              GestureDetector(
                onTap: () {
                  if (!isLast) {
                    final pops = path.length - 1 - idx;
                    for (int i = 0; i < pops; i++) {
                      Navigator.pop(context);
                    }
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLast) ...[
                      Icon(
                        f.isSystemStreak ? Iconsax.calendar_1 : Iconsax.folder_minus,
                        color: AppColors.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      f.name,
                      style: TextStyle(
                        color: isLast ? textColor : textSecondary,
                        fontSize: isLast ? 20 : 16,
                        fontWeight: isLast ? FontWeight.bold : FontWeight.w400,
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

  void _showCreateSheet(BuildContext context, {required bool isTask}) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? AppColors.navDark : AppColors.navLight;
    final inputBg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final controller = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AnimatedPadding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        child: Container(
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.only(
            top: AppTheme.sheetPadTop,
            left: AppTheme.sheetPadH,
            right: AppTheme.sheetPadH,
            bottom: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.sheetHandleRadius),
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.sheetGap),
              Container(
                height: AppTheme.rowHeight,
                decoration: BoxDecoration(
                  color: inputBg,
                  borderRadius: BorderRadius.circular(AppTheme.pillRadius),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.rowPadH,
                  vertical: AppTheme.rowPadV,
                ),
                child: Row(
                  children: [
                    Icon(
                      isTask ? Iconsax.clipboard_tick : Iconsax.folder_minus,
                      color: textSecondary,
                      size: 24,
                    ),
                    const SizedBox(width: AppTheme.rowGap),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        inputFormatters: [textInputFormatter()],
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: isTask ? settings.tr('new_task') : settings.tr('new_folder'),
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 16,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: (val) {
                          final v = sanitizeText(val);
                          if (v.isNotEmpty) {
                            try {
                              if (isTask) {
                                context.read<TaskProvider>().addTask(v, folderId: widget.folder.id);
                              } else {
                                context.read<TaskProvider>().addFolder(v, parentFolderId: widget.folder.id);
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
                              );
                            }
                          }
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgDark : AppColors.bgLight;
    final textColor = isDark ? AppColors.textDark : AppColors.textLight;

    return Scaffold(
      backgroundColor: bg,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity != null &&
              (details.primaryVelocity! > 250 || details.primaryVelocity! < -250)) {
            Navigator.pop(context);
          }
        },
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Column(
                children: [
                  // Top bar with back button and folder title/breadcrumbs
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.arrow_back, color: textColor, size: 22),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildBreadcrumbs(context, textColor, isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                        ),
                      ],
                    ),
                  ),
                  // Subfolders and Task list in this folder
                  Expanded(
                    child: Consumer<TaskProvider>(
                      builder: (context, provider, _) {
                        final subfolders = provider.getSubfolders(widget.folder.id);
                        final folderTasks = provider.getFolderTasks(widget.folder.id);

                        final bool isEmpty = subfolders.isEmpty && folderTasks.isEmpty;

                        if (isEmpty) {
                          return Center(
                            child: Text(
                              settings.tr('no_tasks_in_folder'),
                              style: TextStyle(
                                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                fontSize: 16,
                              ),
                            ),
                          );
                        }

                        final inProgress = folderTasks.where((t) => !t.isCompleted).toList();
                        final completed = folderTasks.where((t) => t.isCompleted).toList();

                        return ReorderableListView(
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.symmetric(horizontal: AppTheme.screenPad, vertical: 12),
                          onReorderItem: (oldIndex, newIndex) {
                            final subfolderCount = subfolders.length;
                            if (oldIndex >= subfolderCount && newIndex >= subfolderCount) {
                              final oldTaskIndex = oldIndex - subfolderCount;
                              final newTaskIndex = newIndex - subfolderCount;
                              provider.reorderFolderTasks(widget.folder.id, oldTaskIndex, newTaskIndex);
                            }
                          },
                          proxyDecorator: (child, index, animation) {
                            return AnimatedBuilder(
                              animation: animation,
                              builder: (context, child) => Transform.scale(
                                scale: 1.03,
                                child: child,
                              ),
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
                            if (inProgress.isNotEmpty && completed.isNotEmpty)
                              Padding(
                                key: const ValueKey('divider_key'),
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Align(
                                  alignment: Alignment.center,
                                  child: SizedBox(
                                    width: 328,
                                    child: Divider(
                                      color: isDark ? Colors.white30 : AppColors.navLight,
                                      thickness: 2,
                                      height: 2,
                                    ),
                                  ),
                                ),
                              ),
                            for (final t in completed)
                              Padding(
                                key: ValueKey(t.id),
                                padding: const EdgeInsets.only(bottom: 8),
                                child: TaskRow(task: t),
                              ),
                            const SizedBox(key: ValueKey('bottom_space_key'), height: 80),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),

              // Floating menu & FAB inside folder detail
              Positioned.fill(
                child: _FolderFloatingMenu(
                  onMenuClose: () {},
                  showCreateSheet: _showCreateSheet,
                  bottomOffset: AppTheme.navHeight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderFloatingMenu extends StatefulWidget {
  final VoidCallback onMenuClose;
  final void Function(BuildContext, {required bool isTask}) showCreateSheet;
  final double bottomOffset;

  const _FolderFloatingMenu({
    required this.onMenuClose,
    required this.showCreateSheet,
    this.bottomOffset = 0.0,
  });

  @override
  State<_FolderFloatingMenu> createState() => _FolderFloatingMenuState();
}

class _FolderFloatingMenuState extends State<_FolderFloatingMenu> {
  bool _isOpen = false;

  void _toggleMenu() {
    setState(() => _isOpen = !_isOpen);
    if (!_isOpen) {
      widget.onMenuClose();
    }
  }

  Widget _menuOption(SettingsProvider settings, {required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.menuRadius),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.menuItemPad),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: AppTheme.menuItemGapInner),
            Text(
              label,
              textAlign: TextAlign.left,
              style: const TextStyle(
                color: Colors.white,
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
    final settings = Provider.of<SettingsProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuColor = isDark ? AppColors.navDark : AppColors.navLight;
    final fabColor = isDark ? AppColors.navDark : AppColors.navLight;

    return Stack(
      children: [
        // Tap area to close menu
        if (_isOpen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleMenu,
              child: Container(color: Colors.transparent),
            ),
          ),

        // Inline menu above FAB
        Positioned(
          right: AppTheme.screenPad,
          bottom: widget.bottomOffset + AppTheme.fabSize + AppTheme.screenPad + 12,
          child: IgnorePointer(
            ignoring: !_isOpen,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: _isOpen ? 0.0 : 1.0, end: _isOpen ? 1.0 : 0.0),
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
                    ),
                    child: IntrinsicWidth(
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
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ),
          ),
        ),

        // FAB button
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
                child:                 AnimatedRotation(
                  turns: _isOpen ? 0.125 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: const Icon(
                    Icons.add,
                    color: Colors.white,
                    size: 28,
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
