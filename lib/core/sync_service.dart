import 'dart:async';
import 'dart:io';
import 'package:bonsoir/bonsoir.dart';

import '../features/tasks/providers/task_provider.dart';
import 'export_import_service.dart';
import 'logger_service.dart';

/// Information about a discovered sync peer.
class SyncPeer {
  final String name;
  final String host;
  final int port;

  const SyncPeer({required this.name, required this.host, required this.port});

  @override
  String toString() => 'SyncPeer($name @ $host:$port)';
}

/// Handles local-network P2P sync over mDNS + TCP sockets.
class SyncService {
  static const String _serviceType = '_taskone-sync._tcp';
  static const String _defaultName = 'Taskone Device';

  static final SyncService instance = SyncService._();
  SyncService._();

  ServerSocket? _server;
  BonsoirBroadcast? _broadcast;
  BonsoirService? _currentService;
  BonsoirDiscovery? _discovery;
  TaskProvider? _provider;
  String _deviceName = _defaultName;
  String? _secret;

  final _peersController = StreamController<List<SyncPeer>>.broadcast();
  Stream<List<SyncPeer>> get peers => _peersController.stream;

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get status => _statusController.stream;

  final List<SyncPeer> _peers = [];
  bool _running = false;
  int? _actualPort;

  bool get isRunning => _running;
  int? get actualPort => _actualPort;

  /// Current human-readable device name used for mDNS broadcast.
  String get currentDeviceName => _deviceName;

  /// Current shared secret, if any.
  String? get currentSecret => _secret;

  /// Sets the [TaskProvider] used for incoming sync merges.
  void setProvider(TaskProvider provider) => _provider = provider;

  /// Sets the visible device name broadcasted over mDNS.
  void setDeviceName(String name) {
    final newName = name.trim().isEmpty ? _defaultName : name.trim();
    if (newName == _deviceName) return;
    _deviceName = newName;
    _updateBroadcast();
  }

  /// Sets the shared secret used to authenticate sync payloads.
  void setSecret(String? secret) {
    final trimmed = secret?.trim();
    _secret = (trimmed != null && trimmed.isNotEmpty) ? trimmed : null;
  }

  /// Starts the sync server and mDNS discovery.
  Future<void> start() async {
    if (_running) return;
    _running = true;

    await _startServer();
    await _startDiscovery();

    LoggerService.instance.i('Sync service started');
    _statusController.add('started');
  }

  /// Stops all sync operations.
  Future<void> stop() async {
    _running = false;
    await _server?.close();
    _server = null;
    _actualPort = null;
    await _broadcast?.stop();
    _broadcast = null;
    _currentService = null;
    await _discovery?.stop();
    _discovery = null;
    _peers.clear();
    _peersController.add(List.unmodifiable(_peers));
    _statusController.add('stopped');
    LoggerService.instance.i('Sync service stopped');
  }

  /// Sends the current data snapshot to [peer].
  Future<bool> sendToPeer(TaskProvider provider, SyncPeer peer) async {
    Socket? socket;
    try {
      socket = await Socket.connect(peer.host, peer.port,
          timeout: const Duration(seconds: 5));
      final payload = ExportImportService.buildSyncPayload(provider, secret: _secret);
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
      await socket.done.timeout(const Duration(seconds: 5), onTimeout: () {});
      LoggerService.instance.i('Sent sync data to ${peer.name}');
      return true;
    } on Exception catch (error, stackTrace) {
      LoggerService.instance.e('Failed to send sync to ${peer.name}',
          error: error, stackTrace: stackTrace);
      return false;
    } finally {
      socket?.destroy();
    }
  }

