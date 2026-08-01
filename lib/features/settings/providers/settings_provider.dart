import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/app_strings.dart';
import '../../../core/device_info.dart';
import '../../../core/home_widget_service.dart';
import '../../../core/logger_service.dart';
import '../../../core/notification_service.dart';
import '../../../core/scale_utils.dart';
import '../../../core/theme.dart';

enum WidgetDisplayMode { activeTasks, lastFolder }

class SettingsProvider with ChangeNotifier {
  final Future<String> Function() _deviceNameProvider;

  ThemeMode _themeMode = ThemeMode.system;
  ColorPalette _colorPalette = ColorPalette.base;
  AppPalette _customPalette = AppPalette.base;
  bool _notificationsEnabled = true;
  String _languageCode = 'ru';
  double _animationSpeed = 1.0;
  double _appScale = 1.0;
  List<double> _customAnimationSpeeds = [];
  List<double> _customAppScales = [];
  String? _avatarPath;
  bool _showInWidget = true;
  WidgetDisplayMode _widgetDisplayMode = WidgetDisplayMode.activeTasks;
  bool _syncEnabled = false;
  String _syncDeviceName = 'ASA Device';
  String _syncDeviceId = '';
  Future<String>? _syncDeviceIdFuture;
  String? _syncSecret;
  bool _initialized = false;
  final _initCompleter = Completer<void>();
  Future<void> _customValuesOperation = Future<void>.value();
  Future<void> _avatarPathOperation = Future<void>.value();

  SettingsProvider({
    Future<String> Function() deviceNameProvider = getDefaultDeviceName,
  }) : _deviceNameProvider = deviceNameProvider {
    init();
  }

  bool get initialized => _initialized;
  Future<void> get ready => _initCompleter.future;

  ThemeMode get themeMode => _themeMode;
  ColorPalette get colorPalette => _colorPalette;
  AppPalette get appPalette =>
      _colorPalette == ColorPalette.custom
          ? _customPalette
          : _paletteFor(_colorPalette);
  List<Color> get customPaletteColors => _customPalette.customColors;
  bool get notificationsEnabled => _notificationsEnabled;
  String get languageCode => _languageCode;
  double get animationSpeed => _animationSpeed;
  double get appScale => _appScale;
  List<double> get customAnimationSpeeds => _customAnimationSpeeds;
  List<double> get customAppScales => _customAppScales;
  String? get avatarPath => _avatarPath;
  bool get showInWidget => _showInWidget;
  WidgetDisplayMode get widgetDisplayMode => _widgetDisplayMode;
  bool get syncEnabled => _syncEnabled;
  String get syncDeviceName => _syncDeviceName;
  String get syncDeviceId => _syncDeviceId;
  String? get syncSecret => _syncSecret;

  bool get isDarkMode =>
      _themeMode == ThemeMode.dark ||
      (_themeMode == ThemeMode.system &&
          SchedulerBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark);

  String tr(String key) => AppStrings.get(key, _languageCode);

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeIndex = prefs.getInt('themeMode') ?? ThemeMode.system.index;
      _themeMode =
          ThemeMode.values[themeIndex.clamp(0, ThemeMode.values.length - 1)];

      final savedPalette = prefs.getString('colorPalette');
      _colorPalette = _colorPaletteFromStorage(savedPalette);
      final savedCustomColors = prefs.getStringList('customPaletteColors');
      final parsedCustomColors =
          savedCustomColors == null
              ? null
              : _parseCustomColors(savedCustomColors);
      if (parsedCustomColors != null) {
        _customPalette = AppPalette.fromCustomColors(parsedCustomColors);
      }
      if (_colorPalette == ColorPalette.custom && parsedCustomColors == null) {
        _colorPalette = ColorPalette.base;
        await prefs.setString('colorPalette', ColorPalette.base.name);
        await prefs.remove('customPaletteColors');
      } else if (savedCustomColors != null && parsedCustomColors == null) {
        await prefs.remove('customPaletteColors');
      }
      AppColors.applyPalette(appPalette);

