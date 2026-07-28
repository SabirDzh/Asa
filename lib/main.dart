import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/tasks/providers/task_provider.dart';
import 'features/tasks/screens/home_screen.dart';

import 'core/theme_switcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => TaskProvider()),
      ],
      child: const AsaApp(),
    ),
  );
}

class AsaApp extends StatelessWidget {
  const AsaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);

    return MaterialApp(
      title: 'ASA',
      debugShowCheckedModeBanner: false,
      themeMode: settingsProvider.themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      builder: (context, child) {
        return GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          behavior: HitTestBehavior.translucent,
          child: RepaintBoundary(
            key: ThemeSwitcher.boundaryKey,
            child: child!,
          ),
        );
      },
      home: const HomeScreen(),
    );
  }
}
