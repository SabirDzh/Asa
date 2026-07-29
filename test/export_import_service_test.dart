import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:asa/core/export_import_service.dart';
import 'package:asa/features/tasks/models/task_model.dart';
import 'package:asa/features/tasks/providers/task_provider.dart';

void main() {
  group('ExportImportService', () {
    late TaskProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = TaskProvider();
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

    test('importFromBytes adds new tasks and folders', () async {
      final snapshot = AsaDataSnapshot(
        version: '1.1.0',
        exportedAt: 0,
        tasks: [
          TaskItem(id: 't1', title: 'Remote task', updatedAt: DateTime(2026, 1, 1)).toJson(),
        ],
        folders: [
          FolderItem(id: 'f1', name: 'Remote folder', updatedAt: DateTime(2026, 1, 1)).toJson(),
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

    test('LWW merge prefers newer task', () async {
      provider.addTask('Local task');
      final localId = provider.tasks.first.id;
      final now = DateTime.now();

      final remote = TaskItem(id: localId, title: 'Remote task', updatedAt: now.add(const Duration(days: 1))).toJson();
      final snapshot = AsaDataSnapshot(
        version: '1.1.0',
        exportedAt: 0,
        tasks: [remote],
        folders: [],
      );

      final result = await ExportImportService.importFromBytes(provider, _utf8(snapshot.toJson()));

      expect(result.success, true);
      expect(provider.tasks.first.title, 'Remote task');
    });

    test('LWW merge keeps newer local task', () async {
      provider.addTask('Local task');
      final localId = provider.tasks.first.id;
      final now = DateTime.now();

      final remote = TaskItem(id: localId, title: 'Remote task', updatedAt: now.subtract(const Duration(days: 1))).toJson();
      final snapshot = AsaDataSnapshot(
        version: '1.1.0',
        exportedAt: 0,
        tasks: [remote],
        folders: [],
      );

      final result = await ExportImportService.importFromBytes(provider, _utf8(snapshot.toJson()));

      expect(result.success, true);
      expect(result.tasksImported, 0);
      expect(provider.tasks.first.title, 'Local task');
    });

    test('LWW merge propagates soft-delete', () async {
      provider.addTask('Local task');
      final localId = provider.tasks.first.id;
      final now = DateTime.now();

      final remote = TaskItem(
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

      final result = await ExportImportService.importFromBytes(provider, _utf8(snapshot.toJson()));

      expect(result.success, true);
      expect(provider.tasks, isEmpty);
      expect(provider.allTasks.first.isDeleted, true);
    });

    group('secret validation', () {
      test('accepts envelope with correct secret', () async {
        final payload = AsaDataSnapshot(
          version: '1.1.0',
          exportedAt: 0,
          tasks: [TaskItem(id: 't1', title: 'Secret task').toJson()],
          folders: [],
        );
        final envelope = SyncEnvelope(secret: '1234', payload: _json(payload.toJson()));
        final bytes = _utf8(envelope.toJson());

        final result = await ExportImportService.importFromBytes(
          provider,
          bytes,
          expectedSecret: '1234',
        );

        expect(result.success, true);
        expect(result.tasksImported, 1);
      });

      test('rejects envelope with wrong secret', () async {
        final payload = AsaDataSnapshot(
          version: '1.1.0',
          exportedAt: 0,
          tasks: [TaskItem(id: 't1', title: 'Secret task').toJson()],
          folders: [],
        );
        final envelope = SyncEnvelope(secret: '1234', payload: _json(payload.toJson()));
        final bytes = _utf8(envelope.toJson());

        final result = await ExportImportService.importFromBytes(
          provider,
          bytes,
          expectedSecret: 'wrong',
        );

        expect(result.success, false);
        expect(result.error, 'Invalid sync secret');
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
        expect(result.error, 'Missing sync secret');
      });

      test('accepts plain payload when no secret expected', () async {
        final payload = AsaDataSnapshot(
          version: '1.1.0',
          exportedAt: 0,
          tasks: [TaskItem(id: 't1', title: 'Plain task').toJson()],
          folders: [],
        );
        final bytes = _utf8(payload.toJson());

        final result = await ExportImportService.importFromBytes(provider, bytes);

        expect(result.success, true);
        expect(result.tasksImported, 1);
      });
    });

    test('buildSyncPayload without secret is plain JSON', () {
      provider.addTask('Task');
      final bytes = ExportImportService.buildSyncPayload(provider);
      final decoded = _decode(bytes) as Map<String, dynamic>;

      expect(decoded.containsKey('payload'), false);
      expect(decoded['tasks'], isA<List<dynamic>>());
    });

    test('buildSyncPayload with secret wraps in envelope', () {
      provider.addTask('Task');
      final bytes = ExportImportService.buildSyncPayload(provider, secret: '1234');
      final decoded = _decode(bytes) as Map<String, dynamic>;

      expect(decoded['secret'], '1234');
      expect(decoded['payload'], isA<String>());
    });
  });
}

String _json(Map<String, dynamic> json) => jsonEncode(json);

List<int> _utf8(Map<String, dynamic> json) => utf8.encode(jsonEncode(json));

Object _decode(List<int> bytes) => jsonDecode(utf8.decode(bytes));
