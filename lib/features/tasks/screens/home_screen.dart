import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../../../core/input_utils.dart';
import '../../../core/bottom_sheet.dart';
import '../../../core/folder_icons.dart';
import '../../../core/responsive_center.dart';
import '../../../core/scroll_hide_mixin.dart';
import '../providers/task_provider.dart';
import '../widgets/folder_card.dart';
import '../../settings/screens/settings_screen.dart';
import '../../settings/providers/settings_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with ScrollHideMixin<HomeScreen> {
  int _navIndex = 0;
  late final PageController _pageController;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _navIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onNavTap(int index) {
    setState(() => _navIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _showFilterMenu(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = context.read<TaskProvider>();
    final menuColor = isDark ? AppColors.navDark : AppColors.navLight;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => Container(
            decoration: BoxDecoration(
              color: menuColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings.tr('filters'),
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Material(
                  color: Colors.transparent,
                  child: _filterTile(
                    ctx,
                    settings.tr('filter_all'),
                    TaskFilter.all,
                    provider,
                    onSurface,
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: _filterTile(
                    ctx,
                    settings.tr('filter_folders'),
                    TaskFilter.foldersOnly,
                    provider,
                    onSurface,
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _filterTile(
    BuildContext ctx,
    String label,
    TaskFilter filterOption,
    TaskProvider provider,
    Color onSurface,
  ) {
    final isSelected = provider.filter == filterOption;
    return ListTile(
      title: Text(
        label,
        style: TextStyle(color: onSurface, fontSize: 16),
      ),
      trailing:
          isSelected ? Icon(Icons.check, color: AppColors.primary) : null,
      onTap: () {
        provider.setFilter(filterOption);
        Navigator.pop(ctx);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ResponsiveCenter(
        child: PageView(
          controller: _pageController,
          onPageChanged: (index) => setState(() => _navIndex = index),
          physics: const BouncingScrollPhysics(),
          children: [
            _buildTasksBody(),
            const SettingsScreen(standalone: false),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navBg = isDark ? AppColors.navDark : AppColors.navLight;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Container(
        height: AppTheme.navHeight,
        color: navBg,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(
              top: AppTheme.navPadTop,
              bottom: AppTheme.navPadBottom,
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _onNavTap(0),
                    child: _navIconBox(
                      icon: Iconsax.task_square,
                      selected: _navIndex == 0,
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _onNavTap(1),
                    child: _navIconBox(
                      icon: Iconsax.profile_circle,
                      selected: _navIndex == 1,
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

  Widget _navIconBox({required IconData icon, required bool selected}) {
    final iconColor = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: AnimatedOpacity(
        opacity: selected ? 1.0 : 0.55,
        duration: const Duration(milliseconds: 150),
        child: Icon(icon, color: iconColor, size: 28),
      ),
    );
  }

  Widget _buildTasksBody() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fabColor = isDark ? AppColors.navDark : AppColors.navLight;

    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: handleScrollNotification,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSearchBar(),
                const Expanded(child: _HomeFolderList()),
              ],
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            right: AppTheme.screenPad,
            bottom: fabVisible ? AppTheme.screenPad : -AppTheme.fabSize - AppTheme.screenPad,
            child: GestureDetector(
              onTap: () => _showCreateFolderSheet(context),
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
                  child: Icon(Icons.add, color: Theme.of(context).colorScheme.onSurface, size: 28),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final provider = context.read<TaskProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.screenPad,
        AppTheme.screenPad,
        AppTheme.screenPad,
        36,
      ),
      child: Container(
        height: AppTheme.rowHeight,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.rowPadH,
          vertical: AppTheme.rowPadV,
        ),
        child: Row(
          children: [
            Icon(Iconsax.search_normal, color: textSecondary, size: 24),
            const SizedBox(width: AppTheme.rowGap),
            Expanded(
              child: TextField(
                controller: _searchController,
                inputFormatters: [textInputFormatter()],
                onChanged: (val) => provider.setSearchQuery(sanitizeText(val)),
                style: TextStyle(color: textSecondary, fontSize: 16),
                decoration: InputDecoration(
                  hintText: context.select<SettingsProvider, String>(
                    (s) => s.tr('search'),
                  ),
                  hintStyle: TextStyle(color: textSecondary, fontSize: 16),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (_searchController.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  provider.setSearchQuery('');
                  setState(() {});
                },
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.clear, color: textSecondary, size: 20),
                ),
              ),
            GestureDetector(
              onTap: () => _showFilterMenu(context),
              child: Icon(
                Iconsax.filter_square,
                color: textSecondary,
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateFolderSheet(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final controller = TextEditingController();
    String? selectedIcon;
    showInputSheet(
      context: context,
      icon: Iconsax.folder_minus,
      hintText: settings.tr('new_folder'),
      controller: controller,
      paste: InputPasteOptions(
        tooltip: settings.tr('paste'),
        errorText: settings.tr('paste_error'),
      ),
      folderIconAssets: folderIconAssets,
      onIconSelected: (asset) => selectedIcon = asset,
      noIconLabel: settings.tr('default_icon'),
      iconLabels: folderIconLabels(settings.tr),
      iconPickerTitle: settings.tr('folder_icon'),
      onSubmit: (val, sheetCtx) {
        final v = sanitizeText(val);
        if (v.isNotEmpty) {
          try {
            context.read<TaskProvider>().addFolder(v, iconAsset: selectedIcon);
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
}

class _HomeFolderList extends StatelessWidget {
  const _HomeFolderList();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TaskProvider>();
    final folders = provider.filteredFolders;
    final searchQuery = provider.searchQuery;

    if (folders.isEmpty) {
      final emptyText = context.select<SettingsProvider, String>(
        (s) =>
            searchQuery.isNotEmpty ? s.tr('nothing_found') : s.tr('empty_list'),
      );
      return Center(
        child: Text(
          emptyText,
          style: TextStyle(
            color:
                Theme.of(context).brightness == Brightness.dark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
            fontSize: 16,
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.screenPad,
        vertical: 4,
      ),
      itemCount: folders.length,
      onReorderItem: (oldIndex, newIndex) {
        if (oldIndex < newIndex) newIndex -= 1;
        context.read<TaskProvider>().reorderRootFolders(oldIndex, newIndex);
      },
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder:
              (context, child) => Transform.scale(scale: 1.03, child: child),
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final f = folders[index];
        return Padding(
          key: ValueKey(f.id),
          padding: const EdgeInsets.only(bottom: 8),
          child: FolderRow(folder: f),
        );
      },
    );
  }
}
