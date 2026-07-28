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
  ThemeMode _themeMode = ThemeMode.system;
  bool _notificationsEnabled = true;
  String _languageCode = 'ru';
  double _animationSpeed = 1.0;
  double _appScale = 1.0;
  List<double> _customAnimationSpeeds = [];
  List<double> _customAppScales = [];
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
  List<double> get customAnimationSpeeds => _customAnimationSpeeds;
  List<double> get customAppScales => _customAppScales;
  String? get avatarPath => _avatarPath;
  bool get showInWidget => _showInWidget;
  WidgetDisplayMode get widgetDisplayMode => _widgetDisplayMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark ||
      (_themeMode == ThemeMode.system &&
          SchedulerBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark);

  String tr(String key) => AppStrings.get(key, _languageCode);

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeIndex = prefs.getInt('themeMode') ?? ThemeMode.system.index;
      _themeMode = ThemeMode.values[themeIndex.clamp(0, ThemeMode.values.length - 1)];
      _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
      _languageCode = prefs.getString('languageCode') ?? 'ru';
      _animationSpeed = prefs.getDouble('animationSpeed') ?? 1.0;
      _appScale = (prefs.getDouble('appScale') ?? 1.0).clamp(kAbsoluteMinAppScale, kAbsoluteMaxAppScale);
      _customAnimationSpeeds = _loadDoubleList(prefs, 'customAnimationSpeeds');
      _customAppScales = _loadDoubleList(prefs, 'customAppScales');
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

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
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

  /// Saves a custom animation speed to the history (max 3 entries, LRU),
  /// then sets it as the active speed.
  Future<void> addCustomAnimationSpeed(double speed) async {
    final clamped = speed.clamp(0.1, 5.0);
    _animationSpeed = clamped;
    _customAnimationSpeeds = _addToCustomHistory(
      _customAnimationSpeeds,
      clamped,
      const [0.5, 1.0, 2.0],
    );
    timeDilation = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('animationSpeed', clamped);
    await prefs.setStringList(
      'customAnimationSpeeds',
      _customAnimationSpeeds.map((v) => v.toString()).toList(),
    );
  }

  Future<void> setAppScale(double scale) async {
    final clamped = scale.clamp(kAbsoluteMinAppScale, kAbsoluteMaxAppScale);
    _appScale = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('appScale', clamped);
  }

  /// Saves a custom app scale to the history (max 3 entries, LRU), then
  /// sets it as the active scale.
  Future<void> addCustomAppScale(double scale, double min, double max) async {
    final clamped = scale.clamp(min, max);
    _appScale = clamped;
    _customAppScales = _addToCustomHistory(
      _customAppScales,
      clamped,
      const [0.8, 1.0, 1.2],
    );
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('appScale', clamped);
    await prefs.setStringList(
      'customAppScales',
      _customAppScales.map((v) => v.toString()).toList(),
    );
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

  /// Loads a list of doubles from [prefs] under [key].
  static List<double> _loadDoubleList(SharedPreferences prefs, String key) {
    final raw = prefs.getStringList(key);
    if (raw == null) return [];
    return raw
        .map((v) => double.tryParse(v))
        .whereType<double>()
        .toList();
  }

  /// Adds [value] to [history] at the front, removes duplicates, and keeps
  /// only the most recent [maxItems] entries. Values matching a built-in
  /// preset are not added to the history.
  static List<double> _addToCustomHistory(
    List<double> history,
    double value,
    List<double> builtInPresets, {
    int maxItems = 3,
  }) {
    final isPreset = builtInPresets.any(
      (preset) => (preset - value).abs() < 0.01,
    );
    if (isPreset) return history;

    final updated = [value, ...history.where((v) => (v - value).abs() >= 0.01)]
        .take(maxItems)
        .toList();
    return updated;
  }
}
