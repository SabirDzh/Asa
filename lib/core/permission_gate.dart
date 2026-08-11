import 'dart:async';

import 'package:flutter/material.dart';

import '../features/splash/setup_screen.dart';
import 'device_permissions.dart';

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

  const PermissionGate({super.key, required this.child});

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate>
    with WidgetsBindingObserver {
  PermissionState? _state;
  bool _loading = true;

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

  Future<void> _refreshPermissionState() async {
    final state = await DevicePermissions.getPermissionState();
    if (!mounted) return;
    setState(() {
      _state = state;
      _loading = false;
    });
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

    return widget.child;
  }
}
