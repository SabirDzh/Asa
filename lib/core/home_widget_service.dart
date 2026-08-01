import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final String tasksJson;
  final String foldersJson;

  const _WidgetSnapshot({
    required this.streak,
    required this.activeTasks,
    required this.lastFolder,
    required this.enabled,
    required this.mode,
    required this.tasksJson,
    required this.foldersJson,
  });

  @override
  bool operator ==(Object other) {
    return other is _WidgetSnapshot &&
        other.streak == streak &&
        other.activeTasks == activeTasks &&
        other.lastFolder == lastFolder &&
        other.enabled == enabled &&
        other.mode == mode &&
        other.tasksJson == tasksJson &&
        other.foldersJson == foldersJson;
  }

  @override
  int get hashCode => Object.hash(
    streak,
    activeTasks,
    lastFolder,
    enabled,
    mode,
    tasksJson,
    foldersJson,
  );
}

@pragma('vm:entry-point')
Future<void> homeWidgetBackgroundCallback(Uri? uri) async {
  if (uri == null || uri.host != 'widget') return;
  final action = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
  if (action != 'complete') return;

  final taskId = uri.queryParameters['taskId'];
  if (taskId == null || taskId.trim().isEmpty) return;

  final prefs = await SharedPreferences.getInstance();
  final rawTasks = prefs.getString('saved_tasks');
  if (rawTasks == null) return;

  final decoded = _decodeWidgetList(rawTasks);
  if (decoded == null) return;
  var changed = false;
  final tasks = <Map<String, dynamic>>[];
  for (final entry in decoded) {
    if (entry is! Map) continue;
    final task = Map<String, dynamic>.from(entry);
    if (task['id'] == taskId &&
        task['isDeleted'] != true &&
        task['isCompleted'] != true) {
      final startedAt = DateTime.tryParse(
        task['timerStartedAt']?.toString() ?? '',
      );
      final elapsed =
          (task['timerElapsedSeconds'] is num)
              ? (task['timerElapsedSeconds'] as num).toInt()
              : 0;
      final additionalSeconds =
          startedAt == null
              ? 0
              : DateTime.now()
                  .difference(startedAt)
                  .inSeconds
                  .clamp(0, 1 << 31);
      task['isCompleted'] = true;
      task['timerStartedAt'] = null;
      task['timerElapsedSeconds'] = elapsed + additionalSeconds;
      task['updatedAt'] = DateTime.now().toIso8601String();
      changed = true;
    }
    tasks.add(task);
  }
  if (!changed) return;

  await prefs.setString('saved_tasks', jsonEncode(tasks));
  final pending = _readPendingCompletionIds(
    prefs.getString(HomeWidgetService.pendingCompletionKey),
  );
  if (!pending.contains(taskId)) pending.add(taskId);
  if (pending.length > HomeWidgetService.maxPendingCompletions) {
    pending.removeRange(
      0,
      pending.length - HomeWidgetService.maxPendingCompletions,
    );
  }
  await prefs.setString(
    HomeWidgetService.pendingCompletionKey,
    jsonEncode(pending),
  );
  final activeTasks =
      tasks
          .where(
            (task) => task['isDeleted'] != true && task['isCompleted'] != true,
          )
          .toList();
  final active =
      activeTasks
          .take(50)
          .map(
            (task) => <String, dynamic>{
              'id': task['id'],
              'title': _compactWidgetText(task['title'], 120),
              'completed': false,
              'folderId': task['folderId'],
            },
          )
          .toList();
  await HomeWidget.saveWidgetData<int>('active_tasks', activeTasks.length);
  await HomeWidget.saveWidgetData<String>(
    'widget_tasks_json',
    jsonEncode(active),
  );
  await HomeWidget.updateWidget(androidName: 'AsaWidgetProvider');
  await HomeWidget.updateWidget(androidName: 'AsaWidgetStatsProvider');
  await HomeWidget.updateWidget(androidName: 'AsaWidgetTasksProvider');
}

