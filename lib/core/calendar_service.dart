import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'device_permissions.dart';

/// Signals that a calendar event would overlap an existing event.
class CalendarEventConflictException implements Exception {
  final int conflictingEventCount;

  const CalendarEventConflictException({this.conflictingEventCount = 1});

  @override
  String toString() =>
      'CalendarEventConflictException($conflictingEventCount conflicts)';
}

/// Signals that the native calendar provider did not persist an event.
class CalendarEventUpdateException implements Exception {
  const CalendarEventUpdateException();

  @override
  String toString() => 'CalendarEventUpdateException';
}

/// Wraps the native Android Calendar Provider (and iOS EventKit) via the
/// `device_calendar` package.
class CalendarService {
  static final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();

  /// Gives native calendar providers a moment to expose calendars after the
  /// user grants access for the first time. Tests can set this to zero.
  @visibleForTesting
  static Duration calendarRetryDelay = const Duration(milliseconds: 250);

  /// Prevents repeated creation attempts when a ROM hides newly created
  /// calendars from the provider. Tests can reset this between cases.
  @visibleForTesting
  static bool calendarFallbackAttempted = false;

  @visibleForTesting
  static bool? calendarPlatformAndroidOverride;

  @visibleForTesting
  static Future<bool> Function()? requestPermissionOverride;

  @visibleForTesting
  static Future<void> Function()? openAppSettingsOverride;

  @visibleForTesting
  static Future<String?> Function({
    required String calendarId,
    required String title,
    required DateTime date,
    DateTime? endTime,
    String? eventId,
    String? description,
  })?
  createOrUpdateEventOverride;

  @visibleForTesting
  static Future<bool> Function(String calendarId, String eventId)?
  deleteEventOverride;

  @visibleForTesting
  static Future<bool> Function({
    required String calendarId,
    required DateTime start,
    required DateTime end,
    String? excludeEventId,
  })?
  hasOverlappingEventsOverride;

  static Future<void>? _fallbackCreationFuture;
  static const _fallbackCalendarIdKey = 'asa_calendar_fallback_id';

  /// Requests calendar read/write permissions. Returns true if granted.
  static Future<bool> requestPermission() async {
    final override = requestPermissionOverride;
    if (override != null) return override();

    final has = await _plugin.hasPermissions();
    if (has.isSuccess && (has.data ?? false)) return true;

    final requested = await _plugin.requestPermissions();
    return requested.isSuccess && (requested.data ?? false);
  }

  /// Opens the app's system settings so the user can restore calendar access
  /// after a permanent denial.
  static Future<void> openAppSettings() async {
    final override = openAppSettingsOverride;
    if (override != null) {
      await override();
      return;
    }
    await DevicePermissions.openAppSettings();
  }

  /// Returns calendars that are not explicitly marked read-only.
  ///
  /// On the first access, Android/iOS can briefly return an empty collection
  /// while the native calendar store is being initialized. Retry a few times
  /// so granting permission does not immediately look like a missing calendar.
  ///
  /// Some Android ROMs, including HyperOS, can grant calendar permissions while
  /// exposing no writable account calendar to third-party apps. In that case,
  /// create a private local calendar owned by ASA and read the provider again.
  /// The fallback is deliberately performed only after the normal lookup fails;
  /// existing user calendars are never modified.
  static Future<List<Calendar>> getCalendars({
    bool permissionAlreadyGranted = false,
  }) async {
    if (!permissionAlreadyGranted && !await requestPermission()) return [];

    final calendars = await _retrieveWritableCalendars();
    final isAndroid =
        calendarPlatformAndroidOverride ??
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
    if (calendars.isNotEmpty || !isAndroid) return calendars;

    final prefs = await SharedPreferences.getInstance();
    if (calendarFallbackAttempted ||
        (prefs.getString(_fallbackCalendarIdKey)?.isNotEmpty ?? false)) {
      return calendars;
    }

    final inFlight = _fallbackCreationFuture;
    if (inFlight != null) {
      await inFlight;
      return _retrieveWritableCalendars();
    }

    final creation = _createFallbackCalendar(prefs);
    _fallbackCreationFuture = creation;
    try {
      await creation;
    } finally {
      if (identical(_fallbackCreationFuture, creation)) {
        _fallbackCreationFuture = null;
      }
    }

    return _retrieveWritableCalendars();
  }

