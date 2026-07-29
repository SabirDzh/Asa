import 'dart:convert';
import 'dart:io';
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

  factory AsaDataSnapshot.fromJson(Map<String, dynamic> json) => AsaDataSnapshot(
        version: json['version']?.toString() ?? '1.0.0',
        exportedAt: json['exportedAt'] is int ? json['exportedAt'] as int : 0,
        tasks: (json['tasks'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [],
        folders: (json['folders'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [],
      );
}

/// Wire-safe envelope for sync payloads.
class SyncEnvelope {
  final String? secret;
  final String payload;

  const SyncEnvelope({this.secret, required this.payload});

  Map<String, dynamic> toJson() => {
        'secret': secret,
        'payload': payload,
      };

  factory SyncEnvelope.fromJson(Map<String, dynamic> json) => SyncEnvelope(
        secret: json['secret'] as String?,
        payload: json['payload'] as String? ?? '',
      );
}

/// Exports and imports app data as a portable JSON file.
class ExportImportService {
  static const String _version = '1.1.0';

  /// Builds a serializable snapshot from the current provider state.
  static AsaDataSnapshot buildSnapshot(TaskProvider provider) {
    final tasks = provider.tasks.map((t) => t.toJson()).toList();
    final folders = provider.folders
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
      await Share.shareXFiles(
        [xFile],
        subject: 'ASA backup',
      );

      LoggerService.instance.i('Exported ${snapshot.tasks.length} tasks, ${snapshot.folders.length} folders');
      return ExportResult(file: file, success: true);
    } on Exception catch (error, stackTrace) {
      LoggerService.instance.e('Export failed', error: error, stackTrace: stackTrace);
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
      LoggerService.instance.e('Export failed', error: error, stackTrace: stackTrace);
      return ExportResult(error: error.toString(), success: false);
    }
  }

  /// Picks a file and merges its data into the current provider.
  static Future<ImportResult> importFromFile(TaskProvider provider) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'asa'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return const ImportResult(cancelled: true);
      }

      final file = result.files.single;
      if (file.bytes == null) {
        return const ImportResult(error: 'error_import_failed');
      }

      final ext = file.extension?.toLowerCase();
      if (ext != 'json' && ext != 'asa') {
        return const ImportResult(error: 'error_invalid_extension');
      }

      if (file.size > _kMaxImportFileSize) {
        return const ImportResult(error: 'error_file_too_large');
      }

      return importFromBytes(provider, file.bytes!);
    } on Exception catch (error, stackTrace) {
      LoggerService.instance.e('Import failed', error: error, stackTrace: stackTrace);
      return const ImportResult(error: 'error_import_failed');
    }
  }

  /// Imports/merges raw bytes using a last-write-wins (LWW) strategy.
  static Future<ImportResult> importFromBytes(TaskProvider provider, List<int> bytes, {String? expectedSecret}) async {
    String? jsonString;
    try {
      jsonString = utf8.decode(bytes);
    } on Exception {
      return const ImportResult(error: 'error_not_utf8');
    }

    // Basic magic bytes / JSON sanity check: first non-whitespace character
    // must be the start of an object or array.
    final firstChar = jsonString.trimLeft().isNotEmpty ? jsonString.trimLeft()[0] : '';
    if (firstChar != '{' && firstChar != '[') {
      return const ImportResult(error: 'error_invalid_json');
    }

    dynamic decodedRaw;
    try {
      decodedRaw = jsonDecode(jsonString);
    } on Exception {
      return const ImportResult(error: 'error_invalid_json');
    }

    if (decodedRaw is! Map<String, dynamic>) {
      return const ImportResult(error: 'error_invalid_format');
    }

    final decoded = decodedRaw as Map<String, dynamic>;

    String payloadJson;
    if (decoded.containsKey('payload')) {
      final payloadValue = decoded['payload'];
      if (payloadValue is! String || (payloadValue as String).isEmpty) {
        return const ImportResult(error: 'error_invalid_format');
      }
      if (decoded['secret'] != null && decoded['secret'] is! String) {
        return const ImportResult(error: 'error_invalid_format');
      }
      final envelope = SyncEnvelope.fromJson(decoded);
      if (expectedSecret != null && envelope.secret != expectedSecret) {
        return const ImportResult(error: 'error_invalid_secret');
      }
      payloadJson = envelope.payload;
    } else if (expectedSecret != null) {
      return const ImportResult(error: 'error_missing_secret');
    } else {
      payloadJson = jsonString;
    }

    dynamic payloadRaw;
    try {
      payloadRaw = jsonDecode(payloadJson);
    } on Exception {
      return const ImportResult(error: 'error_invalid_json');
    }

    if (payloadRaw is! Map<String, dynamic>) {
      return const ImportResult(error: 'error_invalid_format');
    }

    final payload = payloadRaw as Map<String, dynamic>;

    if (!payload.containsKey('version') ||
        !payload.containsKey('exportedAt') ||
        !payload.containsKey('tasks') ||
        !payload.containsKey('folders')) {
      return const ImportResult(error: 'error_missing_keys');
    }

    if (payload['tasks'] is! List || payload['folders'] is! List) {
      return const ImportResult(error: 'error_invalid_lists');
    }

    try {
      final snapshot = AsaDataSnapshot.fromJson(payload);

      int tasksImported = 0;
      int foldersImported = 0;

      for (final taskJson in snapshot.tasks) {
        try {
          final task = TaskItem.fromJson(taskJson);
          if (provider.upsertTask(task)) {
            tasksImported++;
          }
        } on Exception catch (error, stackTrace) {
          LoggerService.instance.w('Failed to import task', error: error, stackTrace: stackTrace);
        }
      }

      for (final folderJson in snapshot.folders) {
        try {
          final folder = FolderItem.fromJson(folderJson);
          if (!folder.isSystemStreak && provider.upsertFolder(folder)) {
            foldersImported++;
          }
        } on Exception catch (error, stackTrace) {
          LoggerService.instance.w('Failed to import folder', error: error, stackTrace: stackTrace);
        }
      }

      await provider.persist();
      LoggerService.instance.i('Imported $tasksImported tasks and $foldersImported folders');
      return ImportResult(tasksImported: tasksImported, foldersImported: foldersImported);
    } on Exception catch (error, stackTrace) {
      LoggerService.instance.e('Import parsing failed', error: error, stackTrace: stackTrace);
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
    final envelope = SyncEnvelope(secret: secret, payload: payload);
    return utf8.encode(jsonEncode(envelope.toJson()));
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