List<dynamic>? _decodeWidgetList(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return decoded is List<dynamic> ? decoded : null;
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}

List<String> _readPendingCompletionIds(String? raw) {
  if (raw == null || raw.trim().isEmpty) return <String>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded
          .whereType<String>()
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .take(HomeWidgetService.maxPendingCompletions)
          .toList();
    }
  } on FormatException {
    // The old implementation stored one raw ID. Preserve it during rollout.
    final legacyId = raw.trim();
    if (legacyId.isNotEmpty) return <String>[legacyId];
  } on TypeError {
    // A malformed queue is discarded rather than blocking future actions.
  }
  return <String>[];
}

String _compactWidgetText(Object? value, int maxLength) {
  final text = value is String ? value.trim() : '';
  return text.length <= maxLength ? text : text.substring(0, maxLength);
}

class HomeWidgetService {
  HomeWidgetService._();

  /// SharedPreferences key written by the Android widget callback. The main
  /// Flutter isolate consumes it after returning to the foreground so the
  /// in-memory TaskProvider cannot diverge from the background update.
  static const pendingCompletionKey = 'widget_pending_complete_task';
  static const maxPendingCompletions = 32;
  static final HomeWidgetService instance = HomeWidgetService._();

  int _lastStreak = -1;
  int _lastActive = -1;
  String? _lastFolder;
  String _lastTasksJson = '[]';
  String _lastFoldersJson = '[]';
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

  /// Registers the background callback used by interactive Android widgets.
  static Future<bool?> registerInteractivityCallback() =>
      HomeWidget.registerInteractivityCallback(homeWidgetBackgroundCallback);

  /// URI supplied when the app was launched from a widget.
  static Future<Uri?> initiallyLaunchedFromWidget() =>
      HomeWidget.initiallyLaunchedFromHomeWidget();

  /// Stream of widget launch URIs received while the app is running.
  static Stream<Uri?> get widgetClicks => HomeWidget.widgetClicked;

  /// Returns and clears completion actions received while Android was
  /// handling widget taps in the background.
  static Future<List<String>> consumePendingCompletions() async {
    final prefs = await SharedPreferences.getInstance();
    final taskIds = _readPendingCompletionIds(
      prefs.getString(pendingCompletionKey),
    );
    if (taskIds.isNotEmpty) await prefs.remove(pendingCompletionKey);
    return taskIds;
  }

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

  static String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return value.substring(0, maxLength);
  }

  void _updateData(TaskProvider provider) {
    final activeTasks = provider.tasks.where((t) => !t.isCompleted).toList();
    final active = activeTasks.length;
    final streak = provider.streakCount;
    final folder = provider.lastViewedFolderName;
    final tasksJson = jsonEncode(
      activeTasks.take(50).map((task) {
        final title = task.title.trim();
        return {
          'id': task.id,
          'title': _truncate(title, 120),
          'completed': task.isCompleted,
          'folderId': task.folderId,
        };
      }).toList(),
    );
    final foldersJson = jsonEncode(
      provider.folders.take(50).map((folder) {
        final name = folder.name.trim();
        return {
          'id': folder.id,
          'name': _truncate(name, 80),
          'system': folder.isSystemStreak,
        };
      }).toList(),
    );

    if (_hasPublished &&
        active == _lastActive &&
        streak == _lastStreak &&
        folder == _lastFolder &&
        tasksJson == _lastTasksJson &&
        foldersJson == _lastFoldersJson) {
      return;
    }

    _lastActive = active;
    _lastStreak = streak;
    _lastFolder = folder;
    _lastTasksJson = tasksJson;
    _lastFoldersJson = foldersJson;
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
    tasksJson: _lastTasksJson,
    foldersJson: _lastFoldersJson,
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
    _lastTasksJson = '[]';
    _lastFoldersJson = '[]';
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
        await HomeWidget.saveWidgetData<String>(
          'widget_tasks_json',
          snapshot.tasksJson,
        );
        await HomeWidget.saveWidgetData<String>(
          'widget_folders_json',
          snapshot.foldersJson,
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
