import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:asa/core/calendar_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.builttoroam.com/device_calendar');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var retrieveCalls = 0;
  var createCalls = 0;
  var alwaysEmpty = false;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CalendarService.calendarRetryDelay = Duration.zero;
    CalendarService.calendarFallbackAttempted = false;
    CalendarService.calendarPlatformAndroidOverride = true;
    CalendarService.requestPermissionOverride = null;
    CalendarService.openAppSettingsOverride = null;
    retrieveCalls = 0;
    createCalls = 0;
    alwaysEmpty = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'hasPermissions':
          return false;
        case 'requestPermissions':
          return true;
        case 'retrieveCalendars':
          retrieveCalls++;
          if (alwaysEmpty) return jsonEncode(<Map<String, Object?>>[]);
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
        case 'createCalendar':
          createCalls++;
          return 'asa-calendar';
        default:
          return null;
      }
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    CalendarService.calendarRetryDelay = const Duration(milliseconds: 250);
    CalendarService.calendarFallbackAttempted = false;
    CalendarService.calendarPlatformAndroidOverride = null;
    CalendarService.requestPermissionOverride = null;
    CalendarService.openAppSettingsOverride = null;
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

  test('creates a local fallback calendar when Android exposes none', () async {
    alwaysEmpty = true;
    Map<Object?, Object?>? createArguments;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'createCalendar') {
        createCalls++;
        createArguments = call.arguments as Map<Object?, Object?>;
        return 'asa-calendar';
      }
      if (call.method == 'hasPermissions') return false;
      if (call.method == 'requestPermissions') return true;
      if (call.method == 'retrieveCalendars') {
        retrieveCalls++;
        return jsonEncode(<Map<String, Object?>>[]);
      }
      return null;
    });

    final calendars = await CalendarService.getCalendars();

    expect(calendars, isEmpty);
    expect(createCalls, 1);
    expect(createArguments?['calendarName'], 'ASA');
    expect(createArguments?['localAccountName'], 'ASA');
    expect(CalendarService.calendarFallbackAttempted, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('asa_calendar_fallback_id'), 'asa-calendar');
  });

  test('does not repeatedly create fallback calendars', () async {
    alwaysEmpty = true;

    await CalendarService.getCalendars();
    await CalendarService.getCalendars();

    expect(createCalls, 1);
  });

  test('does not recreate fallback after app restart', () async {
    alwaysEmpty = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('asa_calendar_fallback_id', 'asa-calendar');

    await CalendarService.getCalendars();

    expect(createCalls, 0);
  });

  test('does not persist an invalid fallback result', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'hasPermissions') return false;
      if (call.method == 'requestPermissions') return true;
      if (call.method == 'retrieveCalendars') {
        retrieveCalls++;
        return jsonEncode(<Map<String, Object?>>[]);
      }
      if (call.method == 'createCalendar') {
        createCalls++;
        return null;
      }
      return null;
    });

    await CalendarService.getCalendars();

    expect(createCalls, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('asa_calendar_fallback_id'), isNull);
    expect(CalendarService.calendarFallbackAttempted, isFalse);
  });

  test('uses the injected permission result and settings action', () async {
    var settingsOpened = false;
    CalendarService.requestPermissionOverride = () async => false;
    CalendarService.openAppSettingsOverride = () async {
      settingsOpened = true;
    };

    expect(await CalendarService.requestPermission(), isFalse);
    await CalendarService.openAppSettings();
    expect(settingsOpened, isTrue);
  });

  test('suppresses fallback outside Android', () async {
    CalendarService.calendarPlatformAndroidOverride = false;
    alwaysEmpty = true;

    await CalendarService.getCalendars();

    expect(createCalls, 0);
  });
}
