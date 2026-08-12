import 'dart:async';
import 'dart:io';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import '../features/tasks/providers/task_provider.dart';
import 'export_import_service.dart';
import 'logger_service.dart';

/// Information about a discovered sync peer.
class SyncPeer {
  final String name;
  final String host;
  final int port;

  /// Unique device ID advertised in the mDNS TXT record, if available.
  final String? deviceId;

  const SyncPeer({
    required this.name,
    required this.host,
    required this.port,
    this.deviceId,
  });

  @override
  String toString() => 'SyncPeer($name @ $host:$port, did=$deviceId)';
}

/// Handles local-network P2P sync over mDNS + TCP sockets.
class SyncService {
  static const String _serviceType = '_asa-sync._tcp';
  static const String _defaultName = 'ASA Device';

  static final SyncService instance = SyncService._();
  SyncService._();

  ServerSocket? _server;
  BonsoirBroadcast? _broadcast;
  BonsoirService? _currentService;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoverySubscription;
  TaskProvider? _provider;
  String _deviceName = _defaultName;
  String? _secret;
  String _deviceId = '';

  final _peersController = StreamController<List<SyncPeer>>.broadcast();
  Stream<List<SyncPeer>> get peers => _peersController.stream;

  final _statusController = StreamController<String>.broadcast();
  Stream<String> get status => _statusController.stream;

  final List<SyncPeer> _peers = [];
  final Set<Socket> _activeSockets = <Socket>{};
  final Map<Socket, Timer> _socketTimeouts = <Socket, Timer>{};
  Future<bool>? _startFuture;
  Future<void>? _broadcastUpdateFuture;
  String? _activeBroadcastSignature;
  int _lifecycleGeneration = 0;
  bool _running = false;
  int? _actualPort;
  List<String> _localAddresses = [];

  static const _incomingFrameTimeout = Duration(seconds: 10);

  bool get isRunning => _running;
  int? get actualPort => _actualPort;

  @visibleForTesting
  bool isOwnPeer(SyncPeer peer) => _isOwnPeer(peer);

  /// Current human-readable device name used for mDNS broadcast.
  String get currentDeviceName => _deviceName;

  /// Current stable device ID used to identify this device on the network.
  String get currentDeviceId => _deviceId;

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

  /// Sets the stable device ID used to filter this device from peer discovery.
  void setDeviceId(String id) {
    final trimmed = id.trim();
    if (trimmed == _deviceId) return;
    _deviceId = trimmed;
    _updateBroadcast();
  }

  /// Sets the shared secret used to authenticate sync payloads.
  void setSecret(String? secret) {
    final trimmed = secret?.trim();
    LoggerService.instance.registerSecret(trimmed);
    _secret = (trimmed != null && trimmed.isNotEmpty) ? trimmed : null;
  }

  /// Starts the sync server and mDNS discovery.
  Future<bool> start() async {
    final inFlight = _startFuture;
    if (inFlight != null) return inFlight;
    if (_running) return true;

    final startFuture = _startInternal();
    _startFuture = startFuture;
    try {
      return await startFuture;
    } finally {
      if (identical(_startFuture, startFuture)) _startFuture = null;
    }
  }

  Future<bool> _startInternal() async {
    if (_secret == null) {
      LoggerService.instance.w(
        'Sync start rejected: shared secret is required',
      );
      _statusController.add('failed:missing_secret');
      return false;
    }
    final generation = ++_lifecycleGeneration;
    _running = true;
    final serverStarted = await _startServer();
    if (!_isCurrentGeneration(generation)) {
      await _cleanupStaleStart();
      return false;
    }
    final discoveryStarted = serverStarted && await _startDiscovery();
    if (!_isCurrentGeneration(generation)) {
      await _cleanupStaleStart();
      return false;
    }
    if (!serverStarted || !discoveryStarted) {
      await stop();
      _statusController.add('failed');
      return false;
    }

    LoggerService.instance.i('Sync service started');
    _statusController.add('started');
    return true;
  }

  bool _isCurrentGeneration(int generation) =>
      generation == _lifecycleGeneration && _running;

