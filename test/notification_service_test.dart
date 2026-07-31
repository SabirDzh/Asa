import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:asa/core/notification_service.dart';

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Moscow'));
  });

  group('NotificationService scheduling helpers', () {
    test('notification ID is stable and positive', () {
      final first = NotificationService.notificationIdForTask('task-1');
      final second = NotificationService.notificationIdForTask('task-1');
      final other = NotificationService.notificationIdForTask('task-2');

      expect(first, greaterThan(0));
      expect(second, first);
      expect(other, isNot(first));
    });

    test('keeps a future start time on the same date', () {
      final now = DateTime(2026, 7, 31, 9, 0);
      final scheduled = NotificationService.nextScheduledStart(
        DateTime(2026, 7, 31, 10, 30),
        now: now,
      );

      expect(scheduled.year, 2026);
      expect(scheduled.month, 7);
      expect(scheduled.day, 31);
      expect(scheduled.hour, 10);
      expect(scheduled.minute, 30);
    });

    test('moves a passed start time to the next day', () {
      final now = DateTime(2026, 7, 31, 18, 0);
      final scheduled = NotificationService.nextScheduledStart(
        DateTime(2026, 7, 31, 10, 30),
        now: now,
      );

      expect(scheduled.year, 2026);
      expect(scheduled.month, 8);
      expect(scheduled.day, 1);
      expect(scheduled.hour, 10);
      expect(scheduled.minute, 30);
    });
  });
}
