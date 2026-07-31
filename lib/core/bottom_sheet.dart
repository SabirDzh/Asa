import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:iconsax/iconsax.dart';

import 'clipboard_utils.dart';
import 'theme.dart';
import 'input_utils.dart';

/// Options for the paste button inside the input bottom sheet.
class InputPasteOptions {
  final String tooltip;
  final String errorText;

  const InputPasteOptions({required this.tooltip, required this.errorText});
}

void showInputSheet({
  required BuildContext context,
  required IconData icon,
  required String hintText,
  required TextEditingController controller,
  required void Function(String, BuildContext) onSubmit,
  InputPasteOptions? paste,
  List<String>? folderIconAssets,
  String? selectedIconAsset,
  ValueChanged<String?>? onIconSelected,
  String? noIconLabel,
  Map<String, String>? iconLabels,
  String? iconPickerTitle,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final inputBg =
      isDark ? AppColors.surfaceSecondaryDark : AppColors.surfaceSecondaryLight;
  final sheetBg = isDark ? AppColors.sheetDark : AppColors.sheetLight;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (ctx) => _InputSheetBody(
          icon: icon,
          hintText: hintText,
          controller: controller,
          inputBg: inputBg,
          sheetBg: sheetBg,
          paste: paste,
          onSubmit: onSubmit,
          folderIconAssets: folderIconAssets,
          selectedIconAsset: selectedIconAsset,
          onIconSelected: onIconSelected,
          noIconLabel: noIconLabel,
          iconLabels: iconLabels,
          iconPickerTitle: iconPickerTitle,
        ),
  );
}

class _InputSheetBody extends StatefulWidget {
  final IconData icon;
  final String hintText;
  final TextEditingController controller;
  final Color inputBg;
  final Color sheetBg;
  final InputPasteOptions? paste;
  final void Function(String, BuildContext) onSubmit;
  final List<String>? folderIconAssets;
  final String? selectedIconAsset;
  final ValueChanged<String?>? onIconSelected;
  final String? noIconLabel;
  final Map<String, String>? iconLabels;
  final String? iconPickerTitle;

  const _InputSheetBody({
    required this.icon,
    required this.hintText,
    required this.controller,
    required this.inputBg,
    required this.sheetBg,
    required this.paste,
    required this.onSubmit,
    this.folderIconAssets,
    this.selectedIconAsset,
    this.onIconSelected,
    this.noIconLabel,
    this.iconLabels,
    this.iconPickerTitle,
  });

  @override
  State<_InputSheetBody> createState() => _InputSheetBodyState();
}

class _InputSheetBodyState extends State<_InputSheetBody> {
  String? _errorText;
  String? _selectedIconAsset;

  @override
  void initState() {
    super.initState();
    _selectedIconAsset = widget.selectedIconAsset;
  }

