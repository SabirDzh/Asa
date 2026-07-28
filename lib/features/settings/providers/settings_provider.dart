import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/app_strings.dart';
import '../../../core/notification_service.dart';

class SettingsProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark;
  bool _notificationsEnabled = true;
  String _languageCode = 'ru';
  double _animationSpeed = 1.0;
  String? _avatarPath;
  bool _initialized = false;
  final _initCompleter = Completer<void>();

  SettingsProvider() {
    init();
  }

  bool get initialized => _initialized;
  Future<void> get ready => _initCompleter.future;

  ThemeMode get themeMode => _themeMode;
  bool get notificationsEnabled => _notificationsEnabled;
  String get languageCode => _languageCode;
  double get animationSpeed => _animationSpeed;
  String? get avatarPath => _avatarPath;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  String tr(String key) => AppStrings.get(key, _languageCode);

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDark = prefs.getBool('isDarkMode') ?? true;
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
      _languageCode = prefs.getString('languageCode') ?? 'ru';
      _animationSpeed = prefs.getDouble('animationSpeed') ?? 1.0;
      _avatarPath = prefs.getString('avatarPath');
      timeDilation = _animationSpeed;
      _initialized = true;
      notifyListeners();
    } finally {
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
    }
  }

  Future<void> toggleTheme() async {
    _themeMode =
        _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDarkMode);
  }

  Future<void> toggleNotifications(bool value) async {
    if (value) {
      bool granted = true;
      if (NotificationService.isInitialized) {
        granted = await NotificationService.requestPermission();
        if (granted) {
          await NotificationService.showTestNotification();
        }
      }
      _notificationsEnabled = granted;
    } else {
      _notificationsEnabled = false;
      if (NotificationService.isInitialized) {
        await NotificationService.cancelAll();
      }
    }

    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notificationsEnabled', _notificationsEnabled);
  }

  Future<void> setLanguage(String code) async {
    if (code != 'ru' && code != 'en') return;
    _languageCode = code;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languageCode', code);
  }

  Future<void> setAnimationSpeed(double speed) async {
    _animationSpeed = speed;
    timeDilation = speed;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('animationSpeed', speed);
  }

  Future<void> setAvatarPath(String? path) async {
    _avatarPath = path;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove('avatarPath');
    } else {
      await prefs.setString('avatarPath', path);
    }
  }
}