      _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
      _languageCode = prefs.getString('languageCode') ?? 'ru';
      NotificationService.setLanguage(_languageCode);
      _animationSpeed = prefs.getDouble('animationSpeed') ?? 1.0;
      _appScale = (prefs.getDouble('appScale') ?? 1.0).clamp(
        kAbsoluteMinAppScale,
        kAbsoluteMaxAppScale,
      );
      _customAnimationSpeeds = _loadDoubleList(
        prefs,
        'customAnimationSpeeds',
        excludedValues: const [0.5, 1.0, 2.0],
      );
      final savedAnimationSpeeds = prefs.getStringList('customAnimationSpeeds');
      if (savedAnimationSpeeds != null) {
        await prefs.setStringList(
          'customAnimationSpeeds',
          _customAnimationSpeeds.map((value) => value.toString()).toList(),
        );
      }
      _customAppScales = _loadDoubleList(
        prefs,
        'customAppScales',
        excludedValues: const [0.8, 1.0, 1.2],
      );
      final savedAppScales = prefs.getStringList('customAppScales');
      if (savedAppScales != null) {
        await prefs.setStringList(
          'customAppScales',
          _customAppScales.map((value) => value.toString()).toList(),
        );
      }
      _avatarPath = prefs.getString('avatarPath');
      _showInWidget = prefs.getBool('showInWidget') ?? true;
      final oldMode = prefs.getInt('widgetDisplayMode');
      if (oldMode == null || oldMode == 0 || oldMode == 1) {
        // Previous 'streak' (0) and previous 'activeTasks' (1) both map to activeTasks.
        _widgetDisplayMode = WidgetDisplayMode.activeTasks;
      } else {
        // Previous 'lastFolder' (2)
        _widgetDisplayMode = WidgetDisplayMode.lastFolder;
      }
      prefs.setInt('widgetDisplayMode', _widgetDisplayMode.index);
      _syncEnabled = prefs.getBool('syncEnabled') ?? false;
      final savedName = prefs.getString('syncDeviceName');
      _syncDeviceName =
          savedName != null && savedName.trim().isNotEmpty
              ? savedName.trim()
              : await _deviceNameProvider();
      _syncSecret = prefs.getString('syncSecret');
      LoggerService.instance.registerSecret(_syncSecret);
      if (_syncSecret != null && _syncSecret!.trim().isEmpty) {
        _syncSecret = null;
      }
      timeDilation = _animationSpeed;
      // Ensure a stable device ID exists for sync. This is a local only
      // SharedPreferences read/write and completes quickly.
      await ensureSyncDeviceId();
      _initialized = true;
      _syncWidgetSettings();
      // Defer the notification so it only fires after the provider is attached
      // to the widget tree, avoiding exceptions or unnecessary early rebuilds.
      Future.microtask(() => notifyListeners());
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

  Future<void> setColorPalette(ColorPalette palette) async {
    await ready;
    _colorPalette = palette;
    AppColors.applyPalette(appPalette);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('colorPalette', palette.name);
  }

  Future<void> setCustomPalette(List<Color> colors) async {
    await ready;
    final palette = AppPalette.fromCustomColors(colors);
    _customPalette = palette;
    _colorPalette = ColorPalette.custom;
    AppColors.applyPalette(palette);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('colorPalette', ColorPalette.custom.name);
    await prefs.setStringList(
      'customPaletteColors',
      palette.customColors.map(AppPalette.colorToHex).toList(),
    );
  }

