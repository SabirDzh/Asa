import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'core/notification_service.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/tasks/providers/task_provider.dart';
import 'features/splash/splash_screen.dart';

import 'core/theme_switcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await NotificationService.init();
  } catch (_) {
    // Notifications are not critical; continue without them.
  }

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
      builder: (context, child) => _ScaledApp(
        scale: settingsProvider.appScale,
        child: child!,
      ),
      home: const SplashScreen(),
    );
  }
}

/// Scales the entire UI by [scale] while keeping hit-testing correct.
///
/// The app is laid out on a virtual canvas whose size is the physical
/// screen divided by [scale]. The painted output is then scaled back up to
/// fit the real screen, giving a true uniform UI scale. This means that a
/// value of 1.2 makes every widget 20 % larger, and 0.8 makes everything
/// 20 % smaller.
class _ScaledApp extends StatelessWidget {
  const _ScaledApp({required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
      final data = MediaQuery.of(context);

    // No scaling needed: avoid the extra layer and preserve exact layout.
    if ((scale - 1.0).abs() < 0.001) {
      return GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        behavior: HitTestBehavior.translucent,
        child: RepaintBoundary(
          key: ThemeSwitcher.boundaryKey,
          child: child,
        ),
      );
    }

    final scaledSize = Size(
      data.size.width / scale,
      data.size.height / scale,
    );

    final scaledMediaQuery = data.copyWith(
      size: scaledSize,
      padding: data.padding / scale,
      viewPadding: data.viewPadding / scale,
      viewInsets: data.viewInsets / scale,
      // The system text scale is preserved. The [Transform.scale] below
      // scales the rendered output (including text) uniformly, so the final
      // text size equals `scale * systemTextScale`.
      textScaler: data.textScaler,
    );

    return OverflowBox(
      minWidth: scaledSize.width,
      maxWidth: scaledSize.width,
      minHeight: scaledSize.height,
      maxHeight: scaledSize.height,
      child: Transform.scale(
        scale: scale,
        child: MediaQuery(
          data: scaledMediaQuery,
          child: GestureDetector(
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            behavior: HitTestBehavior.translucent,
            child: RepaintBoundary(
              key: ThemeSwitcher.boundaryKey,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
