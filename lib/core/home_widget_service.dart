import 'package:home_widget/home_widget.dart';

import '../features/settings/providers/settings_provider.dart';
import '../features/tasks/providers/task_provider.dart';

/// Updates the Android home screen widget when task or streak data changes.
///
/// This is the single place that talks to the `home_widget` plugin. It keeps
/// the last known data so callers can update just the parts they own (task
/// data or settings) without causing redundant platform updates.
class HomeWidgetService {
  static int _lastStreak = -1;
  static int _lastActive = -1;
  static String? _lastFolder;
  static bool _lastEnabled = true;
  static WidgetDisplayMode _lastMode = WidgetDisplayMode.streak;

  /// Saves the current task data and refreshes the widget.
  static void updateData(TaskProvider provider) {
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
    _performUpdate();
  }

  /// Saves the current widget settings and refreshes the widget.
  static void updateSettings({
    required bool enabled,
    required WidgetDisplayMode mode,
  }) {
    if (enabled == _lastEnabled && mode == _lastMode) return;

    _lastEnabled = enabled;
    _lastMode = mode;
    _performUpdate();
  }

  static Future<void> _performUpdate() async {
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
    } catch (_) {
      // Widget updates are best-effort; don't crash the app.
    }
  }
}
