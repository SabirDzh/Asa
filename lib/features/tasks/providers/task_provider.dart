import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task_model.dart';
import 'package:uuid/uuid.dart';

enum TaskFilter { all, active, completed, foldersOnly }

class TaskProvider with ChangeNotifier {
  final _uuid = const Uuid();
  final List<TaskItem> _tasks = [];
  final List<FolderItem> _folders = [];

  String _searchQuery = '';
  TaskFilter _filter = TaskFilter.all;
  int _streakCount = 1;

  TaskProvider() {
    initData();
  }

  Future<void> initData() async {
    await _loadFromPrefs();
    await checkDailyStreak();
  }

  List<TaskItem> get tasks => _tasks;
  List<FolderItem> get folders => _folders;
  String get searchQuery => _searchQuery;
  TaskFilter get filter => _filter;
  int get streakCount => _streakCount;

  void setSearchQuery(String query) {
    _searchQuery = query.trim().toLowerCase();
    notifyListeners();
  }

  void setFilter(TaskFilter filter) {
    _filter = filter;
    notifyListeners();
  }

  // ── Persistence methods ─────────────────────────────────────
  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tasksJson = jsonEncode(_tasks.map((t) => t.toJson()).toList());
      final foldersJson = jsonEncode(_folders.map((f) => f.toJson()).toList());
      await prefs.setString('saved_tasks', tasksJson);
      await prefs.setString('saved_folders', foldersJson);
    } catch (_) {}
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tasksStr = prefs.getString('saved_tasks');
      final foldersStr = prefs.getString('saved_folders');

      if (tasksStr != null && tasksStr.isNotEmpty) {
        final List decoded = jsonDecode(tasksStr);
        _tasks.clear();
        _tasks.addAll(decoded.map((e) => TaskItem.fromJson(e)));
      }

      if (foldersStr != null && foldersStr.isNotEmpty) {
        final List decoded = jsonDecode(foldersStr);
        _folders.clear();
        _folders.addAll(decoded.map((e) => FolderItem.fromJson(e)));
      }
    } catch (_) {}
  }

  // ── Daily streak check logic ────────────────────────────────
  Future<void> checkDailyStreak() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    
    final lastLoginStr = prefs.getString('lastLoginDate');
    int currentStreak = prefs.getInt('streakCount') ?? 1;

    if (lastLoginStr != null && lastLoginStr.isNotEmpty) {
      try {
        final parts = lastLoginStr.split('-');
        final lastDate = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        final todayDate = DateTime(now.year, now.month, now.day);
        final daysDiff = todayDate.difference(lastDate).inDays;

        if (daysDiff == 1) {
          currentStreak += 1;
        } else if (daysDiff == 2) {
        } else if (daysDiff == 3) {
          currentStreak = (currentStreak - 1).clamp(1, 9999);
        } else if (daysDiff >= 4) {
          currentStreak = 1;
        }
      } catch (_) {
        currentStreak = 1;
      }
    }

    _streakCount = currentStreak;
    await prefs.setString('lastLoginDate', todayStr);
    await prefs.setInt('streakCount', _streakCount);

    final streakFolderName = 'День $_streakCount';
    final hasStreakFolder = _folders.any((f) => f.name == streakFolderName && f.isSystemStreak);

    if (!hasStreakFolder) {
      _folders.insert(
        0,
        FolderItem(
          id: 'streak_$_streakCount',
          name: streakFolderName,
          isSystemStreak: true,
          parentFolderId: null,
        ),
      );
      await _saveToPrefs();
    }

    notifyListeners();
  }

  // Root level folders (parentFolderId == null)
  List<FolderItem> get filteredFolders {
    if (_filter == TaskFilter.completed) return [];
    return _folders.where((f) {
      if (f.parentFolderId != null) return false;
      if (_searchQuery.isEmpty) return true;
      return f.name.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  // Subfolders inside a specific parent folder
  List<FolderItem> getSubfolders(String parentFolderId) {
    return _folders.where((f) {
      if (f.parentFolderId != parentFolderId) return false;
      if (_searchQuery.isEmpty) return true;
      return f.name.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  List<TaskItem> get filteredInProgressTasks {
    if (_filter == TaskFilter.completed || _filter == TaskFilter.foldersOnly) return [];
    return _tasks.where((t) {
      if (t.isCompleted) return false;
      if (_searchQuery.isEmpty) return true;
      return t.title.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  List<TaskItem> get filteredCompletedTasks {
    if (_filter == TaskFilter.active || _filter == TaskFilter.foldersOnly) return [];
    return _tasks.where((t) {
      if (!t.isCompleted) return false;
      if (_searchQuery.isEmpty) return true;
      return t.title.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  List<TaskItem> getFolderTasks(String folderId) {
    return _tasks.where((t) => t.folderId == folderId).toList();
  }

  // ── Drag & Move methods ─────────────────────────────────────
  void moveTaskToFolder(String taskId, String? targetFolderId) {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      _tasks[index].folderId = targetFolderId;
      notifyListeners();
      _saveToPrefs();
    }
  }

  void moveFolderToFolder(String folderId, String? targetParentFolderId) {
    if (folderId == targetParentFolderId) return;
    final index = _folders.indexWhere((f) => f.id == folderId);
    if (index != -1 && !_folders[index].isSystemStreak) {
      _folders[index].parentFolderId = targetParentFolderId;
      notifyListeners();
      _saveToPrefs();
    }
  }

  void reorderRootFolders(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final rootList = filteredFolders;
    if (oldIndex >= 0 && oldIndex < rootList.length && newIndex >= 0 && newIndex < rootList.length) {
      final item = rootList.removeAt(oldIndex);
      rootList.insert(newIndex, item);

      // Rebuild main list
      final nonRoots = _folders.where((f) => f.parentFolderId != null).toList();
      _folders.clear();
      _folders.addAll(rootList);
      _folders.addAll(nonRoots);
      notifyListeners();
      _saveToPrefs();
    }
  }

  void reorderFolderTasks(String folderId, int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final folderTasks = getFolderTasks(folderId);
    if (oldIndex >= 0 && oldIndex < folderTasks.length && newIndex >= 0 && newIndex < folderTasks.length) {
      final item = folderTasks.removeAt(oldIndex);
      folderTasks.insert(newIndex, item);

      final otherTasks = _tasks.where((t) => t.folderId != folderId).toList();
      _tasks.clear();
      _tasks.addAll(otherTasks);
      _tasks.addAll(folderTasks);
      notifyListeners();
      _saveToPrefs();
    }
  }

  void addTask(String title, {String? folderId}) {
    if (title.isEmpty) return;
    if (title.length > 250) {
      throw Exception('Название длиннее 250 символов');
    }
    _tasks.add(TaskItem(id: _uuid.v4(), title: title, folderId: folderId));
    notifyListeners();
    _saveToPrefs();
  }

  void toggleTask(String id) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index != -1) {
      _tasks[index].isCompleted = !_tasks[index].isCompleted;
      notifyListeners();
      _saveToPrefs();
    }
  }

  void removeTask(String id) {
    _tasks.removeWhere((t) => t.id == id);
    notifyListeners();
    _saveToPrefs();
  }
  
  void updateTask(String id, String newTitle) {
    if (newTitle.length > 250) {
      throw Exception('Название длиннее 250 символов');
    }
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index != -1) {
      _tasks[index].title = newTitle;
      notifyListeners();
      _saveToPrefs();
    }
  }

  void addFolder(String name, {String? parentFolderId}) {
    if (name.isEmpty) return;
    if (name.length > 250) {
      throw Exception('Название длиннее 250 символов');
    }
    _folders.add(FolderItem(
      id: _uuid.v4(),
      name: name,
      parentFolderId: parentFolderId,
    ));
    notifyListeners();
    _saveToPrefs();
  }
  
  void updateFolder(String id, String newName) {
    final index = _folders.indexWhere((f) => f.id == id);
    if (index != -1 && !_folders[index].isSystemStreak) {
      if (newName.length > 250) {
        throw Exception('Название длиннее 250 символов');
      }
      _folders[index].name = newName;
      notifyListeners();
      _saveToPrefs();
    }
  }

  void removeFolder(String id) {
    final index = _folders.indexWhere((f) => f.id == id);
    if (index != -1 && !_folders[index].isSystemStreak) {
      final childFolders = _folders.where((f) => f.parentFolderId == id).map((f) => f.id).toList();
      for (final childId in childFolders) {
        removeFolder(childId);
      }
      _folders.removeAt(index);
      _tasks.removeWhere((t) => t.folderId == id);
      notifyListeners();
      _saveToPrefs();
    }
  }

  void clearAllTasks() {
    _tasks.clear();
    notifyListeners();
    _saveToPrefs();
  }

  void clearAllFolders() {
    _folders.removeWhere((f) => !f.isSystemStreak);
    _tasks.removeWhere((t) => t.folderId != null);
    notifyListeners();
    _saveToPrefs();
  }

  void clearAllData() {
    _tasks.clear();
    _folders.removeWhere((f) => !f.isSystemStreak);
    notifyListeners();
    _saveToPrefs();
  }
}
