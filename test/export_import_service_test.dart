import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:asa/core/export_import_service.dart';
import 'package:asa/features/tasks/models/task_info_block.dart';
import 'package:asa/features/tasks/models/task_model.dart';
import 'package:asa/features/tasks/providers/task_provider.dart';

void main() {
  group('ExportImportService', () {
    late TaskProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = TaskProvider();
      // Keep the pure-Dart PBKDF2 derivation fast in tests.
      ExportImportService.syncPbkdf2Iterations = 1000;
    });

    tearDown(() {
      ExportImportService.syncPbkdf2Iterations = 210000;
      ExportImportService.resetSyncCrypto();
    });

    test('buildSnapshot includes tasks and folders', () {
      provider.addTask('Task A');
      provider.addFolder('Work');

      final snapshot = ExportImportService.buildSnapshot(provider);

      expect(snapshot.tasks.length, 1);
      expect(snapshot.tasks.first['title'], 'Task A');
      expect(snapshot.folders.length, 1);
      expect(snapshot.folders.first['name'], 'Work');
    });

    test(
      'buildSnapshot preserves task block metadata without binary bytes',
      () {
        provider.addTask(
          'Read a book',
          infoBlocks: [
            TaskInfoBlock.description(
              id: 'book-notes',
              text: 'Read chapter one',
              attachments: [
                const TaskAttachment(
                  id: 'book-link',
                  type: TaskAttachmentType.link,
                  name: 'Book source',
                  value: 'https://example.com/book',
                ),
              ],
            ),
          ],
        );

        final snapshot = ExportImportService.buildSnapshot(provider);
        final encoded = jsonEncode(snapshot.toJson());

        expect(encoded, contains('Read chapter one'));
        expect(encoded, contains('https://example.com/book'));
        expect(encoded, isNot(contains('base64')));
        expect(encoded, isNot(contains('bytes')));
      },
    );

    test('importFromFile reports cancelled when no file is picked', () {
      const result = ImportResult(cancelled: true);
      expect(result.cancelled, true);
      expect(result.success, false);
      expect(result.error, isNull);
    });

    test('importFromBytes adds new tasks and folders', () async {
      final snapshot = AsaDataSnapshot(
        version: '1.1.0',
        exportedAt: 0,
        tasks: [
          TaskItem(
            id: 't1',
            title: 'Remote task',
            updatedAt: DateTime(2026, 1, 1),
          ).toJson(),
        ],
        folders: [
          FolderItem(
            id: 'f1',
            name: 'Remote folder',
            updatedAt: DateTime(2026, 1, 1),
          ).toJson(),
        ],
      );

      final result = await ExportImportService.importFromBytes(
        provider,
        _utf8(snapshot.toJson()),
      );

      expect(result.success, true);
      expect(result.tasksImported, 1);
      expect(result.foldersImported, 1);
      expect(provider.tasks.any((t) => t.id == 't1'), true);
      expect(provider.folders.any((f) => f.id == 'f1'), true);
    });

    test(
      'import rejects reserved streak folders but keeps valid folders',
      () async {
        final snapshot = AsaDataSnapshot(
          version: '1.1.0',
          exportedAt: 0,
          tasks: [],
          folders: [
            FolderItem(id: 'valid', name: 'Valid folder').toJson(),
            FolderItem(
              id: 'system-shaped',
              name: 'System-shaped',
              isSystemStreak: true,
            ).toJson(),
            FolderItem(
              id: 'nested-in-streak',
              name: 'Nested in streak',
              parentFolderId: 'system_streak_folder',
            ).toJson(),
          ],
        );

        await provider.ready;
        final result = await ExportImportService.importFromSnapshot(
          provider,
          snapshot,
        );

        expect(result.success, true);
        expect(result.foldersImported, 1);
        expect(provider.folders.any((folder) => folder.id == 'valid'), true);
        expect(
          provider.folders.where(
            (folder) => folder.id != 'system_streak_folder',
          ),
          hasLength(1),
        );
      },
    );

    test('LWW merge prefers newer task', () async {
      provider.addTask('Local task');
      final localId = provider.tasks.first.id;
      final now = DateTime.now();

      final remote =
          TaskItem(
            id: localId,
            title: 'Remote task',
            updatedAt: now.add(const Duration(days: 1)),
          ).toJson();
      final snapshot = AsaDataSnapshot(
        version: '1.1.0',
        exportedAt: 0,
        tasks: [remote],
        folders: [],
      );

      final result = await ExportImportService.importFromBytes(
        provider,
        _utf8(snapshot.toJson()),
      );

      expect(result.success, true);
      expect(provider.tasks.first.title, 'Remote task');
    });

    test('LWW merge keeps newer local task', () async {
      provider.addTask('Local task');
      final localId = provider.tasks.first.id;
      final now = DateTime.now();

      final remote =
          TaskItem(
            id: localId,
            title: 'Remote task',
            updatedAt: now.subtract(const Duration(days: 1)),
          ).toJson();
      final snapshot = AsaDataSnapshot(
        version: '1.1.0',
        exportedAt: 0,
        tasks: [remote],
        folders: [],
      );

      final result = await ExportImportService.importFromBytes(
        provider,
        _utf8(snapshot.toJson()),
      );

      expect(result.success, true);
      expect(result.tasksImported, 0);
      expect(provider.tasks.first.title, 'Local task');
    });

    test('LWW merge propagates soft-delete', () async {
      provider.addTask('Local task');
      final localId = provider.tasks.first.id;
      final now = DateTime.now();

      final remote =
          TaskItem(
            id: localId,
            title: 'Local task',
            isDeleted: true,
            updatedAt: now.add(const Duration(days: 1)),
          ).toJson();
      final snapshot = AsaDataSnapshot(
        version: '1.1.0',
        exportedAt: 0,
        tasks: [remote],
        folders: [],
      );

      final result = await ExportImportService.importFromBytes(
        provider,
        _utf8(snapshot.toJson()),
      );

      expect(result.success, true);
      expect(provider.tasks, isEmpty);
      expect(provider.allTasks.first.isDeleted, true);
    });

    group('secret validation', () {
      test('rejects legacy envelope that exposes the secret', () async {
        final payload = AsaDataSnapshot(
          version: '1.1.0',
          exportedAt: 0,
          tasks: [TaskItem(id: 't1', title: 'Secret task').toJson()],
          folders: [],
        );
        final envelope = SyncEnvelope(
          secret: '1234',
          payload: _json(payload.toJson()),
        );
        final bytes = _utf8(envelope.toJson());

        final result = await ExportImportService.importFromBytes(
          provider,
          bytes,
          expectedSecret: '1234',
        );

        expect(result.success, false);
        expect(result.error, 'error_invalid_secret');
      });

      test('rejects envelope with wrong secret', () async {
        final payload = AsaDataSnapshot(
          version: '1.1.0',
          exportedAt: 0,
          tasks: [TaskItem(id: 't1', title: 'Secret task').toJson()],
          folders: [],
        );
        final envelope = SyncEnvelope(
          secret: '1234',
          payload: _json(payload.toJson()),
        );
        final bytes = _utf8(envelope.toJson());

        final result = await ExportImportService.importFromBytes(
          provider,
          bytes,
          expectedSecret: 'wrong',
        );

        expect(result.success, false);
        expect(result.error, 'error_invalid_secret');
      });

      test('rejects plain payload when secret expected', () async {
        final payload = AsaDataSnapshot(
          version: '1.1.0',
          exportedAt: 0,
          tasks: [TaskItem(id: 't1', title: 'Secret task').toJson()],
          folders: [],
        );
        final bytes = _utf8(payload.toJson());

        final result = await ExportImportService.importFromBytes(
          provider,
          bytes,
          expectedSecret: '1234',
        );

        expect(result.success, false);
        expect(result.error, 'error_missing_secret');
      });

      test('accepts plain payload when no secret expected', () async {
        final payload = AsaDataSnapshot(
          version: '1.1.0',
          exportedAt: 0,
          tasks: [TaskItem(id: 't1', title: 'Plain task').toJson()],
          folders: [],
        );
        final bytes = _utf8(payload.toJson());

        final result = await ExportImportService.importFromBytes(
          provider,
          bytes,
        );

        expect(result.success, true);
        expect(result.tasksImported, 1);
      });
    });

    test('buildSyncPayload without secret is plain JSON', () async {
      provider.addTask('Task');
      final bytes = await ExportImportService.buildSyncPayload(provider);
      final decoded = _decode(bytes) as Map<String, dynamic>;

      expect(decoded.containsKey('payload'), false);
      expect(decoded['tasks'], isA<List<dynamic>>());
    });

    test('buildSyncPayload with secret produces an encrypted envelope '
        'without exposing the payload or secret', () async {
      provider.addTask('Task');
      final bytes = await ExportImportService.buildSyncPayload(
        provider,
        secret: '1234',
      );
      final decoded = _decode(bytes) as Map<String, dynamic>;

      expect(decoded['secret'], isNull);
      expect(decoded['mac'], isNull);
      expect(decoded['alg'], 'aes-256-gcm');
      expect(decoded['payload'], isA<String>());
      // The plaintext JSON and the secret must not appear on the wire.
      expect(utf8.decode(bytes), isNot(contains('Task')));
      expect(utf8.decode(bytes), isNot(contains('1234')));
    });

    test('importFromBytes accepts a valid legacy HMAC envelope', () async {
      provider.addTask('Task');
      final payload = _json(
        ExportImportService.buildSnapshot(provider).toJson(),
      );
      final hmac = Hmac(sha256, utf8.encode('1234'));
      final mac = hmac.convert(utf8.encode(payload)).toString();
      final envelope = SyncEnvelope(mac: mac, payload: payload);
      final bytes = _utf8(envelope.toJson());

      final result = await ExportImportService.importFromBytes(
        TaskProvider(),
        bytes,
        expectedSecret: '1234',
      );

      expect(result.success, true);
      expect(result.tasksImported, 1);
    });

    test('importFromBytes accepts a valid encrypted envelope', () async {
      provider.addTask('Task');
      final bytes = await ExportImportService.buildSyncPayload(
        provider,
        secret: '1234',
      );

      final result = await ExportImportService.importFromBytes(
        TaskProvider(),
        bytes,
        expectedSecret: '1234',
      );

      expect(result.success, true);
      expect(result.tasksImported, 1);
    });

    test(
      'importFromBytes rejects an encrypted envelope with wrong secret',
      () async {
        provider.addTask('Task');
        final bytes = await ExportImportService.buildSyncPayload(
          provider,
          secret: '1234',
        );

        final result = await ExportImportService.importFromBytes(
          TaskProvider(),
          bytes,
          expectedSecret: 'wrong',
        );

        expect(result.success, false);
        expect(result.error, 'error_invalid_secret');
      },
    );

    test('importFromBytes rejects a tampered encrypted envelope', () async {
      provider.addTask('Task');
      final decoded =
          _decode(
                await ExportImportService.buildSyncPayload(
                  provider,
                  secret: '1234',
                ),
              )
              as Map<String, dynamic>;
      // Corrupt the base64 payload while keeping it decodable.
      final payload = decoded['payload'] as String;
      decoded['payload'] = 'AAAA${payload.substring(4)}';

      final result = await ExportImportService.importFromBytes(
        TaskProvider(),
        _utf8(decoded),
        expectedSecret: '1234',
      );

      expect(result.success, false);
      expect(result.error, 'error_invalid_secret');
    });

    test('importFromBytes rejects an unauthenticated envelope', () async {
      provider.addTask('Task');
      final decoded =
          _decode(await ExportImportService.buildSyncPayload(provider))
              as Map<String, dynamic>;
      final unauthenticated = <String, dynamic>{'payload': jsonEncode(decoded)};

      final result = await ExportImportService.importFromBytes(
        TaskProvider(),
        _utf8(unauthenticated),
        expectedSecret: '1234',
      );

      expect(result.success, false);
      expect(result.error, 'error_missing_secret');
    });

    test('importFromBytes rejects non-UTF8 bytes', () async {
      final result = await ExportImportService.importFromBytes(provider, [
        0x80,
        0x81,
        0x82,
      ]);
      expect(result.success, false);
      expect(result.error, 'error_not_utf8');
    });

    test('importFromBytes rejects invalid JSON', () async {
      final result = await ExportImportService.importFromBytes(
        provider,
        utf8.encode('not json'),
      );
      expect(result.success, false);
      expect(result.error, 'error_invalid_json');
    });

    test('importFromBytes rejects non-object JSON', () async {
      final result = await ExportImportService.importFromBytes(
        provider,
        utf8.encode('[1, 2, 3]'),
      );
      expect(result.success, false);
      expect(result.error, 'error_invalid_format');
    });

    test('importFromBytes rejects missing required keys', () async {
      final result = await ExportImportService.importFromBytes(
        provider,
        utf8.encode(jsonEncode({'version': '1.1.0'})),
      );
      expect(result.success, false);
      expect(result.error, 'error_missing_keys');
    });

    test('importFromBytes rejects non-list tasks/folders', () async {
      final result = await ExportImportService.importFromBytes(
        provider,
        utf8.encode(
          jsonEncode({
            'version': '1.1.0',
            'exportedAt': 0,
            'tasks': 'not-a-list',
            'folders': [],
          }),
        ),
      );
      expect(result.success, false);
      expect(result.error, 'error_invalid_lists');
    });

    test('importFromBytes rejects envelope without string payload', () async {
      final result = await ExportImportService.importFromBytes(
        provider,
        utf8.encode(jsonEncode({'payload': 123})),
      );
      expect(result.success, false);
      expect(result.error, 'error_invalid_format');
    });

    test('SyncEnvelope rejects malformed wire fields', () {
      expect(() => SyncEnvelope.fromJson({}), throwsFormatException);
      expect(
        () => SyncEnvelope.fromJson({'payload': ''}),
        throwsFormatException,
      );
      expect(
        () => SyncEnvelope.fromJson({'payload': '{}', 'mac': 123}),
        throwsFormatException,
      );
      expect(
        () => SyncEnvelope.fromJson({'payload': '{}', 'secret': false}),
        throwsFormatException,
      );
    });

    group('previewImport', () {
      test('returns valid preview with task and folder counts', () {
        final snapshot = AsaDataSnapshot(
          version: '1.1.0',
          exportedAt: 0,
          tasks: [TaskItem(id: 't1', title: 'Remote task').toJson()],
          folders: [FolderItem(id: 'f1', name: 'Remote folder').toJson()],
        );

        final preview = ExportImportService.previewImport(
          fileName: 'backup.json',
          fileSize: 1024,
          bytes: _utf8(snapshot.toJson()),
        );

        expect(preview.isValid, true);
        expect(preview.fileName, 'backup.json');
        expect(preview.fileSizeLabel, '1.0 KB');
        expect(preview.taskCount, 1);
        expect(preview.folderCount, 1);
        expect(preview.version, '1.1.0');
        expect(preview.errorKey, isNull);
      });

      test('returns invalid preview for corrupted JSON', () {
        final preview = ExportImportService.previewImport(
          fileName: 'bad.json',
          fileSize: 12,
          bytes: utf8.encode('not json'),
        );

        expect(preview.isValid, false);
        expect(preview.errorKey, 'error_invalid_json');
      });

      test('returns invalid preview when file is too large', () {
        final preview = ExportImportService.previewImport(
          fileName: 'huge.json',
          fileSize: 20 * 1024 * 1024,
          bytes: utf8.encode('{}'),
        );

        expect(preview.isValid, false);
        expect(preview.errorKey, 'error_file_too_large');
      });

      test('returns invalid preview for missing required keys', () {
        final preview = ExportImportService.previewImport(
          fileName: 'incomplete.json',
          fileSize: 100,
          bytes: utf8.encode(jsonEncode({'version': '1.1.0'})),
        );

        expect(preview.isValid, false);
        expect(preview.errorKey, 'error_missing_keys');
      });

      test(
        'rejects bytes larger than the import limit even when fileSize is smaller',
        () {
          final bytes = List<int>.filled(10 * 1024 * 1024 + 1, 32);
          final preview = ExportImportService.previewImport(
            fileName: 'backup.json',
            fileSize: 1,
            bytes: bytes,
          );

          expect(preview.isValid, false);
          expect(preview.errorKey, 'error_file_too_large');
        },
      );

      test('rejects task entries that are not JSON objects', () {
        final preview = ExportImportService.previewImport(
          fileName: 'backup.json',
          fileSize: 32,
          bytes: utf8.encode(
            jsonEncode({
              'version': '1.1.0',
              'exportedAt': 1,
              'tasks': ['not-a-map'],
              'folders': [],
            }),
          ),
        );

        expect(preview.isValid, false);
        expect(preview.errorKey, 'error_invalid_lists');
      });

      test('rejects malformed folder entries in the snapshot constructor', () {
        expect(
          () => AsaDataSnapshot.fromJson({
            'version': '1.1.0',
            'exportedAt': 1,
            'tasks': [],
            'folders': ['not-a-map'],
          }),
          throwsFormatException,
        );
      });

      test('rejects malformed task entries in the snapshot constructor', () {
        expect(
          () => AsaDataSnapshot.fromJson({
            'version': '1.1.0',
            'exportedAt': 1,
            'tasks': ['not-a-map'],
            'folders': [],
          }),
          throwsFormatException,
        );
      });
    });
  });
}

String _json(Map<String, dynamic> json) => jsonEncode(json);

List<int> _utf8(Map<String, dynamic> json) => utf8.encode(jsonEncode(json));

Object _decode(List<int> bytes) => jsonDecode(utf8.decode(bytes));
