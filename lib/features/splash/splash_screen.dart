import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/sync_service.dart';
import '../../../core/logger_service.dart';
import '../../../core/theme.dart';
import '../../../core/version_service.dart';
import '../settings/providers/settings_provider.dart';
import '../tasks/providers/task_provider.dart';
import '../tasks/screens/home_screen.dart';

/// Initial loading screen.
/// Waits for both providers to finish their async init, then fades into HomeScreen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final Future<void> _readyFuture;
  bool _updateChecked = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    final tasks = context.read<TaskProvider>();
    _readyFuture = Future.wait([settings.ready, tasks.ready]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _startSyncInBackground(settings, tasks).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          // Sync is optional and must never turn a post-frame callback into an
          // unhandled error or delay the first usable screen.
          LoggerService.instance.w(
            'Background sync startup failed',
            error: error,
            stackTrace: stackTrace,
          );
        }),
      );
    });
  }

  Future<void> _startSyncInBackground(
    SettingsProvider settings,
    TaskProvider tasks,
  ) async {
    await _readyFuture;
    if (!settings.syncEnabled) return;

    final deviceId = await settings.ensureSyncDeviceId();
    SyncService.instance.setProvider(tasks);
    SyncService.instance.setDeviceName(settings.syncDeviceName);
    SyncService.instance.setDeviceId(deviceId);
    SyncService.instance.setSecret(settings.syncSecret);
    final started = await SyncService.instance.start().timeout(
      const Duration(seconds: 8),
      onTimeout: () async {
        await SyncService.instance.stop();
        return false;
      },
    );
    if (!started && settings.syncEnabled) {
      await settings.setSyncEnabled(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _readyFuture,
      builder: (context, snapshot) {
        final isReady = snapshot.connectionState == ConnectionState.done;

        if (!isReady) {
          return const _SplashBody();
        }

        if (!_updateChecked) {
          _updateChecked = true;
          final settings = context.read<SettingsProvider>();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            VersionService.checkAndPrompt(context, settings);
          });
        }

        return const HomeScreen();
      },
    );
  }
}

class _SplashBody extends StatelessWidget {
  const _SplashBody();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? AppColors.bgDark : AppColors.bgLight;
    final textColor = isDark ? AppColors.textDark : AppColors.textLight;

    return Scaffold(
      backgroundColor: background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'ASA',
              style: TextStyle(
                color: textColor,
                fontFamily: 'Inter',
                fontSize: 48,
                fontWeight: FontWeight.w700,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
