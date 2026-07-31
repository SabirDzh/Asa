import 'package:flutter_test/flutter_test.dart';
import 'package:asa/core/logger_service.dart';

void main() {
  setUp(() {
    LoggerService.instance.clearBuffer();
  });

  test(
    'redactSensitive replaces registered secrets and keeps short values',
    () {
      expect(
        LoggerService.redactSensitive(
          'peer rejected secret=1234 and token=ab',
          ['1234', 'ab'],
        ),
        'peer rejected secret=[REDACTED] and token=[REDACTED]',
      );
    },
  );

  test('eagerly redacts message, error, and stack trace before buffering', () {
    final logger = LoggerService.instance;
    logger.registerSecret('sync-pin-1234');

    logger.e(
      'sync-pin-1234 rejected',
      error: Exception('failed with sync-pin-1234'),
      stackTrace: StackTrace.fromString('at sync-pin-1234 boundary'),
    );

    final entry = logger.logs.last;
    final output = entry.toString();
    expect(output, isNot(contains('sync-pin-1234')));
    expect(output, contains('[REDACTED]'));
  });

  test('redacts entries that were buffered before registration', () {
    final logger = LoggerService.instance;
    logger.i('before registration: pending-secret');
    logger.registerSecret('pending-secret');

    expect(logger.logs.last.toString(), isNot(contains('pending-secret')));
    expect(logger.logs.last.toString(), contains('[REDACTED]'));
  });

  test('retains old registered secrets after rotation', () {
    final logger = LoggerService.instance;
    logger.registerSecret('old-secret');
    logger.registerSecret('new-secret');

    logger.i('old-secret replaced by new-secret');

    final output = logger.logs.last.toString();
    expect(output, contains('[I]'));
    expect(output, contains('[REDACTED]'));
    expect(output, isNot(contains('old-secret')));
    expect(output, isNot(contains('new-secret')));
  });

  test('bounds reportError entries in the same way as normal logs', () async {
    final logger = LoggerService.instance;
    for (var i = 0; i < 505; i++) {
      await logger.reportError('error-$i');
    }

    expect(logger.logs, hasLength(500));
    expect(logger.logs.first.toString(), contains('error-5'));
    expect(logger.logs.last.toString(), contains('error-504'));
  });
}
