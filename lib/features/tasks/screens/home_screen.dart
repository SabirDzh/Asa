import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
import '../providers/task_provider.dart';
import '../widgets/folder_card.dart';
import '../../settings/screens/settings_screen.dart';
import '../../settings/providers/settings_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 0; // 0=tasks/folders, 1=profile/settings
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

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: menuColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              settings.tr('filters'),
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _filterTile(ctx, settings.tr('filter_all'), TaskFilter.all, provider),
            _filterTile(ctx, settings.tr('filter_folders'), TaskFilter.foldersOnly, provider),
          ],
        ),
      ),
    );
  }

  Widget _filterTile(BuildContext ctx, String label, TaskFilter filterOption, TaskProvider provider) {
    final isSelected = provider.filter == filterOption;
    return ListTile(
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16)),
      trailing: isSelected ? const Icon(Icons.check, color: AppColors.primary) : null,
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
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() => _navIndex = index);
        },
        physics: const BouncingScrollPhysics(),
        children: [
          _buildTasksBody(),
          const SettingsScreen(standalone: false),
        ],
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
    return Center(
      child: AnimatedOpacity(
        opacity: selected ? 1.0 : 0.55,
        duration: const Duration(milliseconds: 150),
        child: Icon(icon, color: Colors.white, size: 28),
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
          // ── Main content ──────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSearchBar(),
              Expanded(child: _buildList()),
            ],
          ),

          // ── FAB button (directly opens create folder sheet) ──
          Positioned(
            right: AppTheme.screenPad,
            bottom: AppTheme.screenPad,
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
                child: const Center(
                  child: Icon(Icons.add, color: Colors.white, size: 28),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final settings = Provider.of<SettingsProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final textSecondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final provider = Provider.of<TaskProvider>(context, listen: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.screenPad,
        AppTheme.screenPad,
        AppTheme.screenPad,
        36, // 36 + 4 (from list padding) = 40 gap
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
                onChanged: (val) => provider.setSearchQuery(val),
                style: TextStyle(color: textSecondary, fontSize: 16),
                decoration: InputDecoration(
                  hintText: settings.tr('search'),
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
              child: Icon(Iconsax.filter_square, color: textSecondary, size: 24),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return Consumer2<TaskProvider, SettingsProvider>(
      builder: (context, provider, settings, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final folders = provider.filteredFolders;

        if (folders.isEmpty) {
          return Center(
            child: Text(
              provider.searchQuery.isNotEmpty ? settings.tr('nothing_found') : settings.tr('empty_list'),
              style: TextStyle(
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                fontSize: 16,
              ),
            ),
          );
        }

        return ReorderableListView.builder(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.screenPad, vertical: 4),
          itemCount: folders.length,
          onReorderItem: (oldIndex, newIndex) => provider.reorderRootFolders(oldIndex, newIndex),
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
          itemBuilder: (context, index) {
            final f = folders[index];
            return Padding(
              key: ValueKey(f.id),
              padding: const EdgeInsets.only(bottom: 8),
              child: FolderRow(folder: f),
            );
          },
        );
      },
    );
  }

  void _showCreateFolderSheet(BuildContext context) {
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
                      Iconsax.folder_minus,
                      color: textSecondary,
                      size: 24,
                    ),
                    const SizedBox(width: AppTheme.rowGap),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                        decoration: InputDecoration(
                          hintText: settings.tr('new_folder'),
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 16,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: (val) {
                          final v = val.trim();
                          if (v.isNotEmpty) {
                            try {
                              context.read<TaskProvider>().addFolder(v);
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(e.toString().replaceAll('Exception: ', '')),
                                ),
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
}