  void _selectIcon(String? asset) {
    setState(() => _selectedIconAsset = asset);
    widget.onIconSelected?.call(asset);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: widget.sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.only(
          top: 12,
          left: AppTheme.sheetPadH,
          right: AppTheme.sheetPadH,
          bottom: 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _handleBar(isDark: Theme.of(context).brightness == Brightness.dark),
            const SizedBox(height: 36),
            _inputRow(),
            if (widget.folderIconAssets != null &&
                widget.folderIconAssets!.isNotEmpty) ...[
              const SizedBox(height: 16),
              if (widget.iconPickerTitle != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    widget.iconPickerTitle!,
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              _iconPicker(),
            ],
            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _errorText!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _inputRow() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final textColor = isDark ? AppColors.textDark : AppColors.textLight;
    final hintColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    Future<void> handlePaste() async {
      final text = await getClipboardText();
      if (!mounted) return;
      if (text == null) {
        setState(() => _errorText = widget.paste?.errorText);
        return;
      }
      setState(() => _errorText = null);
      insertTextAtCursor(widget.controller, _truncate(text));
    }

    return Container(
      height: AppTheme.rowHeight,
      decoration: BoxDecoration(
        color: widget.inputBg,
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.rowPadH,
        vertical: AppTheme.rowPadV,
      ),
      child: Row(
        children: [
          Icon(widget.icon, color: iconColor, size: 24),
          const SizedBox(width: AppTheme.rowGap),
          Expanded(
            child: TextField(
              controller: widget.controller,
              autofocus: true,
              inputFormatters: [textInputFormatter()],
              style: TextStyle(color: textColor, fontSize: 16),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: TextStyle(color: hintColor, fontSize: 16),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              contextMenuBuilder: (context, editableTextState) {
                return _buildContextMenu(
                  context: context,
                  controller: widget.controller,
                  editableTextState: editableTextState,
                  onPaste: handlePaste,
                );
              },
              onSubmitted: (val) => widget.onSubmit(val, context),
            ),
          ),
          if (widget.paste != null) ...[
            IconButton(
              tooltip: widget.paste!.tooltip,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              icon: Icon(
                Icons.content_paste_rounded,
                color: iconColor,
                size: 24,
              ),
              onPressed: handlePaste,
            ),
          ],
        ],
      ),
    );
  }

  String _truncate(String text) {
    if (text.length <= kMaxTextInputLength) return text;
    return text.substring(0, kMaxTextInputLength);
  }

  Widget _iconPicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = AppColors.primary;
    final inactiveColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          _iconTile(null, activeColor, inactiveColor),
          for (final asset in widget.folderIconAssets!)
            _iconTile(asset, activeColor, inactiveColor),
        ],
      ),
    );
  }

  Widget _iconTile(String? asset, Color activeColor, Color inactiveColor) {
    final isSelected = _selectedIconAsset == asset;
    final tile = Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: () => _selectIcon(asset),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: 0.15) : null,
            border: Border.all(
              color:
                  isSelected
                      ? activeColor
                      : inactiveColor.withValues(alpha: 0.3),
              width: 2,
            ),
            borderRadius: BorderRadius.circular(AppTheme.pillRadius),
          ),
          alignment: Alignment.center,
          child:
              asset == null
                  ? Icon(Iconsax.folder_minus, color: inactiveColor, size: 24)
                  : SvgPicture.asset(
                    asset,
                    width: 24,
                    height: 24,
                    colorFilter: ColorFilter.mode(
                      isSelected ? activeColor : inactiveColor,
                      BlendMode.srcIn,
                    ),
                  ),
        ),
      ),
    );
    return Tooltip(message: _iconLabel(asset), child: tile);
  }

  String _iconLabel(String? asset) {
    if (asset == null) return widget.noIconLabel ?? 'Default icon';
    if (widget.iconLabels != null && widget.iconLabels!.containsKey(asset)) {
      return widget.iconLabels![asset]!;
    }
    final name = asset.split('/').last.replaceAll('.svg', '');
    if (name.isEmpty) return asset;
    return '${name[0].toUpperCase()}${name.substring(1)}';
  }

  Widget _buildContextMenu({
    required BuildContext context,
    required TextEditingController controller,
    required EditableTextState editableTextState,
    required Future<void> Function() onPaste,
  }) {
    final localizations = MaterialLocalizations.of(context);
    final pasteLabel = localizations.pasteButtonLabel;

    // Preserve the platform's default menu items and only override Paste
    // so that actions like Look Up / Share / Autofill remain available.
    // We identify the Paste item by its localized label; this is the same
    // identifier the framework uses when building the default menu.
    final buttonItems =
        editableTextState.contextMenuButtonItems.map((item) {
          if (item.label == pasteLabel) {
            return ContextMenuButtonItem(
              onPressed: () async {
                editableTextState.hideToolbar();
                await onPaste();
              },
              label: pasteLabel,
            );
          }
          return item;
        }).toList();

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }
}

Widget _handleBar({required bool isDark}) {
  return Center(
    child: Container(
      width: 48,
      height: 4,
      decoration: BoxDecoration(
        color: isDark ? Colors.white54 : Colors.black26,
        borderRadius: BorderRadius.circular(AppTheme.sheetHandleRadius),
      ),
    ),
  );
}
