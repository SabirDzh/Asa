import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../features/tasks/models/task_model.dart';
import '../features/tasks/providers/task_provider.dart';
import 'logger_service.dart';

/// Maximum allowed import file size (10 MB).
const _kMaxImportFileSize = 10 * 1024 * 1024;

/// Result of an export operation.
class ExportResult {
  final File? file;
  final String? error;
  final bool success;

  const ExportResult({this.file, this.error, required this.success});
}

/// Result of an import operation.
class ImportResult {
  final int tasksImported;
  final int foldersImported;
  final String? error;
  final bool cancelled;
  bool get success => error == null && !cancelled;

  const ImportResult({
    this.tasksImported = 0,
    this.foldersImported = 0,
    this.error,
    this.cancelled = false,
  });
}

/// Preview/metadata for a file the user is about to import.
class ImportPreview {
  final String fileName;
  final int fileSize;
  final bool isValid;
  final String? errorKey;
  final String? version;
  final DateTime? exportedAt;
  final int taskCount;
  final int folderCount;
  final AsaDataSnapshot? snapshot;
  final bool hasSecret;

  const ImportPreview({
    required this.fileName,
    required this.fileSize,
    required this.isValid,
    this.errorKey,
    this.version,
    this.exportedAt,
    this.taskCount = 0,
    this.folderCount = 0,
    this.snapshot,
    this.hasSecret = false,
  });

  String get fileSizeLabel {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Holds the portable data snapshot.
class AsaDataSnapshot {
  final String version;
  final int exportedAt;
  final List<Map<String, dynamic>> tasks;
  final List<Map<String, dynamic>> folders;

  AsaDataSnapshot({
    required this.version,
    required this.exportedAt,
    required this.tasks,
    required this.folders,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'exportedAt': exportedAt,
    'tasks': tasks,
    'folders': folders,
  };

  factory AsaDataSnapshot.fromJson(Map<String, dynamic> json) {
    return AsaDataSnapshot(
      version: json['version']?.toString() ?? '1.0.0',
      exportedAt: json['exportedAt'] is int ? json['exportedAt'] as int : 0,
      tasks: _readObjectList(json['tasks'], 'tasks'),
      folders: _readObjectList(json['folders'], 'folders'),
    );
  }

  static List<Map<String, dynamic>> _readObjectList(
    Object? value,
    String fieldName,
  ) {
    if (value == null) return [];
    if (value is! List) {
      throw FormatException('$fieldName must be a list');
    }

    return value.map((entry) {
      if (entry is! Map) {
        throw FormatException('$fieldName entries must be objects');
      }
      final object = <String, dynamic>{};
      for (final item in entry.entries) {
        if (item.key is! String) {
          throw FormatException('$fieldName object keys must be strings');
        }
        object[item.key as String] = item.value;
      }
      return object;
    }).toList();
  }
}

/// Wire-safe envelope for sync payloads.
class SyncEnvelope {
  /// Legacy plaintext secret used by pre-HMAC payloads.
  final String? secret;

  /// HMAC-SHA256 of [payload] for current payloads.
  final String? mac;
  final String payload;

  const SyncEnvelope({this.secret, this.mac, required this.payload});

  Map<String, dynamic> toJson() => {
    if (secret != null) 'secret': secret,
    if (mac != null) 'mac': mac,
    'payload': payload,
  };

  factory SyncEnvelope.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('payload')) {
      throw const FormatException('Envelope payload is required');
    }

    final payload = json['payload'];
    if (payload is! String || payload.isEmpty) {
      throw const FormatException(
        'Envelope payload must be a non-empty string',
      );
    }

    String? readOptionalString(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String) {
        throw FormatException('Envelope $key must be a string');
      }
      return value;
    }

    return SyncEnvelope(
      secret: readOptionalString('secret'),
      mac: readOptionalString('mac'),
      payload: payload,
    );
  }
}

/// Exports and imports app data as a portable JSON file.
class ExportImportService {
  static const String _version = '1.1.0';

