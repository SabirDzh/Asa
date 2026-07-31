import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'core/theme.dart';
import 'core/notification_service.dart';
import 'core/scale_utils.dart';
import 'core/logger_service.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/tasks/providers/task_provider.dart';
import 'features/splash/splash_screen.dart';

import 'core/theme_switcher.dart';
import 'core/home_widget_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  try {
    tz.setLocalLocation(tz.getLocation(DateTime.now().timeZoneName));
  } catch (_) {
    // Some platforms expose only an abbreviation (for example, "MSK"),
    // which is not an IANA identifier. Keep the device's actual offset instead
    // of silently shifting reminders to UTC.
    final offset = DateTime.now().timeZoneOffset.inMilliseconds;
    tz.setLocalLocation(
      tz.Location(
        'device-offset',
        const <int>[],
        const <int>[],
        <tz.TimeZone>[
          tz.TimeZone(offset, isDst: false, abbreviation: 'LOCAL'),
        ],
      ),
    );
  }
  LoggerService.listenToFlutterErrors();

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

class AsaApp extends StatefulWidget {
  const AsaApp({super.key});

  @override
  State<AsaApp> createState() => _AsaAppState();
}

class _AsaAppState extends State<AsaApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final tasks = context.read<TaskProvider>();
    NotificationService.onStartTimerRequested = (taskId) async {
      await tasks.ready;
      tasks.startTimer(taskId);
    };
    _consumePendingTimerAction(tasks);
  }

  Future<void> _consumePendingTimerAction(TaskProvider tasks) async {
    await tasks.ready;
    final taskId = await NotificationService.consumePendingTimerStart();
    if (taskId != null) tasks.startTimer(taskId);
  }

  @override
  void dispose() {
    NotificationService.onStartTimerRequested = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final settings = context.read<SettingsProvider>();
    final tasks = context.read<TaskProvider>();
    _consumePendingTimerAction(tasks);
    HomeWidgetService.updateSettings(
      enabled: settings.showInWidget,
      mode: settings.widgetDisplayMode,
    );
    HomeWidgetService.updateData(tasks);
    HomeWidgetService.refresh();
  }

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
  final Widget child;  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    final effectiveScale = effectiveAppScale(context, scale);

    // No scaling needed: avoid the extra layer and preserve exact layout.
    if ((effectiveScale - 1.0).abs() < 0.001) {
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
      data.size.width / effectiveScale,
      data.size.height / effectiveScale,
    );

    final scaledMediaQuery = data.copyWith(
      size: scaledSize,
      padding: data.padding / effectiveScale,
      viewPadding: data.viewPadding / effectiveScale,
      viewInsets: data.viewInsets / effectiveScale,
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
        scale: effectiveScale,
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