  Future<void> _startServer() async {
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      _actualPort = _server!.port;

      _server!.listen((socket) async {
        final chunks = <int>[];
        int? expectedLength;
        const maxPayloadSize = 10 * 1024 * 1024; // 10 MB
        socket.listen((data) {
          chunks.addAll(data);
          if (expectedLength == null && chunks.length >= 4) {
            expectedLength = (chunks[0] << 24) | (chunks[1] << 16) | (chunks[2] << 8) | chunks[3];
            if (expectedLength! <= 0 || expectedLength! > maxPayloadSize) {
              LoggerService.instance.w('Sync payload size $expectedLength rejected');
              socket.close();
              return;
            }
          }
          if (expectedLength != null && chunks.length >= expectedLength! + 4) {
            final payload = chunks.sublist(4, expectedLength! + 4);
            final provider = _provider;
            if (provider == null) {
              LoggerService.instance.w('Incoming sync data ignored: no TaskProvider registered');
            } else {
              _handleIncomingData(payload, provider).catchError((Object error, StackTrace stackTrace) {
                LoggerService.instance.e('Incoming sync handling failed', error: error, stackTrace: stackTrace);
              });
            }
            chunks.removeRange(0, expectedLength! + 4);
            expectedLength = null;
          }
        }, onDone: () {
          socket.close();
        });
      });

      _currentService = BonsoirService(
        name: _deviceName,
        type: _serviceType,
        port: _actualPort!,
      );
      _broadcast = BonsoirBroadcast(service: _currentService!);
      await _broadcast!.ready;
      await _broadcast!.start();
    } on Exception catch (error, stackTrace) {
      LoggerService.instance.e('Sync server failed', error: error, stackTrace: stackTrace);
    }
  }

  /// Restarts the mDNS broadcast with the current device name and port.
  Future<void> _updateBroadcast() async {
    if (!_running || _broadcast == null || _actualPort == null) return;
    try {
      await _broadcast!.stop();
      _currentService = BonsoirService(
        name: _deviceName,
        type: _serviceType,
        port: _actualPort!,
      );
      _broadcast = BonsoirBroadcast(service: _currentService!);
      await _broadcast!.ready;
      await _broadcast!.start();
      LoggerService.instance.i('Sync broadcast updated to $_deviceName');
    } on Exception catch (error, stackTrace) {
      LoggerService.instance.e('Failed to update sync broadcast', error: error, stackTrace: stackTrace);
    }
  }

  Future<void> _startDiscovery() async {
    try {
      _discovery = BonsoirDiscovery(type: _serviceType);
      await _discovery!.ready;

      _discovery!.eventStream!.listen((event) {
        if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
          event.service?.resolve(_discovery!.serviceResolver);
        } else if (event.type ==
            BonsoirDiscoveryEventType.discoveryServiceResolved) {
          final resolved = event.service as ResolvedBonsoirService?;
          if (resolved == null) return;
          _addPeer(
            SyncPeer(
              name: resolved.name,
              host: resolved.host ?? '127.0.0.1',
              port: resolved.port,
            ),
          );
        } else if (event.type ==
            BonsoirDiscoveryEventType.discoveryServiceLost) {
          _removePeer(event.service?.name ?? '');
        }
      });

      await _discovery!.start();
    } on Exception catch (error, stackTrace) {
      LoggerService.instance.e('Sync discovery failed', error: error, stackTrace: stackTrace);
    }
  }

  Future<void> _handleIncomingData(List<int> data, TaskProvider provider) async {
    try {
      final result = await ExportImportService.importFromBytes(provider, data, expectedSecret: _secret);
      if (result.success) {
        LoggerService.instance.i('Merged sync data: ${result.tasksImported} tasks, ${result.foldersImported} folders');
        _statusController.add('merged:${result.tasksImported}:${result.foldersImported}');
      } else {
        _statusController.add('merge_failed:${result.error}');
      }
    } on Exception catch (error, stackTrace) {
      LoggerService.instance.e('Sync merge failed', error: error, stackTrace: stackTrace);
    }
  }

  void _addPeer(SyncPeer peer) {
    _peers.removeWhere((p) => p.name == peer.name);
    _peers.add(peer);
    _peersController.add(List.unmodifiable(_peers));
  }

  void _removePeer(String name) {
    _peers.removeWhere((p) => p.name == name);
    _peersController.add(List.unmodifiable(_peers));
  }
}
