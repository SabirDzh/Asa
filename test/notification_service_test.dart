import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:asa/core/notification_service.dart';
import 'package:asa/features/tasks/models/task_model.dart';

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

    test('moves an equal start time to the next day', () {
      final now = DateTime(2026, 7, 31, 22, 1);
      final scheduled = NotificationService.nextScheduledStart(
        DateTime(2026, 7, 31, 22, 1),
        now: now,
      );

      expect(scheduled.year, 2026);
      expect(scheduled.month, 8);
      expect(scheduled.day, 1);
      expect(scheduled.hour, 22);
      expect(scheduled.minute, 1);
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

    test('exposes a stable timer action and task payload contract', () {
      expect(NotificationService.startTimerActionId, 'start_timer');
      expect(
        NotificationService.taskPayloadForId('task-42'),
        'asa_task:task-42',
      );
    });

    test('rejects incomplete, zero-length, completed, and deleted periods', () {
      expect(
        NotificationService.hasSchedulablePeriod(
          TaskItem(
            id: 'incomplete',
            title: 'Incomplete',
            startTime: DateTime(2026, 7, 31, 10),
          ),
        ),
        isFalse,
      );
      expect(
        NotificationService.hasSchedulablePeriod(
          TaskItem(
            id: 'zero',
            title: 'Zero',
            startTime: DateTime(2026, 7, 31, 10),
            endTime: DateTime(2026, 7, 31, 10),
          ),
        ),
        isFalse,
      );
      expect(
        NotificationService.hasSchedulablePeriod(
          TaskItem(
            id: 'completed',
            title: 'Completed',
            isCompleted: true,
            startTime: DateTime(2026, 7, 31, 10),
            endTime: DateTime(2026, 7, 31, 11),
          ),
        ),
        isFalse,
      );
      expect(
        NotificationService.hasSchedulablePeriod(
          TaskItem(
            id: 'deleted',
            title: 'Deleted',
            isDeleted: true,
            startTime: DateTime(2026, 7, 31, 10),
            endTime: DateTime(2026, 7, 31, 11),
          ),
        ),
        isFalse,
      );
    });

    test('accepts daytime and overnight periods', () {
      expect(
        NotificationService.hasSchedulablePeriod(
          TaskItem(
            id: 'day',
            title: 'Day',
            startTime: DateTime(2026, 7, 31, 10),
            endTime: DateTime(2026, 7, 31, 11),
          ),
        ),
        isTrue,
      );
      expect(
        NotificationService.hasSchedulablePeriod(
          TaskItem(
            id: 'overnight',
            title: 'Overnight',
            startTime: DateTime(2026, 7, 31, 23),
            endTime: DateTime(2026, 7, 31, 1),
          ),
        ),
        isTrue,
      );
    });
  });
}
