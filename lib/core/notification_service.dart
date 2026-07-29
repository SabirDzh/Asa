import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show
        AndroidFlutterLocalNotificationsPlugin,
        AndroidInitializationSettings,
        AndroidNotificationDetails,
        DarwinInitializationSettings,
        DarwinNotificationDetails,
        FlutterLocalNotificationsPlugin,
        IOSFlutterLocalNotificationsPlugin,
        InitializationSettings,
        NotificationDetails,
        Priority,
        Importance;

/// Thin wrapper around flutter_local_notifications.
/// Handles initialization, permission requests, and a simple test notification.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  /// Initializes the plugin. Must be called before any other method.
  static Future<void> init() async {
    if (kIsWeb) return;

    const android = AndroidInitializationSettings('@drawable/ic_notification');
    const iOS = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: iOS);
    await _plugin.initialize(settings);
    _initialized = true;
  }

  /// Requests notification permission from the user.
  /// Returns true if granted (or if no request is needed).
  static Future<bool> requestPermission() async {
    if (kIsWeb || !_initialized) return false;

    if (Platform.isAndroid) {
      final android =
          _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? false;
    }

    if (Platform.isIOS) {
      final iOS =
          _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >();
      final granted = await iOS?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    return false;
  }

  /// Shows a one-time test notification so the user can verify it works.
  static Future<void> showTestNotification() async {
    if (kIsWeb || !_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      'asa_test_channel',
      'Taskone Test',
      channelDescription: 'Test notifications from Taskone',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      showWhen: true,
    );

    const iOSDetails = DarwinNotificationDetails();

    await _plugin.show(
      0,
      'Taskone',
      'Уведомления включены',
      const NotificationDetails(android: androidDetails, iOS: iOSDetails),
    );
  }

  /// Cancels all active notifications.
  static Future<void> cancelAll() async {
    if (kIsWeb || !_initialized) return;
    await _plugin.cancelAll();
  }
}