  Future<void> toggleNotifications(bool value) async {
    if (value) {
      bool granted = true;
      if (NotificationService.isInitialized) {
        granted = await NotificationService.requestPermission();
        if (granted) {
          await NotificationService.showTestNotification();
          await NotificationService.rescheduleCachedTasks();
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
    NotificationService.setLanguage(code);
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
  Future<void> addCustomAnimationSpeed(double speed) {
    return _enqueueCustomValuesOperation(() async {
      await ready;
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
    });
  }

  Future<void> setAppScale(double scale) async {
    final clamped = scale.clamp(kAbsoluteMinAppScale, kAbsoluteMaxAppScale);
    _appScale = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('appScale', clamped);
  }

  /// Removes a saved custom animation speed. If it is active, use the normal
  /// preset so the setting remains valid after deletion.
  Future<void> removeCustomAnimationSpeed(double speed) {
    return _enqueueCustomValuesOperation(() async {
      await ready;
      final updated =
          _customAnimationSpeeds
              .where((value) => (value - speed).abs() >= 0.01)
              .toList();
      if (updated.length == _customAnimationSpeeds.length) return;

      _customAnimationSpeeds = updated;
      if ((_animationSpeed - speed).abs() < 0.01) {
        _animationSpeed = 1.0;
        timeDilation = 1.0;
      }
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('animationSpeed', _animationSpeed);
      await prefs.setStringList(
        'customAnimationSpeeds',
        _customAnimationSpeeds.map((value) => value.toString()).toList(),
      );
    });
  }

  /// Saves a custom app scale to the history (max 3 entries, LRU), then
  /// sets it as the active scale.
  Future<void> addCustomAppScale(double scale, double min, double max) {
    return _enqueueCustomValuesOperation(() async {
      await ready;
      final clamped = scale.clamp(min, max);
      _appScale = clamped;
      _customAppScales = _addToCustomHistory(_customAppScales, clamped, const [
        0.8,
        1.0,
        1.2,
      ]);
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('appScale', clamped);
      await prefs.setStringList(
        'customAppScales',
        _customAppScales.map((v) => v.toString()).toList(),
      );
    });
  }

  /// Removes a saved custom app scale. If it is active, use the default
  /// preset so the setting remains valid after deletion.
  Future<void> removeCustomAppScale(double scale) {
    return _enqueueCustomValuesOperation(() async {
      await ready;
      final updated =
          _customAppScales
              .where((value) => (value - scale).abs() >= 0.01)
              .toList();
      if (updated.length == _customAppScales.length) return;

      _customAppScales = updated;
      if ((_appScale - scale).abs() < 0.01) {
        _appScale = 1.0;
      }
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('appScale', _appScale);
      await prefs.setStringList(
        'customAppScales',
        _customAppScales.map((value) => value.toString()).toList(),
      );
    });
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

  Future<void> setSyncEnabled(bool value) async {
    _syncEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('syncEnabled', value);
  }

  Future<void> setSyncDeviceName(String name) async {
    final trimmed = name.trim();
    final prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      // When the user clears the custom name, fall back to the device name
      // and remove the saved override so the name stays dynamic.
      _syncDeviceName = await _deviceNameProvider();
      await prefs.remove('syncDeviceName');
    } else {
      _syncDeviceName = trimmed;
      await prefs.setString('syncDeviceName', _syncDeviceName);
    }
    notifyListeners();
  }

  /// Returns the stable device ID used to identify this device during sync.
  /// If no ID exists, a new UUID is generated and persisted.
  Future<String> ensureSyncDeviceId() {
    if (_syncDeviceId.isNotEmpty) return Future.value(_syncDeviceId);
    if (_syncDeviceIdFuture != null) return _syncDeviceIdFuture!;
    _syncDeviceIdFuture = _loadOrCreateDeviceId();
    _syncDeviceIdFuture!.then((_) => _syncDeviceIdFuture = null);
    return _syncDeviceIdFuture!;
  }

  Future<String> _loadOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('syncDeviceId');
    if (id == null || id.trim().isEmpty) {
      id = const Uuid().v4();
      await prefs.setString('syncDeviceId', id);
    }
    _syncDeviceId = id;
    return id;
  }

  Future<void> setSyncSecret(String? secret) async {
    final trimmed = secret?.trim();
    LoggerService.instance.registerSecret(trimmed);
    _syncSecret = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (_syncSecret == null) {
      await prefs.remove('syncSecret');
    } else {
      await prefs.setString('syncSecret', _syncSecret!);
    }
  }

  String widgetModeLabel(WidgetDisplayMode mode) {
    switch (mode) {
      case WidgetDisplayMode.activeTasks:
        return tr('widget_mode_active_tasks');
      case WidgetDisplayMode.lastFolder:
        return tr('widget_mode_last_folder');
    }
  }

  static ColorPalette _colorPaletteFromStorage(String? value) {
    return ColorPalette.values.firstWhere(
      (palette) => palette.name == value,
      orElse: () => ColorPalette.base,
    );
  }

  static List<Color>? _parseCustomColors(List<String> values) {
    if (values.isEmpty || values.length > 3) return null;
    final colors = values.map(AppPalette.tryParseHex).toList();
    if (colors.any((color) => color == null)) return null;
    return colors.cast<Color>();
  }

  static AppPalette _paletteFor(ColorPalette palette) {
    switch (palette) {
      case ColorPalette.base:
        return AppPalette.base;
      case ColorPalette.ocean:
        return AppPalette.ocean;
      case ColorPalette.custom:
        return AppPalette.base;
    }
  }

  void _syncWidgetSettings() {
    HomeWidgetService.updateSettings(
      enabled: _showInWidget,
      mode: _widgetDisplayMode,
    );
  }

  /// Persists [path] in FIFO order and returns the path replaced by this
  /// operation. The returned value lets callers clean up the correct previous
  /// file even when multiple avatar selections are started concurrently.
  Future<String?> setAvatarPath(String? path) {
    final next = _avatarPathOperation.then((_) => _persistAvatarPath(path));
    _avatarPathOperation = next.catchError(
      (Object error, StackTrace stackTrace) => null,
    );
    return next;
  }

  Future<String?> _persistAvatarPath(String? path) async {
    final previousPath = _avatarPath;
    _avatarPath = path;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (path == null) {
        await prefs.remove('avatarPath');
      } else {
        await prefs.setString('avatarPath', path);
      }
      return previousPath;
    } catch (_) {
      _avatarPath = previousPath;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _enqueueCustomValuesOperation(
    Future<void> Function() operation,
  ) {
    final next = _customValuesOperation.then((_) => operation());
    _customValuesOperation = next.catchError((_) {});
    return next;
  }

  /// Loads a list of doubles from [prefs] under [key].
  static List<double> _loadDoubleList(
    SharedPreferences prefs,
    String key, {
    List<double> excludedValues = const [],
  }) {
    final raw = prefs.getStringList(key);
    if (raw == null) return [];
    return raw
        .map((v) => double.tryParse(v))
        .whereType<double>()
        .where(
          (value) => excludedValues.every(
            (excluded) => (value - excluded).abs() >= 0.01,
          ),
        )
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

    final updated =
        [
          value,
          ...history.where((v) => (v - value).abs() >= 0.01),
        ].take(maxItems).toList();
    return updated;
  }
}
