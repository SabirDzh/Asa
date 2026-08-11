import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'device_info.dart';

/// Severity level for log entries.
enum LogLevel { verbose, debug, info, warning, error, fatal }

/// A single buffered log entry.
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? error;
  final String? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write(
      '${_levelLabel(level)} ${timestamp.toIso8601String()} $message',
    );
    if (error != null) buffer.write('\nERROR: $error');
    if (stackTrace != null) buffer.write('\n$stackTrace');
    return buffer.toString();
  }

  static String _levelLabel(LogLevel level) {
    return switch (level) {
      LogLevel.verbose => '[V]',
      LogLevel.debug => '[D]',
      LogLevel.info => '[I]',
      LogLevel.warning => '[W]',
      LogLevel.error => '[E]',
      LogLevel.fatal => '[F]',
    };
  }
}

/// Result of an explicit user-initiated diagnostic report submission.
class DiagnosticReportResult {
  const DiagnosticReportResult({
    required this.success,
    this.reportId,
    this.error,
  });

  const DiagnosticReportResult.success(String id)
    : this(success: true, reportId: id);

  const DiagnosticReportResult.failure(String reason)
    : this(success: false, error: reason);

  final bool success;
  final String? reportId;
  final String? error;
}

/// Bounded local logger with explicit, consent-driven diagnostic reporting.
///
/// Release scripts read the public HTTPS endpoint from the ignored,
/// owner-only `config/private.env` file and pass it at compile time. No manual
/// endpoint argument is needed. No Telegram, database, or admin secret is
/// ever embedded in the app. Reports contain the current bounded log buffer
/// and safe device metadata; tasks, attachments, and backups are not included.
class LoggerService {
  LoggerService._() {
    registerSecret(_diagnosticsEndpoint);
  }

