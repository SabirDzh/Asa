import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asa/core/calendar_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.builttoroam.com/device_calendar');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var retrieveCalls = 0;
  setUp(() {
    CalendarService.calendarRetryDelay = Duration.zero;
    retrieveCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'hasPermissions':
          return false;
        case 'requestPermissions':
          return true;
        case 'retrieveCalendars':
          retrieveCalls++;
          if (retrieveCalls == 1) return jsonEncode(<Map<String, Object?>>[]);
          return jsonEncode([
            {
              'id': 'device-calendar',
              'name': 'Личный календарь',
              'isReadOnly': null,
            },
            {
              'id': 'read-only-calendar',
              'name': 'Праздники',
              'isReadOnly': true,
            },
            {'id': 'writable-calendar', 'name': 'Работа', 'isReadOnly': false},
            {'id': null, 'name': 'Без идентификатора', 'isReadOnly': false},
          ]);
        default:
          return null;
      }
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    CalendarService.calendarRetryDelay = const Duration(milliseconds: 250);
  });

  test('retries calendar retrieval after permission is granted', () async {
    final calendars = await CalendarService.getCalendars();

    expect(retrieveCalls, 2);
    expect(calendars.map((calendar) => calendar.id), [
      'device-calendar',
      'writable-calendar',
    ]);
  });

  test('does not return read-only or incomplete calendars', () async {
    retrieveCalls = 1;

    final calendars = await CalendarService.getCalendars();

    expect(calendars, hasLength(2));
    expect(calendars.every((calendar) => calendar.isReadOnly != true), true);
    expect(
      calendars.every((calendar) => calendar.id?.isNotEmpty == true),
      true,
    );
  });
}
