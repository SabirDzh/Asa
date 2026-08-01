import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;

/// Wraps the native Android Calendar Provider (and iOS EventKit) via the
/// `device_calendar` package.
class CalendarService {
  static final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();

  /// Gives native calendar providers a moment to expose calendars after the
  /// user grants access for the first time. Tests can set this to zero.
  @visibleForTesting
  static Duration calendarRetryDelay = const Duration(milliseconds: 250);

  /// Requests calendar read/write permissions. Returns true if granted.
  static Future<bool> requestPermission() async {
    final has = await _plugin.hasPermissions();
    if (has.isSuccess && (has.data ?? false)) return true;

    final requested = await _plugin.requestPermissions();
    return requested.isSuccess && (requested.data ?? false);
  }

  /// Returns calendars that are not explicitly marked read-only.
  ///
  /// On the first access, Android/iOS can briefly return an empty collection
  /// while the native calendar store is being initialized. Retry a few times
  /// so granting permission does not immediately look like a missing calendar.
  static Future<List<Calendar>> getCalendars() async {
    if (!await requestPermission()) return [];

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

  /// Deletes the calendar event with [eventId] from [calendarId].
  static Future<void> deleteEvent(String calendarId, String eventId) async {
    if (!await requestPermission()) return;
    await _plugin.deleteEvent(calendarId, eventId);
  }
}