  /// Builds a serializable snapshot from the current provider state.
  static AsaDataSnapshot buildSnapshot(TaskProvider provider) {
    final tasks = provider.tasks.map((t) => t.toJson()).toList();
    final folders =
        provider.folders
            .where((f) => !f.isSystemStreak)
            .map((f) => f.toJson())
            .toList();

    return AsaDataSnapshot(
      version: _version,
      exportedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
      tasks: tasks,
      folders: folders,
    );
  }

  /// Exports the current tasks/folders to a file and opens the share sheet.
  static Future<ExportResult> exportAndShare(TaskProvider provider) async {
    try {
      final snapshot = buildSnapshot(provider);
      final json = jsonEncode(snapshot.toJson());
      final file = await _writeToFile(json);

      final xFile = XFile(file.path);
      await Share.shareXFiles([xFile], subject: 'ASA backup');

      LoggerService.instance.i(
        'Exported ${snapshot.tasks.length} tasks, ${snapshot.folders.length} folders',
      );
      return ExportResult(file: file, success: true);
    } on Exception catch (error, stackTrace) {
      LoggerService.instance.e(
        'Export failed',
        error: error,
        stackTrace: stackTrace,
      );
      return ExportResult(error: error.toString(), success: false);
    }
  }

  /// Exports to a file without opening the share sheet. Returns the file path.
  static Future<ExportResult> exportToFile(TaskProvider provider) async {
    try {
      final snapshot = buildSnapshot(provider);
      final json = jsonEncode(snapshot.toJson());
      final file = await _writeToFile(json);
      LoggerService.instance.i('Exported backup to ${file.path}');
      return ExportResult(file: file, success: true);
    } on Exception catch (error, stackTrace) {
      LoggerService.instance.e(
        'Export failed',
        error: error,
        stackTrace: stackTrace,
      );
      return ExportResult(error: error.toString(), success: false);
    }
  }