  Future<void> _cleanupStaleStart() async {
    final server = _server;
    final broadcast = _broadcast;
    final discoverySubscription = _discoverySubscription;
    final discovery = _discovery;
    _server = null;
    _actualPort = null;
    _broadcast = null;
    _currentService = null;
    _activeBroadcastSignature = null;
    _discoverySubscription = null;
    _discovery = null;

    final activeSockets = List<Socket>.from(_activeSockets);
    for (final socket in activeSockets) {
      _socketTimeouts.remove(socket)?.cancel();
      socket.destroy();
    }
    _activeSockets.clear();

    await _stopResource('stale sync server', server?.close);
    await _stopResource('stale sync broadcast', broadcast?.stop);
    await _stopResource(
      'stale sync discovery subscription',
      discoverySubscription?.cancel,
    );
    await _stopResource('stale sync discovery', discovery?.stop);
  }

  /// Stops all sync operations.
  Future<void> stop() async {
    _lifecycleGeneration++;
    _running = false;
    final pendingBroadcastUpdate = _broadcastUpdateFuture;
    await _stopResource(
      'pending sync broadcast update',
      pendingBroadcastUpdate == null ? null : () => pendingBroadcastUpdate,
    );
    final server = _server;
    final broadcast = _broadcast;
    final discoverySubscription = _discoverySubscription;
    final discovery = _discovery;
    _server = null;
    _actualPort = null;
    _broadcast = null;
    _currentService = null;
    _activeBroadcastSignature = null;
    _discoverySubscription = null;
    _discovery = null;

    final activeSockets = List<Socket>.from(_activeSockets);
    for (final socket in activeSockets) {
      _socketTimeouts.remove(socket)?.cancel();
      socket.destroy();
    }
    _activeSockets.clear();

    await _stopResource('sync server', server?.close);
    await _stopResource('sync broadcast', broadcast?.stop);
    await _stopResource(
      'sync discovery subscription',
      discoverySubscription?.cancel,
    );
    await _stopResource('sync discovery', discovery?.stop);

    _peers.clear();
    _peersController.add(List.unmodifiable(_peers));
    _statusController.add('stopped');
    LoggerService.instance.i('Sync service stopped');
  }

