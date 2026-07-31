import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
    if (error != null) {
      buffer.write('\nERROR: $error');
    }
    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }
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

/// Simple logging service.
///
/// Reads token and chat id from compile-time environment:
///   --dart-define=TELEGRAM_BOT_TOKEN=... --dart-define=TELEGRAM_CHAT_ID=...
///
/// When no token is configured, Telegram sending is skipped and logs are only
/// printed to the console and buffered.
class LoggerService {
  LoggerService._() {
    registerSecret(_token);
    registerSecret(_chatId);
  }

  static final LoggerService instance = LoggerService._();

  static const String _token = String.fromEnvironment('TELEGRAM_BOT_TOKEN');
  static const String _chatId = String.fromEnvironment('TELEGRAM_CHAT_ID');

  final _buffer = <LogEntry>[];
  final _redactedSecrets = <String>{};
  static const _redactionMarker = '[REDACTED]';
  final _maxBufferSize = 500;

  /// Whether Telegram integration is active.
  bool get telegramEnabled => _token.isNotEmpty && _chatId.isNotEmpty;

  /// All buffered entries (oldest first).
  List<LogEntry> get logs => List.unmodifiable(_buffer);

  /// Registers a secret for eager redaction in future log entries.
  ///
  /// Previously registered values are intentionally retained so a rotated
  /// secret cannot leak from a later asynchronous error.
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

  /// Replaces registered non-empty secrets in arbitrary diagnostic text.
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
      redacted = redacted.replaceAll(secret, _redactionMarker);
    }
    return redacted;
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

  /// Sends the current log buffer to Telegram.
  ///
  /// If [clear] is true, the buffer is cleared after a successful send.
  Future<bool> sendToTelegram({bool clear = true}) async {
    if (!telegramEnabled) {
      return false;
    }

    if (_buffer.isEmpty) {
      return true;
    }

    try {
      final text = _buffer.map((e) => e.toString()).join('\n---\n');
      final truncated =
          text.length > 4000 ? '${text.substring(0, 4000)}...' : text;

      final uri = Uri.parse('https://api.telegram.org/bot$_token/sendMessage');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'chat_id': _chatId, 'text': _escapeHtml(truncated)}),
      );

      if (response.statusCode == 200 && clear) {
        _buffer.clear();
      }
      return response.statusCode == 200;
    } on Exception catch (error, stackTrace) {
      log(
        LogLevel.error,
        'Failed to send logs to Telegram',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Reports an unhandled error/fatal condition to Telegram immediately.
  Future<bool> reportError(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    final entry = LogEntry(
      timestamp: DateTime.now().toUtc(),
      level: LogLevel.fatal,
      message: _redact(message),
      error: error == null ? null : _redact(error.toString()),
      stackTrace: stackTrace == null ? null : _redact(stackTrace.toString()),
    );
    _buffer.add(entry);
    while (_buffer.length > _maxBufferSize) {
      _buffer.removeAt(0);
    }

    if (!telegramEnabled) {
      return false;
    }

    try {
      final text = entry.toString();
      final uri = Uri.parse('https://api.telegram.org/bot$_token/sendMessage');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': _chatId,
          'text': _escapeHtml(
            text.length > 4000 ? text.substring(0, 4000) : text,
          ),
        }),
      );
      return response.statusCode == 200;
    } on Exception catch (error, stackTrace) {
      log(
        LogLevel.error,
        'Failed to report error to Telegram',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  void clearBuffer() => _buffer.clear();

  /// Wires the logger to report unhandled framework errors to Telegram.
  static void listenToFlutterErrors() {
    FlutterError.onError = (details) {
      final logger = LoggerService.instance;
      logger.reportError(
        details.exceptionAsString(),
        error: details.exception,
        stackTrace: details.stack,
      );
      FlutterError.presentError(details);
    };
  }

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}
