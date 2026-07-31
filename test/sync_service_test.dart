import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:asa/core/export_import_service.dart';
import 'package:asa/core/sync_service.dart';
import 'package:asa/features/tasks/providers/task_provider.dart';

class _BonsoirMock {
  static const _channel = MethodChannel('fr.skyost.bonsoir');

  static void setup() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, _handle);
  }

  static void tearDown() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }

  static Future<Object?> _handle(MethodCall call) async {
    final method = call.method;
    if (method == 'broadcast.initialize' ||
        method == 'broadcast.start' ||
        method == 'broadcast.stop' ||
        method == 'discovery.initialize' ||
        method == 'discovery.start' ||
        method == 'discovery.stop') {
      return null;
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _BonsoirMock.setup();

  group('SyncService', () {
    late TaskProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      provider = TaskProvider();
      // Keep the pure-Dart PBKDF2 derivation fast in tests.
      ExportImportService.syncPbkdf2Iterations = 1000;
    });

    tearDown(() async {
      await SyncService.instance.stop();
      SyncService.instance.setSecret(null);
      SyncService.instance.setDeviceName('ASA Device');
      SyncService.instance.setDeviceId('');
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      ExportImportService.syncPbkdf2Iterations = 210000;
      ExportImportService.resetSyncCrypto();
    });

    tearDownAll(_BonsoirMock.tearDown);

    test('setSecret trims and treats empty as null', () {
      SyncService.instance.setSecret('  1234  ');
      expect(SyncService.instance.currentSecret, '1234');

      SyncService.instance.setSecret('   ');
      expect(SyncService.instance.currentSecret, null);

      SyncService.instance.setSecret(null);
      expect(SyncService.instance.currentSecret, null);
    });

    test('setDeviceName trims and defaults empty', () {
      SyncService.instance.setDeviceName('  Phone  ');
      expect(SyncService.instance.currentDeviceName, 'Phone');

      SyncService.instance.setDeviceName('   ');
      expect(SyncService.instance.currentDeviceName, 'ASA Device');
    });

    test('isOwnPeer filters self by device ID and falls back to name/port', () {
      SyncService.instance.setDeviceId('my-device-id');

      final ownById = SyncPeer(
        name: 'Other Device',
        host: '192.168.1.20',
        port: 9999,
        deviceId: 'my-device-id',
      );
      final other = SyncPeer(
        name: 'ASA Device',
        host: '192.168.1.21',
        port: 9999,
        deviceId: 'other-device-id',
      );
      final sameName = SyncPeer(
        name: 'ASA Device',
        host: '192.168.1.21',
        port: 9999,
      );

      expect(SyncService.instance.isOwnPeer(ownById), true);
      expect(SyncService.instance.isOwnPeer(other), false);
      expect(SyncService.instance.isOwnPeer(sameName), false);
    });

    test('start binds to an available port', () async {
      SyncService.instance.setProvider(provider);
      await SyncService.instance.start();

      expect(SyncService.instance.isRunning, true);
      expect(SyncService.instance.actualPort, isNotNull);
      expect(SyncService.instance.actualPort, greaterThan(0));

      await SyncService.instance.stop();
      expect(SyncService.instance.isRunning, false);
      expect(SyncService.instance.actualPort, isNull);
    });

    test('concurrent starts share one startup result', () async {
      SyncService.instance.setProvider(provider);

      final first = SyncService.instance.start();
      final second = SyncService.instance.start();

      expect(await first, true);
      expect(await second, true);
      expect(SyncService.instance.isRunning, true);
      expect(SyncService.instance.actualPort, isNotNull);
    });

    test('sendToPeer round-trips a payload to the local server', () async {
      provider.addTask('Local task');
      final receiver = TaskProvider();
      SyncService.instance.setProvider(receiver);
      SyncService.instance.setSecret('pin');
      await SyncService.instance.start();

      final port = SyncService.instance.actualPort!;
      final peer = SyncPeer(name: 'self', host: '127.0.0.1', port: port);

      final ok = await SyncService.instance.sendToPeer(provider, peer);
      expect(ok, true);
      await Future.delayed(const Duration(milliseconds: 100));
      expect(receiver.tasks.any((t) => t.title == 'Local task'), true);

      await SyncService.instance.stop();
    });

    test('server rejects oversized frames before importing data', () async {
      final receiver = TaskProvider();
      SyncService.instance.setProvider(receiver);
      await SyncService.instance.start();

      final port = SyncService.instance.actualPort!;
      final socket = await Socket.connect('127.0.0.1', port);
      const oversizedLength = 10 * 1024 * 1024 + 1;
      socket.add(<int>[
        (oversizedLength >> 24) & 0xFF,
        (oversizedLength >> 16) & 0xFF,
        (oversizedLength >> 8) & 0xFF,
        oversizedLength & 0xFF,
      ]);
      await socket.flush();
      await socket.close();

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(receiver.tasks, isEmpty);
      await SyncService.instance.stop();
    });

    test('server rejects payload with wrong secret', () async {
      provider.addTask('Secret task');
      final receiver = TaskProvider();
      SyncService.instance.setProvider(receiver);
      SyncService.instance.setSecret('correct');

      final events = <String>[];
      final sub = SyncService.instance.status.listen(events.add);

      await SyncService.instance.start();

      final port = SyncService.instance.actualPort!;
      final payload = await ExportImportService.buildSyncPayload(
        provider,
        secret: 'wrong',
      );
      final socket = await Socket.connect('127.0.0.1', port);
      final length = payload.length;
      final frame = <int>[
        (length >> 24) & 0xFF,
        (length >> 16) & 0xFF,
        (length >> 8) & 0xFF,
        length & 0xFF,
        ...payload,
      ];
      socket.add(frame);
      await socket.flush();
      await socket.close();

      await Future.delayed(const Duration(milliseconds: 100));
      sub.cancel();
      expect(events.any((e) => e.startsWith('merge_failed')), true);

      await SyncService.instance.stop();
    });
  });
}
