import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme.dart';
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

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    final tasks = context.read<TaskProvider>();
    _readyFuture = Future.wait([settings.ready, tasks.ready]);
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