  static Future<void> _createFallbackCalendar(SharedPreferences prefs) async {
    try {
      final created = await _plugin.createCalendar(
        'ASA',
        localAccountName: 'ASA',
      );
      final calendarId = created.data;
      if (!created.isSuccess || calendarId == null || calendarId.isEmpty) {
        return;
      }
      calendarFallbackAttempted = true;
      await prefs.setString(_fallbackCalendarIdKey, calendarId);
    } on Object {
      // A ROM may forbid local calendar creation even when permissions are
      // granted. Keep the caller's existing empty-calendar error in that case.
    }
  }

  static Future<List<Calendar>> _retrieveWritableCalendars() async {
    const maxAttempts = 3;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final result = await _plugin.retrieveCalendars();
      if (result.isSuccess && result.data != null) {
        final calendars =
            result.data!
                .where(
                  (calendar) =>
                      calendar.id?.isNotEmpty == true &&
                      calendar.isReadOnly != true,
                )
                .toList();
        if (calendars.isNotEmpty || attempt == maxAttempts - 1) {
          return calendars;
        }
      } else if (attempt == maxAttempts - 1) {
        return [];
      }

      await Future<void>.delayed(calendarRetryDelay);
    }

    return [];
  }

  /// Creates or updates a calendar event linked to [taskId].
  /// If [eventId] is provided, the existing event is updated.
  /// Returns the event id, or null on failure.
  static Future<String?> createOrUpdateEvent({
    required String calendarId,
    required String title,
    required DateTime date,
    DateTime? endTime,
    String? eventId,
    String? description,
  }) async {
    final override = createOrUpdateEventOverride;
    if (override != null) {
      return override(
        calendarId: calendarId,
        title: title,
        date: date,
        endTime: endTime,
        eventId: eventId,
        description: description,
      );
    }
    if (!await requestPermission()) return null;

    final start = tz.TZDateTime.from(date, tz.local);
    final end =
        endTime != null
            ? tz.TZDateTime.from(endTime, tz.local)
            : start.add(const Duration(hours: 1));

    final event = Event(
      calendarId,
      eventId: eventId,
      title: title,
      description: description,
      start: start,
      end: end,
    );

    final result = await _plugin.createOrUpdateEvent(event);
    return result?.data;
  }

  /// Returns whether an existing event in [calendarId] overlaps the proposed
  /// interval. The event identified by [excludeEventId] is ignored, which lets
  /// an update compare against other events without conflicting with itself.
  ///
  /// Calendar-provider read failures fail open: the caller may still create the
  /// event, because a transient provider failure must not make calendar linking
  /// impossible. The user-facing operation remains serialized by TaskProvider.
  static Future<bool> hasOverlappingEvents({
    required String calendarId,
    required DateTime start,
    required DateTime end,
    String? excludeEventId,
  }) async {
    final override = hasOverlappingEventsOverride;
    if (override != null) {
      return override(
        calendarId: calendarId,
        start: start,
        end: end,
        excludeEventId: excludeEventId,
      );
    }
    if (!end.isAfter(start) || !await requestPermission()) return false;

    try {
      final result = await _plugin.retrieveEvents(
        calendarId,
        RetrieveEventsParams(
          startDate: tz.TZDateTime.from(start, tz.local),
          endDate: tz.TZDateTime.from(end, tz.local),
        ),
      );
      if (!result.isSuccess || result.data == null) return false;
      return result.data!.any((event) {
        if (event.eventId == excludeEventId ||
            event.start == null ||
            event.end == null) {
          return false;
        }
        return intervalsOverlap(start, end, event.start!, event.end!);
      });
    } on Object {
      return false;
    }
  }

  /// Uses half-open intervals, so an event ending exactly when another starts
  /// is not considered a conflict.
  @visibleForTesting
  static bool intervalsOverlap(
    DateTime start,
    DateTime end,
    DateTime otherStart,
    DateTime otherEnd,
  ) {
    return start.isBefore(otherEnd) && otherStart.isBefore(end);
  }

  /// Deletes the calendar event with [eventId] from [calendarId]. Returns
  /// false when permission/provider access is unavailable so callers can queue
  /// a retry instead of silently losing the cleanup operation.
  static Future<bool> deleteEvent(String calendarId, String eventId) async {
    final override = deleteEventOverride;
    if (override != null) return override(calendarId, eventId);
    if (!await requestPermission()) return false;
    final result = await _plugin.deleteEvent(calendarId, eventId);
    return result.isSuccess;
  }
}