  /// Picks a file for import and returns the selected [PlatformFile]
  /// (including its bytes) without importing anything yet.
  static Future<PlatformFile?> pickImportFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'asa'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null ||
        file.size > _kMaxImportFileSize ||
        bytes.length > _kMaxImportFileSize) {
      return null;
    }

    return file;
  }

  /// Picks a file and merges its data into the current provider.
  static Future<ImportResult> importFromFile(TaskProvider provider) async {
    try {
      final file = await pickImportFile();
      if (file == null) {
        return const ImportResult(cancelled: true);
      }

      return importFromBytes(provider, file.bytes!);
    } on Exception catch (error, stackTrace) {
      LoggerService.instance.e(
        'Import failed',
        error: error,
        stackTrace: stackTrace,
      );
      return const ImportResult(error: 'error_import_failed');
    }
  }

  /// Returns a preview of a file the user is about to import.
  /// This performs the same validation as [importFromBytes] but does not
  /// modify the provider state.
  static ImportPreview previewImport({
    required String fileName,
    required int fileSize,
    required List<int> bytes,
    String? expectedSecret,
  }) {
    final actualSize = bytes.length;
    final effectiveSize = actualSize > fileSize ? actualSize : fileSize;

    // Raw byte imports (including network sync) do not have a filename.
    // File-based previews still validate the user-visible extension.
    final ext =
        fileName.isEmpty ? null : fileName.split('.').lastOrNull?.toLowerCase();
    if (ext != null && ext != 'json' && ext != 'asa') {
      return ImportPreview(
        fileName: fileName,
        fileSize: effectiveSize,
        isValid: false,
        errorKey: 'error_invalid_extension',
      );
    }
    if (effectiveSize > _kMaxImportFileSize) {
      return ImportPreview(
        fileName: fileName,
        fileSize: effectiveSize,
        isValid: false,
        errorKey: 'error_file_too_large',
      );
    }

    String? jsonString;
    try {
      jsonString = utf8.decode(bytes);
    } on Exception {
      return ImportPreview(
        fileName: fileName,
        fileSize: effectiveSize,
        isValid: false,
        errorKey: 'error_not_utf8',
      );
    }

    final firstChar =
        jsonString.trimLeft().isNotEmpty ? jsonString.trimLeft()[0] : '';
    if (firstChar != '{' && firstChar != '[') {
      return ImportPreview(
        fileName: fileName,
        fileSize: effectiveSize,
        isValid: false,
        errorKey: 'error_invalid_json',
      );
    }

    dynamic decodedRaw;
    try {
      decodedRaw = jsonDecode(jsonString);
    } on Exception {
      return ImportPreview(
        fileName: fileName,
        fileSize: effectiveSize,
        isValid: false,
        errorKey: 'error_invalid_json',
      );
    }

    if (decodedRaw is! Map<String, dynamic>) {
      return ImportPreview(
        fileName: fileName,
        fileSize: effectiveSize,
        isValid: false,
        errorKey: 'error_invalid_format',
      );
    }

    final decoded = decodedRaw;
    bool hasSecret = false;
    String payloadJson;

    if (decoded.containsKey('payload')) {
      final payloadValue = decoded['payload'];
      if (payloadValue is! String || payloadValue.isEmpty) {
        return ImportPreview(
          fileName: fileName,
          fileSize: effectiveSize,
          isValid: false,
          errorKey: 'error_invalid_format',
        );
      }
      if (decoded['secret'] != null && decoded['secret'] is! String) {
        return ImportPreview(
          fileName: fileName,
          fileSize: effectiveSize,
          isValid: false,
          errorKey: 'error_invalid_format',
        );
      }
      if (decoded['mac'] != null && decoded['mac'] is! String) {
        return ImportPreview(
          fileName: fileName,
          fileSize: effectiveSize,
          isValid: false,
          errorKey: 'error_invalid_format',
        );
      }
      final envelope = SyncEnvelope.fromJson(decoded);
      hasSecret = envelope.secret != null || envelope.mac != null;
      if (envelope.mac != null) {
        if (expectedSecret == null) {
          return ImportPreview(
            fileName: fileName,
            fileSize: effectiveSize,
            isValid: false,
            errorKey: 'error_missing_secret',
            hasSecret: true,
          );
        }
        final expectedMac = _computeMac(expectedSecret, envelope.payload);
        if (!_constantTimeEquals(envelope.mac!, expectedMac)) {
          return ImportPreview(
            fileName: fileName,
            fileSize: effectiveSize,
            isValid: false,
            errorKey: 'error_invalid_secret',
            hasSecret: true,
          );
        }
      } else if (envelope.secret != null) {
        // Do not accept legacy envelopes that put the shared secret on the
        // wire. Sync payloads must use the HMAC format above.
        return ImportPreview(
          fileName: fileName,
          fileSize: effectiveSize,
          isValid: false,
          errorKey: 'error_invalid_secret',
          hasSecret: true,
        );
      } else if (expectedSecret != null) {
        return ImportPreview(
          fileName: fileName,
          fileSize: effectiveSize,
          isValid: false,
          errorKey: 'error_missing_secret',
          hasSecret: true,
        );
      }
      payloadJson = envelope.payload;
    } else if (expectedSecret != null) {
      return ImportPreview(
        fileName: fileName,
        fileSize: effectiveSize,
        isValid: false,
        errorKey: 'error_missing_secret',
      );
    } else {
      payloadJson = jsonString;
    }

    dynamic payloadRaw;
    try {
      payloadRaw = jsonDecode(payloadJson);
    } on Exception {
      return ImportPreview(
        fileName: fileName,
        fileSize: effectiveSize,
        isValid: false,
        errorKey: 'error_invalid_json',
      );
    }

    if (payloadRaw is! Map<String, dynamic>) {
      return ImportPreview(
        fileName: fileName,
        fileSize: effectiveSize,
        isValid: false,
        errorKey: 'error_invalid_format',
      );
    }

    final payload = payloadRaw;

    if (!payload.containsKey('version') ||
        !payload.containsKey('exportedAt') ||
        !payload.containsKey('tasks') ||
        !payload.containsKey('folders')) {
      return ImportPreview(
        fileName: fileName,
        fileSize: effectiveSize,
        isValid: false,
        errorKey: 'error_missing_keys',
      );
    }

    if (payload['tasks'] is! List || payload['folders'] is! List) {
      return ImportPreview(
        fileName: fileName,
        fileSize: effectiveSize,
        isValid: false,
        errorKey: 'error_invalid_lists',
      );
    }

    final taskEntries = payload['tasks'] as List<dynamic>;
    final folderEntries = payload['folders'] as List<dynamic>;
    final areValidEntries = [
      ...taskEntries,
      ...folderEntries,
    ].every((entry) => entry is Map);
    if (!areValidEntries) {
      return ImportPreview(
        fileName: fileName,
        fileSize: effectiveSize,
        isValid: false,
        errorKey: 'error_invalid_lists',
      );
    }

    try {
      final snapshot = AsaDataSnapshot.fromJson(payload);
      final exportedAt = DateTime.fromMillisecondsSinceEpoch(
        snapshot.exportedAt,
        isUtc: true,
      );
      return ImportPreview(
        fileName: fileName,
        fileSize: effectiveSize,
        isValid: true,
        version: snapshot.version,
        exportedAt: exportedAt,
        taskCount: snapshot.tasks.length,
        folderCount: snapshot.folders.length,
        snapshot: snapshot,
        hasSecret: hasSecret,
      );
    } on Exception {
      return ImportPreview(
        fileName: fileName,
        fileSize: effectiveSize,
        isValid: false,
        errorKey: 'error_import_failed',
      );
    }
  }

  /// Imports/merges raw bytes using a last-write-wins (LWW) strategy.
  static Future<ImportResult> importFromBytes(
    TaskProvider provider,
    List<int> bytes, {
    String? expectedSecret,
  }) async {
    final preview = previewImport(
      fileName: '',
      fileSize: bytes.length,
      bytes: bytes,
      expectedSecret: expectedSecret,
    );
    if (!preview.isValid) {
      return ImportResult(error: preview.errorKey ?? 'error_import_failed');
    }
    if (preview.snapshot == null) {
      return const ImportResult(error: 'error_import_failed');
    }
    return importFromSnapshot(provider, preview.snapshot!);
  }

  /// Applies a validated [snapshot] to the provider and persists changes.
  static Future<ImportResult> importFromSnapshot(
    TaskProvider provider,
    AsaDataSnapshot snapshot,
  ) async {
    try {
      int tasksImported = 0;
      int foldersImported = 0;

      for (final taskJson in snapshot.tasks) {
        try {
          final task = TaskItem.fromJson(taskJson);
          if (provider.upsertTask(task)) {
            tasksImported++;
          }
        } on Exception catch (error, stackTrace) {
          LoggerService.instance.w(
            'Failed to import task',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }

      for (final folderJson in snapshot.folders) {
        try {
          final folder = FolderItem.fromJson(folderJson);
          if (!folder.isSystemStreak && provider.upsertFolder(folder)) {
            foldersImported++;
          }
        } on Exception catch (error, stackTrace) {
          LoggerService.instance.w(
            'Failed to import folder',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }

      await provider.persist();
      LoggerService.instance.i(
        'Imported $tasksImported tasks and $foldersImported folders',
      );
      return ImportResult(
        tasksImported: tasksImported,
        foldersImported: foldersImported,
      );
    } on Exception catch (error, stackTrace) {
      LoggerService.instance.e(
        'Import parsing failed',
        error: error,
        stackTrace: stackTrace,
      );
      return const ImportResult(error: 'error_import_failed');
    }
  }

  /// Builds a sync payload that optionally includes a shared [secret].
  static List<int> buildSyncPayload(TaskProvider provider, {String? secret}) {
    final snapshot = buildSnapshot(provider);
    final payload = jsonEncode(snapshot.toJson());
    if (secret == null) {
      return utf8.encode(payload);
    }
    final envelope = SyncEnvelope(
      mac: _computeMac(secret, payload),
      payload: payload,
    );
    return utf8.encode(jsonEncode(envelope.toJson()));
  }

  static String _computeMac(String secret, String payload) {
    final hmac = Hmac(sha256, utf8.encode(secret));
    return hmac.convert(utf8.encode(payload)).toString();
  }

  static bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var i = 0; i < left.length; i++) {
      difference |= left.codeUnitAt(i) ^ right.codeUnitAt(i);
    }
    return difference == 0;
  }

  static Future<File> _writeToFile(String json) async {
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final path = '${dir.path}/asa_backup_$timestamp.json';
    final file = File(path);
    await file.writeAsString(json);
    return file;
  }
}
