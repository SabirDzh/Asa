import 'package:flutter/material.dart';

import 'clipboard_utils.dart';
import 'theme.dart';
import 'input_utils.dart';

/// Options for the paste button inside the input bottom sheet.
class InputPasteOptions {
  final String tooltip;
  final String errorText;

  const InputPasteOptions({
    required this.tooltip,
    required this.errorText,
  });
}

void showInputSheet({
  required BuildContext context,
  required IconData icon,
  required String hintText,
  required TextEditingController controller,
  required void Function(String, BuildContext) onSubmit,
  InputPasteOptions? paste,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final inputBg = isDark ? AppColors.surfaceSecondaryDark : AppColors.surfaceSecondaryLight;
  final sheetBg = isDark ? AppColors.sheetDark : AppColors.sheetLight;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _InputSheetBody(
      icon: icon,
      hintText: hintText,
      controller: controller,
      inputBg: inputBg,
      sheetBg: sheetBg,
      paste: paste,
      onSubmit: onSubmit,
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

  const _InputSheetBody({
    required this.icon,
    required this.hintText,
    required this.controller,
    required this.inputBg,
    required this.sheetBg,
    required this.paste,
    required this.onSubmit,
  });

  @override
  State<_InputSheetBody> createState() => _InputSheetBodyState();
}

class _InputSheetBodyState extends State<_InputSheetBody> {
  String? _errorText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).size.height * 0.10,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: widget.sheetBg,
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
            _handleBar(),
            const SizedBox(height: AppTheme.sheetGap),
            _inputRow(),
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
    final isDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    final iconColor = isDark ? Colors.white70 : Colors.black54;

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
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black54,
                  fontSize: 16,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                suffixIcon: widget.paste != null
                    ? IconButton(
                        tooltip: widget.paste!.tooltip,
                        icon: Icon(
                          Icons.content_paste_rounded,
                          color: iconColor,
                          size: 22,
                        ),
                        onPressed: handlePaste,
                      )
                    : null,
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
        ],
      ),
    );
  }

  String _truncate(String text) {
    if (text.length <= kMaxTextInputLength) return text;
    return text.substring(0, kMaxTextInputLength);
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
    final buttonItems = editableTextState.contextMenuButtonItems.map((item) {
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

Widget _handleBar() {
  return Center(
    child: Container(
      width: 48,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.sheetHandleRadius),
      ),
    ),
  );
}
