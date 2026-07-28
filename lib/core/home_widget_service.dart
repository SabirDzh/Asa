import 'package:home_widget/home_widget.dart';

import '../features/tasks/providers/task_provider.dart';

/// Updates the Android home screen widget when task or streak data changes.
///
/// Updates are only sent when the displayed values (streak / active task count)
/// actually change, so rapid mutations of unrelated state don't spam the system.
class HomeWidgetService {
  static int _lastStreak = -1;
  static int _lastActive = -1;

  /// Saves the current streak and active task count, then refreshes the widget.
  ///
  /// This is a fire-and-forget call; it returns immediately and the actual
  /// platform work happens asynchronously.
  static void update(TaskProvider provider) {
    final active = provider.tasks.where((t) => !t.isCompleted).length;
    final streak = provider.streakCount;

    if (active == _lastActive && streak == _lastStreak) return;

    _lastActive = active;
    _lastStreak = streak;

    _performUpdate(active, streak);
  }

  static Future<void> _performUpdate(int active, int streak) async {
    try {
      await HomeWidget.saveWidgetData<int>('streak', streak);
      await HomeWidget.saveWidgetData<int>('active_tasks', active);
      await HomeWidget.updateWidget(androidName: 'AsaWidgetProvider');
    } catch (_) {
      // Widget updates are best-effort; don't crash the app.
    }
  }
}
