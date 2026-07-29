import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/timezone.dart' as tz;

/// Wraps the native Android Calendar Provider (and iOS EventKit) via the
/// `device_calendar` package.
class CalendarService {
  static final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();

  /// Requests calendar read/write permissions. Returns true if granted.
  static Future<bool> requestPermission() async {
    final has = await _plugin.hasPermissions();
    if (has.isSuccess && (has.data ?? false)) return true;

    final requested = await _plugin.requestPermissions();
    return requested.isSuccess && (requested.data ?? false);
  }

  /// Returns writable calendars available on the device.
  static Future<List<Calendar>> getCalendars() async {
    if (!await requestPermission()) return [];
    final result = await _plugin.retrieveCalendars();
    if (!result.isSuccess || result.data == null) return [];
    return result.data!.where((c) => !(c.isReadOnly ?? true)).toList();
  }

  /// Creates or updates a calendar event linked to [taskId].
  /// If [eventId] is provided, the existing event is updated.
  /// Returns the event id, or null on failure.
  static Future<String?> createOrUpdateEvent({
    required String calendarId,
    required String title,
    required DateTime date,
    String? eventId,
    String? description,
  }) async {
    if (!await requestPermission()) return null;

    final start = tz.TZDateTime.from(date, tz.local);
    final end = start.add(const Duration(hours: 1));

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