  static final LoggerService instance = LoggerService._();
  static const String _diagnosticsEndpoint = String.fromEnvironment(
    'DIAGNOSTICS_ENDPOINT',
    defaultValue: '',
  );
  static const String _appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.1.3',
  );
  static const String _installationIdKey = 'diagnostic_installation_id';
  static const int _maxBufferSize = 500;
  static const int _maxReportBytes = 256 * 1024;
  static const int _maxEntryCharacters = 8 * 1024;

  @visibleForTesting
  static String? diagnosticsEndpointOverride;

  @visibleForTesting
  static http.Client? reportClientOverride;

  @visibleForTesting
  static Future<String> Function()? installationIdProviderOverride;

  @visibleForTesting
  static Future<String> Function()? deviceNameProviderOverride;

  final _buffer = <LogEntry>[];
  final _redactedSecrets = <String>{};

  /// All buffered entries (oldest first).
  List<LogEntry> get logs => List.unmodifiable(_buffer);

  /// Whether an HTTPS diagnostic endpoint is configured.
  bool get diagnosticsEnabled => _validEndpoint != null;

  Uri? get _validEndpoint {
    final raw = (diagnosticsEndpointOverride ?? _diagnosticsEndpoint).trim();
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }

  /// Registers a secret for eager redaction in future log entries.
  /// Previously registered values remain redacted after rotation.
  void registerSecret(String? secret) {
    final normalized = secret?.trim();
    if (normalized == null || normalized.isEmpty) return;
    _redactedSecrets.add(normalized);
    for (var i = 0; i < _buffer.length; i++) {
      final entry = _buffer[i];
      _buffer[i] = LogEntry(
        timestamp: entry.timestamp,
        level: entry.level,
        message: _redact(entry.message),
        error: entry.error == null ? null : _redact(entry.error!),
        stackTrace:
            entry.stackTrace == null ? null : _redact(entry.stackTrace!),
      );
    }
  }

  /// Replaces registered secrets and common sensitive diagnostic patterns.
  static String redactSensitive(String message, Iterable<String> secrets) {
    final candidates =
        secrets
            .map((secret) => secret.trim())
            .where((secret) => secret.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    var redacted = message;
    for (final secret in candidates) {
      redacted = redacted.replaceAll(secret, '[REDACTED]');
    }
    return _sanitizeDiagnosticText(redacted);
  }

  static String _sanitizeDiagnosticText(String value) {
    var sanitized = value.replaceAllMapped(
      RegExp(
        r'((?:bearer\s+|token|secret|password|api[_-]?key|chat[_-]?id)\s*[:=]\s*)[^\s,;]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}[REDACTED]',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'https?://[^\s]+'),
      '[URL_REDACTED]',
    );
    sanitized = sanitized.replaceAll(
      RegExp(
        r'\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b',
      ),
      '[JWT_REDACTED]',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'/bot[A-Za-z0-9:_-]{20,}'),
      '/bot[REDACTED]',
    );
    sanitized = sanitized.replaceAll(
      RegExp(
        r'(/Users/|/data/user/|/storage/emulated/|[A-Z]:\\)[^\s]+',
        caseSensitive: false,
      ),
      '[PATH_REDACTED]',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'),
      '[IP_REDACTED]',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b'),
      '[EMAIL_REDACTED]',
    );
    return sanitized;
  }

  String _redact(String value) => redactSensitive(value, _redactedSecrets);

  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now().toUtc(),
      level: level,
      message: _redact(message),
      error: error == null ? null : _redact(error.toString()),
      stackTrace: stackTrace == null ? null : _redact(stackTrace.toString()),
    );

    _buffer.add(entry);
    while (_buffer.length > _maxBufferSize) {
      _buffer.removeAt(0);
    }

    if (kDebugMode) {
      // ignore: avoid_print
      print(entry.toString());
    }
  }

  void v(String message) => log(LogLevel.verbose, message);
  void d(String message) => log(LogLevel.debug, message);
  void i(String message) => log(LogLevel.info, message);
  void w(String message, {Object? error, StackTrace? stackTrace}) =>
      log(LogLevel.warning, message, error: error, stackTrace: stackTrace);
  void e(String message, {Object? error, StackTrace? stackTrace}) =>
      log(LogLevel.error, message, error: error, stackTrace: stackTrace);
  void f(String message, {Object? error, StackTrace? stackTrace}) =>
      log(LogLevel.fatal, message, error: error, stackTrace: stackTrace);

  /// Captures an unhandled error without sending it automatically.
  ///
  /// Kept as a compatibility wrapper for existing integrations. Network
  /// delivery is intentionally available only through [sendDiagnosticReport].
  Future<bool> reportError(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    log(LogLevel.fatal, message, error: error, stackTrace: stackTrace);
    return false;
  }

  /// Sends the current bounded log buffer after the user explicitly confirms.
  /// The local buffer is cleared only after a successful server response.
  Future<DiagnosticReportResult> sendDiagnosticReport() async {
    final endpoint = _validEndpoint;
    if (endpoint == null) {
      return const DiagnosticReportResult.failure('endpoint_not_configured');
    }
    if (_buffer.isEmpty) {
      return const DiagnosticReportResult.failure('logs_empty');
    }

    try {
      final installationId = await _installationId();
      final deviceName =
          await (deviceNameProviderOverride ?? getDiagnosticDeviceName)();
      final logs = _buffer
          .map((entry) {
            final text = _sanitizeDiagnosticText(entry.toString());
            return text.length > _maxEntryCharacters
                ? '${text.substring(0, _maxEntryCharacters)}\n[ENTRY_TRUNCATED]'
                : text;
          })
          .toList(growable: false);
      final payload = <String, Object?>{
        'installationId': installationId,
        'appVersion': _appVersion,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'deviceName': _sanitizeDiagnosticText(deviceName),
        'sentAt': DateTime.now().toUtc().toIso8601String(),
        'logs': logs,
      };
      final body = jsonEncode(payload);
      if (utf8.encode(body).length > _maxReportBytes) {
        return const DiagnosticReportResult.failure('report_too_large');
      }

      final client = reportClientOverride ?? http.Client();
      late final http.Response response;
      try {
        response = await client
            .post(
              endpoint,
              headers: {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
                'User-Agent': 'ASA-Diagnostics/1',
              },
              body: body,
            )
            .timeout(const Duration(seconds: 10));
      } finally {
        if (reportClientOverride == null) client.close();
      }
      if (response.statusCode != 201) {
        return const DiagnosticReportResult.failure('server_rejected');
      }

      String? reportId;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['reportId'] is String) {
          reportId = decoded['reportId'] as String;
        }
      } on Object {
        // A successful response without a parseable ID is still accepted.
      }
      _buffer.clear();
      return DiagnosticReportResult.success(reportId ?? 'received');
    } on Object catch (error, stackTrace) {
      // Do not recursively submit this network failure. Keep the original
      // buffer so the user can retry after connectivity is restored.
      log(
        LogLevel.error,
        'Diagnostic report submission failed',
        error: error,
        stackTrace: stackTrace,
      );
      return const DiagnosticReportResult.failure('network_error');
    }
  }

  Future<String> _installationId() async {
    final override = installationIdProviderOverride;
    if (override != null) return override();
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_installationIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await prefs.setString(_installationIdKey, id);
    return id;
  }

  void clearBuffer() => _buffer.clear();

  /// Captures unhandled Flutter errors locally for the next explicit report.
  static void listenToFlutterErrors() {
    FlutterError.onError = (details) {
      final logger = LoggerService.instance;
      logger.log(
        LogLevel.fatal,
        details.exceptionAsString(),
        error: details.exception,
        stackTrace: details.stack,
      );
      FlutterError.presentError(details);
    };
  }
}
