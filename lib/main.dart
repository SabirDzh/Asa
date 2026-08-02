import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'core/theme.dart';
import 'core/notification_service.dart';
import 'core/scale_utils.dart';
import 'core/logger_service.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/tasks/providers/task_provider.dart';
import 'features/tasks/screens/folder_detail_screen.dart';
import 'features/tasks/widgets/task_editor_sheet.dart';
import 'features/tasks/models/task_model.dart';
import 'features/splash/splash_screen.dart';

import 'core/theme_switcher.dart';
import 'core/home_widget_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LoggerService.listenToFlutterErrors();

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
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<Uri?>? _widgetClickSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _widgetClickSubscription = HomeWidgetService.widgetClicks.listen(
      (uri) => unawaited(_handleWidgetUri(uri)),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeNonCriticalServices());
    });
    final tasks = context.read<TaskProvider>();
    NotificationService.onStartTimerRequested = (taskId) async {
      await tasks.ready;
      tasks.startTimer(taskId);
    };
    _consumePendingTimerAction(tasks);
  }

  Future<void> _initializeNonCriticalServices() async {
    try {
      try {
        await HomeWidgetService.registerInteractivityCallback();
      } on Object catch (error, stackTrace) {
        LoggerService.instance.w(
          'Widget interactivity registration unavailable',
          error: error,
          stackTrace: stackTrace,
        );
      }
      tz_data.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation(DateTime.now().timeZoneName));
      } catch (_) {
        // Some platforms expose only an abbreviation (for example, "MSK"),
        // which is not an IANA identifier. Keep the device's actual offset
        // instead of silently shifting reminders to UTC.
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
      await NotificationService.init();
      if (!mounted) return;
      final settings = context.read<SettingsProvider>();
      await settings.ready;
      if (!mounted) return;
      final tasks = context.read<TaskProvider>();
      await tasks.ready;
      if (!mounted) return;
      await _consumePendingWidgetCompletion(tasks);
      final initialWidgetUri =
          await HomeWidgetService.initiallyLaunchedFromWidget();
      if (initialWidgetUri != null) {
        unawaited(_handleWidgetUri(initialWidgetUri));
      }
      if (settings.notificationsEnabled) {
        // The default-enabled setting must still request Android runtime
        // notification permission before reminders are scheduled. Exact-alarm
        // access is requested later from the explicit notification setting,
        // not on every app launch.
        final granted = await NotificationService.requestPermission(
          requestExactAlarms: false,
        );
        if (!granted && mounted) {
          // Keep the setting honest when Android/iOS denies runtime access;
          // otherwise reminders appear enabled but can never be delivered.
          await settings.toggleNotifications(false);
        }
      }
      // When the user revokes and later re-grants notification permission
      // through system settings while the app is killed, the saved blocked
      // flag must be cleared on the next launch so the toggle is interactive.
      if (!settings.notificationsEnabled &&
          settings.notificationsBlockedBySystem &&
          mounted) {
        await settings.syncNotificationPermission();
      }
      // Sync the loaded task snapshot directly. The notification cache is
      // populated by this call, avoiding a startup race with TaskProvider.
      await NotificationService.syncTasks(tasks.allTasks);
    } on Object catch (error, stackTrace) {
      LoggerService.instance.w(
        'Optional startup services failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _consumePendingTimerAction(TaskProvider tasks) async {
    await tasks.ready;
    final taskId = await NotificationService.consumePendingTimerStart();
    if (taskId != null) tasks.startTimer(taskId);
  }

  Future<void> _consumePendingWidgetCompletion(TaskProvider tasks) async {
    final taskIds = await HomeWidgetService.consumePendingCompletions();
    for (final taskId in taskIds) {
      tasks.completeTaskFromWidget(taskId);
    }
  }

  Future<void> _handleWidgetUri(Uri? uri) async {
    if (uri == null || uri.scheme != 'asa' || uri.host != 'widget') return;
    final tasks = context.read<TaskProvider>();
    await tasks.ready;
    if (!mounted) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    final action = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    if (action == 'add') {
      await showTaskEditorSheet(context, folderId: null);
      return;
    }
    if (action == 'folder') {
      final folderId = uri.queryParameters['folderId'];
      if (folderId == null || folderId.isEmpty) return;
      FolderItem? folder;
      for (final candidate in tasks.folders) {
        if (candidate.id == folderId) {
          folder = candidate;
          break;
        }
      }
      if (folder != null && navigator.mounted) {
        await navigator.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => FolderDetailScreen(folder: folder!),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    NotificationService.onStartTimerRequested = null;
    _widgetClickSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final tasks = context.read<TaskProvider>();
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(
        tasks.flushPersistence().catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          LoggerService.instance.w(
            'Background task persistence flush failed',
            error: error,
            stackTrace: stackTrace,
          );
        }),
      );
      return;
    }
    if (state != AppLifecycleState.resumed || !mounted) return;
    unawaited(_consumePendingWidgetCompletion(tasks));
    final settings = context.read<SettingsProvider>();
    unawaited(settings.syncNotificationPermission());
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
    // Only theme and scale affect the app shell. Language, sync and profile
    // changes are consumed by their feature widgets and must not rebuild the
    // entire MaterialApp tree.
    final themeMode = context.select<SettingsProvider, ThemeMode>(
      (settings) => settings.themeMode,
    );
    final appPalette = context.select<SettingsProvider, AppPalette>(
      (settings) => settings.appPalette,
    );
    final appScale = context.select<SettingsProvider, double>(
      (settings) => settings.appScale,
    );
    final languageCode = context.select<SettingsProvider, String>(
      (settings) => settings.languageCode,
    );

    return MaterialApp(
      title: 'ASA',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.lightThemeFor(appPalette),
      darkTheme: AppTheme.darkThemeFor(appPalette),
      locale: Locale(languageCode),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => _ScaledApp(scale: appScale, child: child!),
      navigatorKey: _navigatorKey,
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
    final effectiveScale = effectiveAppScale(context, scale);

    // No scaling needed: avoid the extra layer and preserve exact layout.
    if ((effectiveScale - 1.0).abs() < 0.001) {
      return GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        behavior: HitTestBehavior.translucent,
        child: RepaintBoundary(key: ThemeSwitcher.boundaryKey, child: child),
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
