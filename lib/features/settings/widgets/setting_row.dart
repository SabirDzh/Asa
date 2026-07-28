import 'package:flutter/material.dart';
import '../../../core/theme.dart';

class SettingRow extends StatelessWidget {
  final Color surface;
  final IconData icon;
  final String label;
  final Color textColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const SettingRow({
    super.key,
    required this.surface,
    required this.icon,
    required this.label,
    required this.textColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
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
              Icon(icon, color: textColor, size: 24),
              const SizedBox(width: AppTheme.rowGap),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
