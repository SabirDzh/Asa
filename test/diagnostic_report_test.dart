import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:asa/core/logger_service.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.response);

  final http.Response response;
  Uri? uri;
  String? body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    uri = request.url;
    body = await request.finalize().bytesToString();
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LoggerService logger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    logger = LoggerService.instance;
    logger.clearBuffer();
    LoggerService.diagnosticsEndpointOverride = null;
    LoggerService.reportClientOverride = null;
    LoggerService.installationIdProviderOverride = null;
    LoggerService.deviceNameProviderOverride = null;
  });

  tearDown(() {
    LoggerService.diagnosticsEndpointOverride = null;
    LoggerService.reportClientOverride = null;
    LoggerService.installationIdProviderOverride = null;
    LoggerService.deviceNameProviderOverride = null;
  });

  test('redacts secrets and common sensitive values while preserving keys', () {
    final output = LoggerService.redactSensitive(
      'secret=1234 token=abc email=test@example.com ip=192.168.1.4 '
      'url=https://example.com/path?token=abc path=/data/user/0/com.example/file',
      const ['1234', 'abc'],
    );

    expect(output, contains('secret=[REDACTED]'));
    expect(output, contains('token=[REDACTED]'));
    expect(output, contains('[EMAIL_REDACTED]'));
    expect(output, contains('[IP_REDACTED]'));
    expect(output, contains('[URL_REDACTED]'));
    expect(output, contains('[PATH_REDACTED]'));
    expect(output, isNot(contains('test@example.com')));
  });

  test('does not send when endpoint is missing', () async {
    logger.i('failure');

    final result = await logger.sendDiagnosticReport();

    expect(result.success, isFalse);
    expect(result.error, 'endpoint_not_configured');
    expect(logger.logs, hasLength(1));
  });

  test('sends safe payload and clears buffer only after 201', () async {
    final client = _FakeClient(http.Response('{"reportId":"abc123"}', 201));
    LoggerService.diagnosticsEndpointOverride =
        'https://diagnostics.example/api/reports';
    LoggerService.reportClientOverride = client;
    LoggerService.installationIdProviderOverride = () async => 'install-id-123';
    LoggerService.deviceNameProviderOverride = () async => 'Pixel 9';
    logger.e(
      'request failed secret=do-not-send email=person@example.com',
      error: Exception('/data/user/0/com.example.secret/file'),
    );

    final result = await logger.sendDiagnosticReport();

    expect(result.success, isTrue);
    expect(result.reportId, 'abc123');
    expect(logger.logs, isEmpty);
    expect(client.uri.toString(), 'https://diagnostics.example/api/reports');
    final payload = jsonDecode(client.body!) as Map<String, dynamic>;
    expect(payload['installationId'], 'install-id-123');
    expect(payload['deviceName'], 'Pixel 9');
    final logs = (payload['logs'] as List).single as String;
    expect(logs, contains('secret=[REDACTED]'));
    expect(logs, contains('[EMAIL_REDACTED]'));
    expect(logs, isNot(contains('do-not-send')));
    expect(logs, isNot(contains('person@example.com')));
    expect(logs, isNot(contains('/data/user/0')));
  });

  test('captures reportError without automatic network delivery', () async {
    final sent = await logger.reportError('fatal failure');
    expect(sent, isFalse);
    expect(logger.logs, hasLength(1));
  });

  test('keeps buffer after server failure', () async {
    LoggerService.diagnosticsEndpointOverride =
        'https://diagnostics.example/api/reports';
    LoggerService.reportClientOverride = _FakeClient(http.Response('no', 503));
    logger.w('temporary failure');

    final result = await logger.sendDiagnosticReport();

    expect(result.success, isFalse);
    expect(result.error, 'server_rejected');
    expect(logger.logs, hasLength(1));
  });
}
