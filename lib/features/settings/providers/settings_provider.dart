import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/app_strings.dart';
import '../../../core/home_widget_service.dart';
import '../../../core/notification_service.dart';
import '../../../core/scale_utils.dart';

enum WidgetDisplayMode { streak, activeTasks, lastFolder }

class SettingsProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark;
  bool _notificationsEnabled = true;
  String _languageCode = 'ru';
  double _animationSpeed = 1.0;
  double _appScale = 1.0;
  String? _avatarPath;
  bool _showInWidget = true;
  WidgetDisplayMode _widgetDisplayMode = WidgetDisplayMode.streak;
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
  double get appScale => _appScale;
  String? get avatarPath => _avatarPath;
  bool get showInWidget => _showInWidget;
  WidgetDisplayMode get widgetDisplayMode => _widgetDisplayMode;

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
      _appScale = (prefs.getDouble('appScale') ?? 1.0).clamp(kMinAppScale, kAbsoluteMaxAppScale);
      _avatarPath = prefs.getString('avatarPath');
      _showInWidget = prefs.getBool('showInWidget') ?? true;
      _widgetDisplayMode = WidgetDisplayMode.values[
        (prefs.getInt('widgetDisplayMode') ?? 0).clamp(0, WidgetDisplayMode.values.length - 1)
      ];
      timeDilation = _animationSpeed;
      _initialized = true;
      _syncWidgetSettings();
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

  Future<void> setAppScale(double scale) async {
    final clamped = scale.clamp(kMinAppScale, kAbsoluteMaxAppScale);
    _appScale = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('appScale', clamped);
  }

  Future<void> setShowInWidget(bool value) async {
    _showInWidget = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showInWidget', value);
    _syncWidgetSettings();
  }

  Future<void> setWidgetDisplayMode(WidgetDisplayMode mode) async {
    _widgetDisplayMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('widgetDisplayMode', mode.index);
    _syncWidgetSettings();
  }

  String widgetModeLabel(WidgetDisplayMode mode) {
    switch (mode) {
      case WidgetDisplayMode.streak:
        return tr('widget_mode_streak');
      case WidgetDisplayMode.activeTasks:
        return tr('widget_mode_active_tasks');
      case WidgetDisplayMode.lastFolder:
        return tr('widget_mode_last_folder');
    }
  }

  void _syncWidgetSettings() {
    HomeWidgetService.updateSettings(
      enabled: _showInWidget,
      mode: _widgetDisplayMode,
    );
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
