import 'dart:async';

import 'package:flutter/material.dart';

import '../features/splash/setup_screen.dart';
import 'device_permissions.dart';
import 'logger_service.dart';

/// Single source of truth for background-reliability permission gating.
///
/// Evaluates [DevicePermissions.getPermissionState] on initial load (showing a
/// clean loading indicator to avoid UI flicker) and listens to
/// [AppLifecycleState.resumed] to re-check state whenever the app resumes.
///
/// If any required permission or setting is missing, displays [SetupScreen]
/// and blocks access to [child] until [PermissionState.isComplete] is true.
class PermissionGate extends StatefulWidget {
  final Widget child;
  final Future<void> Function()? onReady;

  const PermissionGate({super.key, required this.child, this.onReady});

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate>
    with WidgetsBindingObserver {
  PermissionState? _state;
  bool _loading = true;
  bool _readyCallbackScheduled = false;
  Future<void>? _refreshFuture;
  int _refreshGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshPermissionState());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPermissionState());
    }
  }

  Future<void> _refreshPermissionState() {
    final previous = _refreshFuture ?? Future<void>.value();
    final generation = ++_refreshGeneration;
    final refresh = previous.then((_) async {
      final state = await DevicePermissions.getPermissionState();
      if (!mounted || generation != _refreshGeneration) return;
      setState(() {
        _state = state;
        _loading = false;
      });
      if (!state.isComplete) _readyCallbackScheduled = false;
    });
    final guarded = refresh.catchError((Object error, StackTrace stackTrace) {
      if (!mounted || generation != _refreshGeneration) return;
      setState(() {
        _state = const PermissionState(
          notificationsGranted: false,
          exactAlarmGranted: false,
          batteryOptimizationDisabled: false,
          autoStartGranted: false,
          autoStartSupported: false,
          permissionCheckFailed: true,
        );
        _loading = false;
        _readyCallbackScheduled = false;
      });
      // The setup screen exposes a retry action; preserve the error only in
      // diagnostics so a transient platform failure cannot leave a spinner.
      LoggerService.instance.w(
        'Permission state refresh failed',
        error: error,
        stackTrace: stackTrace,
      );
    });
    _refreshFuture = guarded;
    unawaited(
      guarded.then<void>((_) {
        if (identical(_refreshFuture, guarded)) _refreshFuture = null;
      }),
    );
    return guarded;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _state == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    if (!_state!.isComplete) {
      return SetupScreen(
        initialState: _state,
        onPermissionsResolved: _refreshPermissionState,
      );
    }

    if (!_readyCallbackScheduled && widget.onReady != null) {
      _readyCallbackScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(widget.onReady!());
      });
    }

    return widget.child;
  }
}
