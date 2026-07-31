import 'dart:async';

import 'package:flutter/foundation.dart';
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
class _WidgetSnapshot {
  final int streak;
  final int activeTasks;
  final String? lastFolder;
  final bool enabled;
  final WidgetDisplayMode mode;

  const _WidgetSnapshot({
    required this.streak,
    required this.activeTasks,
    required this.lastFolder,
    required this.enabled,
    required this.mode,
  });

  @override
  bool operator ==(Object other) {
    return other is _WidgetSnapshot &&
        other.streak == streak &&
        other.activeTasks == activeTasks &&
        other.lastFolder == lastFolder &&
        other.enabled == enabled &&
        other.mode == mode;
  }

  @override
  int get hashCode =>
      Object.hash(streak, activeTasks, lastFolder, enabled, mode);
}

class HomeWidgetService {
  HomeWidgetService._();
  static final HomeWidgetService instance = HomeWidgetService._();

  int _lastStreak = -1;
  int _lastActive = -1;
  String? _lastFolder;
  bool _lastEnabled = true;
  WidgetDisplayMode _lastMode = WidgetDisplayMode.activeTasks;
  bool _hasPublished = false;
  DateTime? _lastForcedRefreshAt;

  Timer? _debounce;
  Future<void>? _updateInFlight;
  bool _updateQueued = false;
  _WidgetSnapshot? _lastRequestedSnapshot;
  int _generation = 0;

  @visibleForTesting
  Future<void> Function()? updateOverride;

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
  }) => instance._updateSettings(enabled: enabled, mode: mode);

  /// Cancels any pending widget update. Useful in tests to avoid leaking
  /// timers between test cases.
  static void cancelPendingUpdate() => instance._cancelPendingUpdate();

  /// Requests a fresh native widget publish using the latest cached values.
  /// This is used when the app resumes because the launcher may have cleared
  /// its native widget state while the Flutter process was backgrounded.
  /// Repeated resumes within a short window are throttled to avoid redundant
  /// platform writes while still recovering from normal background/foreground
  /// transitions.
  static void refresh() => instance._refresh();

  /// Resets cached widget state between isolated widget tests.
  ///
  /// Awaiting an active native update prevents platform calls from leaking
  /// into the next isolated test while the generation guard prevents the
  /// completed operation from publishing stale state after reset.
  static Future<void> resetForTests() => instance._resetForTests();

  void _updateData(TaskProvider provider) {
    final active = provider.tasks.where((t) => !t.isCompleted).length;
    final streak = provider.streakCount;
    final folder = provider.lastViewedFolderName;

    if (_hasPublished &&
        active == _lastActive &&
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
    if (_hasPublished && enabled == _lastEnabled && mode == _lastMode) return;

    _lastEnabled = enabled;
    _lastMode = mode;
    _scheduleUpdate();
  }

  void _scheduleUpdate({bool force = false}) {
    final snapshot = _currentSnapshot();
    if (!force && snapshot == _lastRequestedSnapshot) return;
    _lastRequestedSnapshot = snapshot;
    _updateQueued = true;
    _debounce?.cancel();
    _debounce = Timer(debounceDelay, () {
      _debounce = null;
      unawaited(_runQueuedUpdate());
    });
  }

  _WidgetSnapshot _currentSnapshot() => _WidgetSnapshot(
    streak: _lastStreak,
    activeTasks: _lastActive,
    lastFolder: _lastFolder,
    enabled: _lastEnabled,
    mode: _lastMode,
  );

  Future<void> _runQueuedUpdate() async {
    if (!_updateQueued) return;
    final inFlight = _updateInFlight;
    if (inFlight != null) {
      // The active update owns the platform channel. It will start the latest
      // queued snapshot when it completes.
      await inFlight;
      return;
    }

    _updateQueued = false;
    final snapshot = _currentSnapshot();
    final generation = _generation;
    final future = _performUpdate(snapshot, generation);
    _updateInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_updateInFlight, future)) _updateInFlight = null;
      if (_updateQueued && _debounce == null) {
        unawaited(_runQueuedUpdate());
      }
    }
  }

  void _refresh() {
    final now = DateTime.now();
    if (_hasPublished &&
        _lastForcedRefreshAt != null &&
        now.difference(_lastForcedRefreshAt!) < const Duration(seconds: 5)) {
      return;
    }
    _lastForcedRefreshAt = now;
    _scheduleUpdate(force: true);
  }

  void _cancelPendingUpdate() {
    _debounce?.cancel();
    _debounce = null;
    _updateQueued = false;
    _lastRequestedSnapshot = null;
  }

  Future<void> _resetForTests() async {
    _generation++;
    _cancelPendingUpdate();
    final inFlight = _updateInFlight;
    if (inFlight != null) await inFlight;
    _lastStreak = -1;
    _lastActive = -1;
    _lastFolder = null;
    _lastEnabled = true;
    _lastMode = WidgetDisplayMode.activeTasks;
    _hasPublished = false;
    _lastForcedRefreshAt = null;
    _lastRequestedSnapshot = null;
    updateOverride = null;
    _updateQueued = false;
  }

  Future<void> _performUpdate(_WidgetSnapshot snapshot, int generation) async {
    try {
      final override = updateOverride;
      if (override != null) {
        await override();
      } else {
        await HomeWidget.saveWidgetData<int>('streak', snapshot.streak);
        await HomeWidget.saveWidgetData<int>(
          'active_tasks',
          snapshot.activeTasks,
        );
        await HomeWidget.saveWidgetData<String?>(
          'last_folder',
          snapshot.lastFolder,
        );
        await HomeWidget.saveWidgetData<bool>(
          'widget_enabled',
          snapshot.enabled,
        );
        await HomeWidget.saveWidgetData<String>(
          'widget_mode',
          snapshot.mode.name,
        );
        await HomeWidget.updateWidget(androidName: 'AsaWidgetProvider');
        await HomeWidget.updateWidget(androidName: 'AsaWidgetStatsProvider');
        await HomeWidget.updateWidget(androidName: 'AsaWidgetTasksProvider');
      }
      if (generation == _generation) {
        _hasPublished = true;
      }
    } catch (_) {
      if (generation == _generation && _lastRequestedSnapshot == snapshot) {
        _lastRequestedSnapshot = null;
      }
      // Widget updates are best-effort; don't crash the app.
    }
  }
}
