import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../../../core/theme.dart';

void showLanguageSheet(BuildContext context) {
  final settings = Provider.of<SettingsProvider>(context, listen: false);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final navBg = isDark ? AppColors.navDark : AppColors.navLight;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: navBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              settings.tr('language'),
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Material(
              color: Colors.transparent,
              child: ListTile(
                title: const Text('Русский', style: TextStyle(color: Colors.white, fontSize: 16)),
                trailing: settings.languageCode == 'ru'
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () {
                  settings.setLanguage('ru');
                  Navigator.pop(ctx);
                },
              ),
            ),
            Material(
              color: Colors.transparent,
              child: ListTile(
                title: const Text('English', style: TextStyle(color: Colors.white, fontSize: 16)),
                trailing: settings.languageCode == 'en'
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () {
                  settings.setLanguage('en');
                  Navigator.pop(ctx);
                },
              ),
            ),
          ],
        ),
      ),
  );
}
