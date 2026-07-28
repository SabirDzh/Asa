import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppStrings {
  static final Map<String, Map<String, String>> _localizedValues = {
    'ru': {
      'search': 'Поиск',
      'tasks': 'Задачи',
      'settings': 'Настройки',
      'create_folder': 'Создать папку',
      'create_task': 'Создать задачу',
      'new_task': 'новая задача...',
      'new_folder': 'новая папка...',
      'delete': 'Удалить',
      'edit': 'Редактировать',
      'edit_task': 'Редактировать задачу',
      'edit_folder': 'Редактировать папку',
      'delete_folder': 'Удалить папку',
      'cancel': 'Отмена',
      'save': 'Сохранить',
      'empty_list': 'Список пуст',
      'nothing_found': 'Ничего не найдено',
      'filters': 'Фильтры',
      'filter_all': 'Все',
      'filter_active': 'В процессе',
      'filter_completed': 'Завершенные',
      'filter_folders': 'Только папки',
      'change_avatar': 'Сменить аватар',
      'notifications': 'Уведомления',
      'theme': 'Тема приложения',
      'data_management': 'Управление данными',
      'language': 'Язык',
      'lang_name': 'русский',
      'animation_speed': 'Плавность анимации',
      'speed_fast': 'Быстро',
      'speed_normal': 'Обычно',
      'speed_slow': 'Медленно',
      'speed_custom': 'Своя',
      'about': 'О приложении',
      'about_title': 'О приложении ASA',
      'about_desc': 'ASA — современный менеджер задач с поддержкой папок и гибкой фильтрацией.',
      'version': 'Версия 1.0.0',
      'clear_tasks': 'Очистить все задачи',
      'clear_folders': 'Очистить все папки',
      'clear_all': 'Сбросить все данные',
      'confirm_clear': 'Вы уверены?',
      'folder_title': 'Папка: ',
      'no_tasks_in_folder': 'В этой папке пока нет задач',
      'add_task_to_folder': 'Добавить задачу в папку',
      'back': 'Назад',
      'confirm_delete_title': 'Удаление',
      'confirm_delete_content': 'Вы уверены, что хотите удалить это?',
    },
    'en': {
      'search': 'Search',
      'tasks': 'Tasks',
      'settings': 'Settings',
      'create_folder': 'Create folder',
      'create_task': 'Create task',
      'new_task': 'new task...',
      'new_folder': 'new folder...',
      'delete': 'Delete',
      'edit': 'Edit',
      'edit_task': 'Edit task',
      'edit_folder': 'Edit folder',
      'delete_folder': 'Delete folder',
      'cancel': 'Cancel',
      'save': 'Save',
      'empty_list': 'List is empty',
      'nothing_found': 'Nothing found',
      'filters': 'Filters',
      'filter_all': 'All',
      'filter_active': 'In progress',
      'filter_completed': 'Completed',
      'filter_folders': 'Folders only',
      'change_avatar': 'Change avatar',
      'notifications': 'Notifications',
      'theme': 'App theme',
      'data_management': 'Data management',
      'language': 'Language',
      'lang_name': 'English',
      'animation_speed': 'Animation speed',
      'speed_fast': 'Fast',
      'speed_normal': 'Normal',
      'speed_slow': 'Slow',
      'speed_custom': 'Custom',
      'about': 'About app',
      'about_title': 'About ASA App',
      'about_desc': 'ASA is a modern task manager supporting folders and flexible filtering.',
      'version': 'Version 1.0.0',
      'clear_tasks': 'Clear all tasks',
      'clear_folders': 'Clear all folders',
      'clear_all': 'Reset all data',
      'confirm_clear': 'Are you sure?',
      'folder_title': 'Folder: ',
      'no_tasks_in_folder': 'No tasks in this folder yet',
      'add_task_to_folder': 'Add task to folder',
      'back': 'Back',
      'confirm_delete_title': 'Delete',
      'confirm_delete_content': 'Are you sure you want to delete this?',
    },
  };

  static String get(String key, String lang) {
    return _localizedValues[lang]?[key] ?? _localizedValues['ru']?[key] ?? key;
  }
}

class SettingsProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark;
  bool _notificationsEnabled = true;
  String _languageCode = 'ru';
  double _animationSpeed = 1.0;
  String? _avatarPath;

  SettingsProvider() {
    _loadSettings();
  }

  ThemeMode get themeMode => _themeMode;
  bool get notificationsEnabled => _notificationsEnabled;
  String get languageCode => _languageCode;
  double get animationSpeed => _animationSpeed;
  String? get avatarPath => _avatarPath;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  String tr(String key) => AppStrings.get(key, _languageCode);

  void _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkMode') ?? true;
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
    _languageCode = prefs.getString('languageCode') ?? 'ru';
    _animationSpeed = prefs.getDouble('animationSpeed') ?? 1.0;
    _avatarPath = prefs.getString('avatarPath');
    timeDilation = _animationSpeed;
    notifyListeners();
  }

  void toggleTheme() async {
    _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDarkMode);
  }

  void toggleNotifications(bool value) async {
    _notificationsEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notificationsEnabled', value);
  }

  void setLanguage(String code) async {
    if (code != 'ru' && code != 'en') return;
    _languageCode = code;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languageCode', code);
  }

  void setAnimationSpeed(double speed) async {
    _animationSpeed = speed;
    timeDilation = speed;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('animationSpeed', speed);
  }

  void setAvatarPath(String? path) async {
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
