import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show
        AndroidFlutterLocalNotificationsPlugin,
        AndroidInitializationSettings,
        AndroidNotificationAction,
        AndroidNotificationDetails,
        AndroidScheduleMode,
        DarwinInitializationSettings,
        DarwinNotificationAction,
        DarwinNotificationCategory,
        DarwinNotificationDetails,
        FlutterLocalNotificationsPlugin,
        IOSFlutterLocalNotificationsPlugin,
        Importance,
        InitializationSettings,
        NotificationDetails,
        NotificationResponse,
        Priority,
        UILocalNotificationDateInterpretation;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../features/tasks/models/task_model.dart';
import 'logger_service.dart';

/// Thin wrapper around flutter_local_notifications.
/// Handles permissions, task-start reminders, and timer actions.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static String _languageCode = 'ru';
  static final Map<int, String> _scheduledFingerprints = <int, String>{};
  static const _taskChannelId = 'asa_task_start_channel';
  static const _taskCategoryIdRu = 'asa_task_start_category_ru';
  static const _taskCategoryIdEn = 'asa_task_start_category_en';
  static const _startTimerActionId = 'start_timer';
  static const _taskPayloadPrefix = 'asa_task:';
  static const _pendingTimerTaskKey = 'pending_timer_task_id';

  /// Set by the app after providers are mounted. Background isolates persist
  /// the request instead; the app consumes it when it starts/resumes.
  static Future<void> Function(String taskId)? onStartTimerRequested;

  @visibleForTesting
  static Future<bool?> Function()? notificationPermissionStateOverride;

  @visibleForTesting
  static Future<bool> Function({required bool requestExactAlarms})?
  requestPermissionOverride;

  @visibleForTesting
  static bool? initializedOverride;

  static bool get isInitialized => initializedOverride ?? _initialized;

  static void setLanguage(String languageCode) {
    if (languageCode == 'ru' || languageCode == 'en') {
      _languageCode = languageCode;
      _scheduledFingerprints.clear();
      unawaited(rescheduleCachedTasks());
    }
  }

  static String _tr(String ru, String en) => _languageCode == 'en' ? en : ru;

  /// The stable action identifier used by Android and iOS timer actions.
  @visibleForTesting
  static String get startTimerActionId => _startTimerActionId;

  /// Returns the payload used by notification actions for [taskId].
  @visibleForTesting
  static String taskPayloadForId(String taskId) => '$_taskPayloadPrefix$taskId';

  /// Returns the current system notification permission when the platform
  /// exposes it. A null result means the platform has no separate runtime
  /// notification permission (for example, older Android versions).
  static Future<bool?> notificationPermissionState() async {
    final override = notificationPermissionStateOverride;
    if (override != null) return override();
    if (kIsWeb || !isInitialized) return null;

    if (Platform.isAndroid) {
      final android =
          _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
      return android?.areNotificationsEnabled();
    }
    if (Platform.isIOS) {
      final iOS =
          _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >();
      return (await iOS?.checkPermissions())?.isEnabled;
    }
    return true;
  }

  /// Returns whether a task has a valid, non-zero period for a reminder.
  /// A start/end pair with the same time has no computable duration and must
  /// not create a notification that offers a timer which cannot start.
  @visibleForTesting
  static bool hasSchedulablePeriod(TaskItem task) {
    if (task.isDeleted || task.isCompleted) return false;
    final start = task.startTime;
    final end = task.endTime;
    if (start == null || end == null) return false;
    return TaskItem.durationForPeriod(start, end) != null;
  }

  /// Returns a deterministic positive notification ID for a task.
  static int notificationIdForTask(String taskId) {
    var hash = 2166136261;
    for (final unit in taskId.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return 100000 + (hash % 100000000);
  }

  /// Initializes the plugin. Must be called before any other method.
  static Future<void> init() async {
    if (kIsWeb) return;

    const android = AndroidInitializationSettings('@drawable/ic_notification');
    final iOS = DarwinInitializationSettings(
      notificationCategories: [
        DarwinNotificationCategory(
          _taskCategoryIdRu,
          actions: [
            DarwinNotificationAction.plain(
              _startTimerActionId,
              'Запустить таймер',
            ),
          ],
        ),
        DarwinNotificationCategory(
          _taskCategoryIdEn,
          actions: [
            DarwinNotificationAction.plain(_startTimerActionId, 'Start timer'),
          ],
        ),
      ],
    );
    final settings = InitializationSettings(android: android, iOS: iOS);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          notificationBackgroundResponseHandler,
    );
    _initialized = true;
  }

  /// Requests notification permission and, on Android, exact alarm access when
  /// the platform exposes that setting. Scheduling falls back to inexact alarms
  /// if exact access is unavailable.
  static Future<bool> requestPermission({
    bool requestExactAlarms = true,
  }) async {
    final override = requestPermissionOverride;
    if (override != null) {
      return override(requestExactAlarms: requestExactAlarms);
    }
    if (kIsWeb || !isInitialized) return false;

    var granted = false;
    if (Platform.isAndroid) {
      final android =
          _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
      final notificationPermission =
          await android?.requestNotificationsPermission();
      // Android versions before API 33 return null because no runtime
      // notification permission is required. Exact alarm access is separate
      // and is intentionally best-effort: scheduling falls back to inexact
      // alarms when the user declines it.
      if (requestExactAlarms && notificationPermission != false) {
        try {
          await android?.requestExactAlarmsPermission();
        } on Object catch (error, stackTrace) {
          LoggerService.instance.w(
            'Exact alarm permission request failed',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      granted = notificationPermission ?? true;
    } else if (Platform.isIOS) {
      final iOS =
          _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >();
      granted =
          await iOS?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    } else {
      granted = true;
    }
    return granted;
  }

  /// Shows a one-time test notification so the user can verify it works.
  static Future<void> showTestNotification() async {
    if (!_canUseNotifications) return;

    const androidDetails = AndroidNotificationDetails(
      'asa_test_channel',
      'ASA Test',
      channelDescription: 'Test notifications from ASA',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      showWhen: true,
    );
    const iOSDetails = DarwinNotificationDetails();
    await _plugin.show(
      0,
      'ASA',
      'Уведомления включены',
      const NotificationDetails(android: androidDetails, iOS: iOSDetails),
    );
  }

  /// Synchronizes all task-start reminders. Tasks without a complete period
  /// (start and end), completed tasks, and deleted tasks have their reminder
  /// cancelled.
  static Future<void> syncTasks(Iterable<TaskItem> tasks) async {
    final taskList = tasks.toList(growable: false);
    for (final task in taskList) {
      _cachedTasks[task.id] = task;
    }
    if (!_canUseNotifications) return;
    for (final task in taskList) {
      try {
        await syncTaskStart(task);
      } on Object catch (error, stackTrace) {
        // One unsupported or malformed task must not prevent other reminders
        // from being synchronized.
        LoggerService.instance.w(
          'Task notification sync failed for ${task.id}',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  /// Returns the next local occurrence of a task start time.
  ///
  /// The task editor stores a time of day rather than a calendar date, so the
  /// reminder is intentionally treated as a daily schedule: a time that has
  /// already passed today is scheduled for tomorrow.
  static tz.TZDateTime nextScheduledStart(DateTime startTime, {DateTime? now}) {
    final current =
        now == null
            ? tz.TZDateTime.now(tz.local)
            : tz.TZDateTime.from(now, tz.local);
    var scheduled = tz.TZDateTime.from(startTime, tz.local);
    if (!scheduled.isAfter(current)) {
      scheduled = tz.TZDateTime(
        tz.local,
        current.year,
        current.month,
        current.day + 1,
        scheduled.hour,
        scheduled.minute,
      );
    }
    return scheduled;
  }

  /// Schedules or cancels the reminder for one task.
  static Future<void> syncTaskStart(TaskItem task) async {
    _cachedTasks[task.id] = task;
    if (!_canUseNotifications) return;

    final id = notificationIdForTask(task.id);
    final prefs = await SharedPreferences.getInstance();
    final fingerprint =
        '${task.title}|${task.startTime?.toIso8601String()}|${task.endTime?.toIso8601String()}|${task.effectiveDurationMinutes}|${task.isCompleted}|${task.isDeleted}|$_languageCode';
    if (_scheduledFingerprints[id] == fingerprint) return;
    await _plugin.cancel(id);
    if (prefs.getBool('notificationsEnabled') == false ||
        !hasSchedulablePeriod(task)) {
      _scheduledFingerprints.remove(id);
      return;
    }

    final scheduled = nextScheduledStart(task.startTime!);

    final androidDetails = AndroidNotificationDetails(
      _taskChannelId,
      _tr('Начало задачи', 'Task starts'),
      channelDescription: _tr(
        'Напоминания о начале периода задачи',
        'Reminders when a task period begins',
      ),
      importance: Importance.high,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction(
          _startTimerActionId,
          _tr('Запустить таймер', 'Start timer'),
          showsUserInterface: true,
        ),
      ],
    );
    final iOSDetails = DarwinNotificationDetails(
      categoryIdentifier:
          _languageCode == 'en' ? _taskCategoryIdEn : _taskCategoryIdRu,
    );

    final duration = task.effectiveDurationMinutes;
    final durationText =
        duration != null && duration > 0
            ? ' · ${_tr('Период', 'Period')} ${_formatDuration(duration)}'
            : '';
    final body =
        '${task.title}$durationText · ${_tr('Запустить таймер?', 'Start timer?')}';
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
    );
    try {
      await _plugin.zonedSchedule(
        id,
        _tr('Начало задачи', 'Task starts'),
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: taskPayloadForId(task.id),
      );
      _scheduledFingerprints[id] = fingerprint;
    } on Object {
      // Exact alarms may be unavailable on Android 12+. Preserve the reminder
      // with an inexact alarm rather than silently dropping it.
      await _plugin.zonedSchedule(
        id,
        _tr('Начало задачи', 'Task starts'),
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: taskPayloadForId(task.id),
      );
      _scheduledFingerprints[id] = fingerprint;
    }
  }

  static final Map<String, TaskItem> _cachedTasks = <String, TaskItem>{};

  static bool get _canUseNotifications =>
      !kIsWeb && _initialized && (Platform.isAndroid || Platform.isIOS);

  /// Keeps scheduled reminders in sync after notifications are re-enabled.
  static Future<void> rescheduleCachedTasks() async {
    if (!_canUseNotifications) return;
    _scheduledFingerprints.clear();
    for (final task in _cachedTasks.values) {
      await syncTaskStart(task);
    }
  }

  static String _formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
  }

  /// Cancels a task reminder without affecting the test notification or other
  /// task reminders.
  static Future<void> cancelTaskStart(String taskId) async {
    final id = notificationIdForTask(taskId);
    _cachedTasks.remove(taskId);
    _scheduledFingerprints.remove(id);
    if (!_canUseNotifications) return;
    await _plugin.cancel(id);
  }

  /// Cancels all active notifications.
  static Future<void> cancelAll() async {
    _scheduledFingerprints.clear();
    if (kIsWeb || !_initialized) return;
    await _plugin.cancelAll();
  }

  /// Returns and clears a timer-start request stored by a background callback.
  static Future<String?> consumePendingTimerStart() async {
    final prefs = await SharedPreferences.getInstance();
    final taskId = prefs.getString(_pendingTimerTaskKey);
    if (taskId != null) await prefs.remove(_pendingTimerTaskKey);
    return taskId;
  }

  static Future<void> handleBackgroundResponse(
    NotificationResponse response,
  ) async {
    await _handleNotificationResponse(response);
  }

  static Future<void> _handleNotificationResponse(
    NotificationResponse response,
  ) async {
    if (response.actionId != _startTimerActionId) return;
    final taskId = _taskIdFromPayload(response.payload);
    if (taskId == null) return;
    final callback = onStartTimerRequested;
    if (callback != null) {
      await callback(taskId);
    } else {
      await _storePendingTimerStart(taskId);
    }
  }

  static String? _taskIdFromPayload(String? payload) {
    if (payload == null || !payload.startsWith(_taskPayloadPrefix)) return null;
    final taskId = payload.substring(_taskPayloadPrefix.length);
    return taskId.isEmpty ? null : taskId;
  }

  static Future<void> _storePendingTimerStart(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingTimerTaskKey, taskId);
  }
}

/// Top-level entry point required by flutter_local_notifications for background
/// action callbacks in release/AOT builds.
@pragma('vm:entry-point')
void notificationBackgroundResponseHandler(NotificationResponse response) {
  unawaited(NotificationService.handleBackgroundResponse(response));
}
