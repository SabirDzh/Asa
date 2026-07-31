import 'dart:async';

import 'package:home_widget/home_widget.dart';

import '../features/settings/providers/settings_provider.dart';
import '../features/tasks/providers/task_provider.dart';

/// Updates the Android home screen widget when task or streak data changes.
///
/// This is the single place that talks to the `home_widget` plugin. It keeps
/// the last known data so callers can update just the parts they own (task
/// data or settings). Updates are debounced so rapid changes (e.g. on app
/// startup when both settings and task data are ready) are batched into a
/// single platform call.
class HomeWidgetService {
  HomeWidgetService._();
  static final HomeWidgetService instance = HomeWidgetService._();

  int _lastStreak = -1;
  int _lastActive = -1;
  String? _lastFolder;
  bool _lastEnabled = true;
  WidgetDisplayMode _lastMode = WidgetDisplayMode.activeTasks;

  Timer? _debounce;

  /// Debounce duration. Can be set to [Duration.zero] in tests to avoid
  /// leaking timers across test cases.
  Duration debounceDelay = const Duration(milliseconds: 300);

  /// Saves the current task data and refreshes the widget.
  static void updateData(TaskProvider provider) =>
      instance._updateData(provider);

  /// Saves the current widget settings and refreshes the widget.
  static void updateSettings({
    required bool enabled,
    required WidgetDisplayMode mode,
  }) =>
      instance._updateSettings(enabled: enabled, mode: mode);

  /// Cancels any pending widget update. Useful in tests to avoid leaking
  /// timers between test cases.
  static void cancelPendingUpdate() => instance._cancelPendingUpdate();

  /// Resets cached widget state between isolated widget tests.
  static void resetForTests() => instance._resetForTests();

  void _updateData(TaskProvider provider) {
    final active = provider.tasks.where((t) => !t.isCompleted).length;
    final streak = provider.streakCount;
    final folder = provider.lastViewedFolderName;

    if (active == _lastActive &&
        streak == _lastStreak &&
        folder == _lastFolder) {
      return;
    }

    _lastActive = active;
    _lastStreak = streak;
    _lastFolder = folder;
    _scheduleUpdate();
  }

  void _updateSettings({
    required bool enabled,
    required WidgetDisplayMode mode,
  }) {
    if (enabled == _lastEnabled && mode == _lastMode) return;

    _lastEnabled = enabled;
    _lastMode = mode;
    _scheduleUpdate();
  }

  void _scheduleUpdate() {
    _debounce?.cancel();
    _debounce = Timer(debounceDelay, _performUpdate);
  }

  void _cancelPendingUpdate() {
    _debounce?.cancel();
    _debounce = null;
  }

  void _resetForTests() {
    _cancelPendingUpdate();
    _lastStreak = -1;
    _lastActive = -1;
    _lastFolder = null;
    _lastEnabled = true;
    _lastMode = WidgetDisplayMode.activeTasks;
  }

  Future<void> _performUpdate() async {
    _debounce?.cancel();
    _debounce = null;
    try {
      await HomeWidget.saveWidgetData<int>('streak', _lastStreak);
      await HomeWidget.saveWidgetData<int>('active_tasks', _lastActive);
      await HomeWidget.saveWidgetData<String?>(
        'last_folder',
        _lastFolder,
      );
      await HomeWidget.saveWidgetData<bool>('widget_enabled', _lastEnabled);
      await HomeWidget.saveWidgetData<String>(
        'widget_mode',
        _lastMode.name,
      );
      await HomeWidget.updateWidget(androidName: 'AsaWidgetProvider');
      await HomeWidget.updateWidget(androidName: 'AsaWidgetStatsProvider');
      await HomeWidget.updateWidget(androidName: 'AsaWidgetTasksProvider');
    } catch (_) {
      // Widget updates are best-effort; don't crash the app.
    }
  }
}