  Future<void> _stopResource(
    String name,
    Future<void> Function()? close,
  ) async {
    if (close == null) return;
    try {
      await close();
    } on Object catch (error, stackTrace) {
      LoggerService.instance.w(
        'Failed to stop $name',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Sends the current data snapshot to [peer].
  ///
  /// Sync transport is never allowed to send a plaintext snapshot. Export
  /// files may remain unencrypted by design, but LAN sync requires the shared
  /// secret that also authenticates/encrypts the payload.
  Future<bool> sendToPeer(TaskProvider provider, SyncPeer peer) async {
    if (_secret == null || _secret!.isEmpty) {
      LoggerService.instance.w('Sync send rejected: shared secret is required');
      return false;
    }

    Socket? socket;
    try {
      socket = await Socket.connect(
        peer.host,
        peer.port,
        timeout: const Duration(seconds: 5),
      );
      _activeSockets.add(socket);
      final payload = await ExportImportService.buildSyncPayload(
        provider,
        secret: _secret,
      );
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
      // The frame is complete once flush resolves; signal EOF instead of
      // waiting for the peer to close first (which otherwise adds a 5s delay).
      await socket.close();
      LoggerService.instance.i('Sent sync data to ${peer.name}');
      return true;
    } on Exception catch (error, stackTrace) {
      LoggerService.instance.e(
        'Failed to send sync to ${peer.name}',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    } finally {
      if (socket != null) _activeSockets.remove(socket);
      socket?.destroy();
    }
  }

  Future<bool> _startServer() async {
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      _actualPort = _server!.port;

      _server!.listen(
        (socket) {
          _activeSockets.add(socket);
          final chunks = <int>[];
          int? expectedLength;
          var frameHandled = false;
          const maxPayloadSize = 10 * 1024 * 1024; // 10 MB

          void cleanupSocket() {
            _socketTimeouts.remove(socket)?.cancel();
            _activeSockets.remove(socket);
          }

          void rejectFrame(String reason) {
            if (frameHandled) return;
            frameHandled = true;
            cleanupSocket();
            LoggerService.instance.w('Incoming sync frame rejected: $reason');
            socket.destroy();
          }

          void armTimeout() {
            _socketTimeouts[socket]?.cancel();
            _socketTimeouts[socket] = Timer(_incomingFrameTimeout, () {
              rejectFrame('frame read timeout');
            });
          }

          armTimeout();
          socket.listen(
            (data) {
              if (frameHandled) return;
              armTimeout();
              chunks.addAll(data);
              if (chunks.length > maxPayloadSize + 4) {
                rejectFrame('frame exceeds limit');
                return;
              }
              if (expectedLength == null && chunks.length >= 4) {
                expectedLength =
                    (chunks[0] << 24) |
                    (chunks[1] << 16) |
                    (chunks[2] << 8) |
                    chunks[3];
                if (expectedLength! <= 0 || expectedLength! > maxPayloadSize) {
                  rejectFrame('invalid payload size');
                  return;
                }
              }
              if (expectedLength != null &&
                  chunks.length >= expectedLength! + 4) {
                frameHandled = true;
                final payload = chunks.sublist(4, expectedLength! + 4);
                final provider = _provider;
                cleanupSocket();
                socket.destroy();
                if (provider == null) {
                  LoggerService.instance.w(
                    'Incoming sync data ignored: no TaskProvider registered',
                  );
                } else {
                  _handleIncomingData(payload, provider).catchError((
                    Object error,
                    StackTrace stackTrace,
                  ) {
                    LoggerService.instance.e(
                      'Incoming sync handling failed',
                      error: error,
                      stackTrace: stackTrace,
                    );
                  });
                }
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!frameHandled) {
                frameHandled = true;
                cleanupSocket();
                LoggerService.instance.w(
                  'Incoming sync connection failed',
                  error: error,
                  stackTrace: stackTrace,
                );
                socket.destroy();
              }
            },
            onDone: () {
              cleanupSocket();
              if (!frameHandled) socket.destroy();
            },
            cancelOnError: true,
          );
        },
        onError: (Object error, StackTrace stackTrace) {
          LoggerService.instance.e(
            'Sync server connection failed',
            error: error,
            stackTrace: stackTrace,
          );
        },
      );

      _currentService = BonsoirService(
        name: _deviceName,
        type: _serviceType,
        port: _actualPort!,
        attributes: <String, String>{
          if (_deviceId.isNotEmpty) 'did': _deviceId,
        },
      );
      _broadcast = BonsoirBroadcast(service: _currentService!);
      await _broadcast!.ready;
      await _broadcast!.start();
      _activeBroadcastSignature = _broadcastSignatureForCurrentSettings();
      return true;
    } on Exception catch (error, stackTrace) {
      LoggerService.instance.e(
        'Sync server failed',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Restarts the mDNS broadcast with the current device name and port.
  ///
  /// Settings can update the name and device ID back-to-back. Queue updates so
  /// Bonsoir never receives overlapping stop/start calls, and coalesce changes
  /// that are already represented by the active broadcast.
  void _updateBroadcast() {
    final previous = _broadcastUpdateFuture ?? Future<void>.value();
    final update = previous.then<void>((_) async {
      if (!_running || _broadcast == null || _actualPort == null) return;
      if (_activeBroadcastSignature ==
          _broadcastSignatureForCurrentSettings()) {
        return;
      }

      final generation = _lifecycleGeneration;
      final broadcast = _broadcast!;
      final port = _actualPort!;
      try {
        await broadcast.stop();
        if (!_isCurrentGeneration(generation) ||
            !identical(_broadcast, broadcast) ||
            _actualPort != port) {
          return;
        }

        final signature = _broadcastSignatureForCurrentSettings();
        final replacement = BonsoirBroadcast(
          service: BonsoirService(
            name: _deviceName,
            type: _serviceType,
            port: port,
            attributes: <String, String>{
              if (_deviceId.isNotEmpty) 'did': _deviceId,
            },
          ),
        );
        _currentService = replacement.service;
        _broadcast = replacement;
        await replacement.ready;
        if (!_isCurrentGeneration(generation) ||
            !identical(_broadcast, replacement)) {
          await _stopResource(
            'stale sync broadcast replacement',
            replacement.stop,
          );
          if (identical(_broadcast, replacement)) {
            _broadcast = null;
            _currentService = null;
          }
          return;
        }

        await replacement.start();
        if (!_isCurrentGeneration(generation) ||
            !identical(_broadcast, replacement)) {
          await _stopResource(
            'stale sync broadcast replacement',
            replacement.stop,
          );
          if (identical(_broadcast, replacement)) {
            _broadcast = null;
            _currentService = null;
          }
          return;
        }

        _activeBroadcastSignature = signature;
        LoggerService.instance.i('Sync broadcast updated to $_deviceName');
      } on Exception catch (error, stackTrace) {
        LoggerService.instance.e(
          'Failed to update sync broadcast',
          error: error,
          stackTrace: stackTrace,
        );
      }
    });

    _broadcastUpdateFuture = update;
    unawaited(
      update.whenComplete(() {
        if (identical(_broadcastUpdateFuture, update)) {
          _broadcastUpdateFuture = null;
        }
      }),
    );
  }

  String _broadcastSignatureForCurrentSettings() =>
      '$_deviceName\u0000$_deviceId';

  Future<bool> _startDiscovery() async {
    try {
      _localAddresses = await _loadLocalAddresses();
      _discovery = BonsoirDiscovery(type: _serviceType);
      await _discovery!.ready;

      _discoverySubscription = _discovery!.eventStream!.listen((event) {
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
              deviceId: resolved.attributes['did'],
            ),
          );
        } else if (event.type ==
            BonsoirDiscoveryEventType.discoveryServiceLost) {
          _removePeer(event.service?.name ?? '');
        }
      });

      await _discovery!.start();
      return true;
    } on Exception catch (error, stackTrace) {
      LoggerService.instance.e(
        'Sync discovery failed',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<void> _handleIncomingData(
    List<int> data,
    TaskProvider provider,
  ) async {
    try {
      final result = await ExportImportService.importFromBytes(
        provider,
        data,
        expectedSecret: _secret,
      );
      if (result.success) {
        LoggerService.instance.i(
          'Merged sync data: ${result.tasksImported} tasks, ${result.foldersImported} folders',
        );
        _statusController.add(
          'merged:${result.tasksImported}:${result.foldersImported}',
        );
      } else {
        _statusController.add('merge_failed:${result.error}');
      }
    } on Exception catch (error, stackTrace) {
      LoggerService.instance.e(
        'Sync merge failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _addPeer(SyncPeer peer) {
    // Don't show our own device in the peers list.
    if (_isOwnPeer(peer)) return;
    _peers.removeWhere(
      (p) => p.name == peer.name && p.host == peer.host && p.port == peer.port,
    );
    _peers.add(peer);
    _peersController.add(List.unmodifiable(_peers));
  }

  /// Returns true if [peer] is this device.
  ///
  /// The primary check is the stable device ID advertised in the mDNS TXT
  /// record. If that is not available, it falls back to the listening port,
  /// local network addresses, and finally the broadcast name.
  bool _isOwnPeer(SyncPeer peer) {
    if (_deviceId.isNotEmpty && peer.deviceId == _deviceId) return true;
    if (peer.port != _actualPort) return false;
    if (peer.host == '127.0.0.1' || peer.host == 'localhost') return true;
    if (_localAddresses.contains(peer.host)) return true;
    // Fallback: exact match by broadcast name.
    return peer.name == _deviceName;
  }

  /// Loads local network interface addresses so we can recognize ourselves.
  Future<List<String>> _loadLocalAddresses() async {
    try {
      final interfaces = await NetworkInterface.list();
      return interfaces
          .expand((interface) => interface.addresses)
          .map((addr) => addr.address)
          .toList();
    } on Exception catch (error, stackTrace) {
      LoggerService.instance.w(
        'Failed to load local network interfaces',
        error: error,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  void _removePeer(String name) {
    _peers.removeWhere((p) => p.name == name);
    _peersController.add(List.unmodifiable(_peers));
  }
}
