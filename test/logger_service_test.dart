import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:asa/core/logger_service.dart';

void main() {
  setUp(() {
    LoggerService.instance.clearBuffer();
    LoggerService.diagnosticsEndpointOverride = null;
    LoggerService.reportClientOverride = null;
    LoggerService.installationIdProviderOverride = null;
    LoggerService.deviceNameProviderOverride = null;
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

  group('sendDiagnosticReport', () {
    test('sends a report and clears the buffer on a 201 response', () async {
      LoggerService.diagnosticsEndpointOverride =
          'https://example.com/api/reports';
      LoggerService.installationIdProviderOverride = () async => 'inst-1';
      LoggerService.deviceNameProviderOverride = () async => 'Test Phone';
      late http.Request captured;
      LoggerService.reportClientOverride = MockClient((request) async {
        captured = request;
        return http.Response(
          '{"reportId":"report-123"}',
          201,
          headers: {'content-type': 'application/json'},
        );
      });
      final logger = LoggerService.instance;
      logger.i('hello');

      final result = await logger.sendDiagnosticReport();

      expect(result.success, isTrue);
      expect(result.reportId, 'report-123');
      expect(logger.logs, isEmpty);
      expect(captured.url.toString(), 'https://example.com/api/reports');
      expect(captured.headers['Content-Type'], 'application/json');
      final body = String.fromCharCodes(captured.bodyBytes);
      expect(body, contains('"installationId":"inst-1"'));
      expect(body, contains('"deviceName":"Test Phone"'));
      expect(body, contains('hello'));
    });

    test(
      'reports failure without clearing the buffer on a 4xx response',
      () async {
        LoggerService.diagnosticsEndpointOverride =
            'https://example.com/api/reports';
        LoggerService.installationIdProviderOverride = () async => 'inst-2';
        LoggerService.deviceNameProviderOverride = () async => 'Test Phone';
        LoggerService.reportClientOverride = MockClient(
          (_) async => http.Response('{"error":"bad"}', 400),
        );
        final logger = LoggerService.instance;
        logger.i('keep me');

        final result = await logger.sendDiagnosticReport();

        expect(result.success, isFalse);
        expect(result.error, 'server_rejected');
        expect(logger.logs, isNotEmpty);
      },
    );

    test('fails with a clear reason when no endpoint is configured', () async {
      final logger = LoggerService.instance;
      logger.i('unreachable');

      final result = await logger.sendDiagnosticReport();

      expect(result.success, isFalse);
      expect(result.error, 'endpoint_not_configured');
    });
  });
}
