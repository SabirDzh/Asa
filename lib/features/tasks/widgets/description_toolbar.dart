import 'package:flutter/material.dart';

import '../../../core/app_strings.dart';

class DescriptionToolbar extends StatelessWidget {
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onCode;
  final VoidCallback onBulletedList;
  final VoidCallback onQuote;
  final VoidCallback onLink;

  const DescriptionToolbar({
    super.key,
    required this.onBold,
    required this.onItalic,
    required this.onCode,
    required this.onBulletedList,
    required this.onQuote,
    required this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return Semantics(
      container: true,
      label: AppStrings.get('description_formatting', languageCode),
      child: SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          children: [
            _tool(context, 'description_bold', Icons.format_bold, onBold),
            _tool(context, 'description_italic', Icons.format_italic, onItalic),
            _tool(context, 'description_code', Icons.code, onCode),
            _tool(
              context,
              'description_bulleted_list',
              Icons.format_list_bulleted,
              onBulletedList,
            ),
            _tool(context, 'description_quote', Icons.format_quote, onQuote),
            _tool(context, 'description_link', Icons.link, onLink),
          ],
        ),
      ),
    );
  }

  Widget _tool(
    BuildContext context,
    String tooltipKey,
    IconData icon,
    VoidCallback onPressed,
  ) {
    final tooltip = AppStrings.get(
      tooltipKey,
      Localizations.localeOf(context).languageCode,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        key: ValueKey('description-toolbar-$tooltipKey'),
        tooltip: tooltip,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
      ),
    );
  }
}
