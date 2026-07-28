import 'package:flutter/material.dart';

import 'theme.dart';
import 'input_utils.dart';void showInputSheet({
  required BuildContext context,
  required IconData icon,
  required String hintText,
  required TextEditingController controller,
  required void Function(String, BuildContext) onSubmit,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final inputBg = isDark ? AppColors.surfaceSecondaryDark : AppColors.surfaceSecondaryLight;
  final sheetBg = isDark ? AppColors.sheetDark : AppColors.sheetLight;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).size.height * 0.08,
      ),
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
            _handleBar(),
            const SizedBox(height: AppTheme.sheetGap),
            _inputRow(
              icon: icon,
              hintText: hintText,
              controller: controller,
              inputBg: inputBg,
              onSubmit: (val) => onSubmit(val, ctx),
            ),
          ],
        ),
      ),
    ),
  );
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

Widget _inputRow({
  required IconData icon,
  required String hintText,
  required TextEditingController controller,
  required Color inputBg,
  required ValueChanged<String> onSubmit,
}) {
  final isDark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
  return Container(
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
        Icon(icon, color: isDark ? Colors.white70 : Colors.black54, size: 24),
        const SizedBox(width: AppTheme.rowGap),
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: true,
            inputFormatters: [textInputFormatter()],
            style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54,
                fontSize: 16,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: onSubmit,
          ),
        ),
      ],
    ),
  );
}
