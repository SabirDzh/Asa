import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task_model.dart';
import 'package:uuid/uuid.dart';

import '../../../core/home_widget_service.dart';

enum TaskFilter { all, active, completed, foldersOnly }

class TaskProvider with ChangeNotifier {
  final _uuid = const Uuid();
  final List<TaskItem> _tasks = [];
  final List<FolderItem> _folders = [];
  final _initCompleter = Completer<void>();

  String _searchQuery = '';
  TaskFilter _filter = TaskFilter.all;
  int _streakCount = 1;
  int _foldersVersion = 0;
  String? _lastViewedFolderName;

  TaskProvider() {
    initData();
  }

  /// Resolves once initial data loading (and streak recalculation) is done.
  Future<void> get ready => _initCompleter.future;

  Future<void> initData() async {
    try {
      await _loadFromPrefs();
      await checkDailyStreak();
    } finally {
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
    }
  }

  /// Active (non-deleted) tasks.
  List<TaskItem> get tasks => List.unmodifiable(_tasks.where((t) => !t.isDeleted));

  /// Active (non-deleted) folders, including the system streak folder.
  List<FolderItem> get folders => List.unmodifiable(_folders.where((f) => !f.isDeleted));
  String get searchQuery => _searchQuery;
  TaskFilter get filter => _filter;
  int get streakCount => _streakCount;
  int get foldersVersion => _foldersVersion;
  String? get lastViewedFolderName => _lastViewedFolderName;

  void setSearchQuery(String query) {
    _searchQuery = query.trim().toLowerCase();
    notifyListeners();
  }

  void setFilter(TaskFilter filter) {
    _filter = filter;
    notifyListeners();
  }

  void setLastViewedFolderName(String? name) {
    _lastViewedFolderName = name;
  }

  // ── Persistence methods ─────────────────────────────────────
  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tasksJson = jsonEncode(_tasks.map((t) => t.toJson()).toList());
      final foldersJson = jsonEncode(_folders.map((f) => f.toJson()).toList());
      await prefs.setString('saved_tasks', tasksJson);
      await prefs.setString('saved_folders', foldersJson);
      HomeWidgetService.updateData(this);
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
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final lastLoginStr = prefs.getString('lastLoginDate');
    int currentStreak = prefs.getInt('streakCount') ?? 1;

    if (lastLoginStr != null && lastLoginStr.isNotEmpty) {
      try {
        final parts = lastLoginStr.split('-');
        final lastDate = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        final todayDate = DateTime(now.year, now.month, now.day);
        final daysDiff = todayDate.difference(lastDate).inDays;

        if (daysDiff == 1) {
          currentStreak += 1;
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

    _folders.removeWhere((f) => f.isSystemStreak);

    final streakFolderName = 'День $_streakCount';
    _folders.insert(
      0,
      FolderItem(
        id: 'streak_$_streakCount',
        name: streakFolderName,
        isSystemStreak: true,
        parentFolderId: null,
      ),
    );
    _foldersVersion++;
    await _saveToPrefs();
    notifyListeners();
  }

  // Root level folders (parentFolderId == null)
  List<FolderItem> get filteredFolders {
    if (_filter == TaskFilter.completed) return [];
    return _folders.where((f) {
      if (f.isDeleted || f.parentFolderId != null) {
        return false;
      }
      if (_searchQuery.isEmpty) {
        return true;
      }
      return f.name.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  // Subfolders inside a specific parent folder
  List<FolderItem> getSubfolders(String parentFolderId) {
    return _folders.where((f) {
      if (f.isDeleted || f.parentFolderId != parentFolderId) {
        return false;
      }
      if (_searchQuery.isEmpty) {
        return true;
      }
      return f.name.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  List<TaskItem> get filteredInProgressTasks {
    if (_filter == TaskFilter.completed || _filter == TaskFilter.foldersOnly) {
      return [];
    }
    return _tasks.where((t) {
      if (t.isDeleted || t.isCompleted) return false;
      if (_searchQuery.isEmpty) return true;
      return t.title.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  List<TaskItem> get filteredCompletedTasks {
    if (_filter == TaskFilter.active || _filter == TaskFilter.foldersOnly) {
      return [];
    }
    return _tasks.where((t) {
      if (t.isDeleted || !t.isCompleted) return false;
      if (_searchQuery.isEmpty) return true;
      return t.title.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  List<TaskItem> getFolderTasks(String folderId) {
    return _tasks.where((t) => t.folderId == folderId && !t.isDeleted).toList();
  }

  List<TaskItem> get allTasks => List.unmodifiable(_tasks);

  // ── Drag & Move methods ─────────────────────────────────────
  void moveTaskToFolder(String taskId, String? targetFolderId) {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      _tasks[index] = _tasks[index].copyWith(folderId: targetFolderId, updatedAt: DateTime.now());
      notifyListeners();
      _saveToPrefs();
    }
  }

  void moveFolderToFolder(String folderId, String? targetParentFolderId) {
    if (folderId == targetParentFolderId) return;
    final index = _folders.indexWhere((f) => f.id == folderId);
    if (index != -1 && !_folders[index].isSystemStreak) {
      _folders[index] = _folders[index].copyWith(parentFolderId: targetParentFolderId, updatedAt: DateTime.now());
      _foldersVersion++;
      notifyListeners();
      _saveToPrefs();
    }
  }

  void reorderRootFolders(int oldIndex, int newIndex) {
    if (oldIndex < 0 || newIndex < 0) return;
    // Reordering a filtered/searched list is ambiguous and can cause data
    // loss, so only reorder when the full root list is visible.
    if (_searchQuery.isNotEmpty || _filter != TaskFilter.all) return;

    final rootList = _folders.where((f) => f.parentFolderId == null).toList();
    if (oldIndex >= rootList.length || newIndex >= rootList.length) return;

    final item = rootList.removeAt(oldIndex);
    rootList.insert(newIndex, item);

    final rootIds = rootList.map((f) => f.id).toSet();
    final newFolders = <FolderItem>[
      ...rootList,
      ..._folders.where((f) => !rootIds.contains(f.id)),
    ];

    _folders
      ..clear()
      ..addAll(newFolders);
    _foldersVersion++;
    notifyListeners();
    _saveToPrefs();
  }

  void reorderFolderTasks(String folderId, int oldIndex, int newIndex) {
    final folderTasks = _tasks.where((t) => t.folderId == folderId).toList();
    if (oldIndex < 0 ||
        newIndex < 0 ||
        oldIndex >= folderTasks.length ||
        newIndex >= folderTasks.length) {
      return;
    }

    final item = folderTasks.removeAt(oldIndex);
    folderTasks.insert(newIndex, item);

    final taskIdsInFolder = folderTasks.map((t) => t.id).toSet();
    final newTasks = <TaskItem>[
      ..._tasks.where((t) => !taskIdsInFolder.contains(t.id)),
      ...folderTasks,
    ];

    _tasks
      ..clear()
      ..addAll(newTasks);
    notifyListeners();
    _saveToPrefs();
  }

  void addTask(String title, {String? folderId}) {
    if (title.isEmpty) return;
    if (title.length > 250) {
      throw Exception('Название длиннее 250 символов');
    }
    _tasks.add(TaskItem(id: _uuid.v4(), title: title, folderId: folderId, updatedAt: DateTime.now()));
    notifyListeners();
    _saveToPrefs();
  }

  /// Adds a raw [task] directly, used by import/sync flows.
  void addTaskRaw(TaskItem task) {
    _tasks.add(task);
    notifyListeners();
    _saveToPrefs();
  }

  /// Upserts a task during import/sync, updating the existing record if it
  /// already exists. Returns true if the item was changed.
  bool upsertTask(TaskItem task) {
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index == -1) {
      _tasks.add(task);
      return true;
    }
    if (task.updatedAt.isAfter(_tasks[index].updatedAt)) {
      _tasks[index] = task;
      return true;
    }
    return false;
  }

  void toggleTask(String id) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index != -1) {
      _tasks[index] = _tasks[index].copyWith(
        isCompleted: !_tasks[index].isCompleted,
        updatedAt: DateTime.now(),
      );
      notifyListeners();
      _saveToPrefs();
    }
  }

  void removeTask(String id) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index != -1) {
      _tasks[index] = _tasks[index].copyWith(isDeleted: true, updatedAt: DateTime.now());
      notifyListeners();
      _saveToPrefs();
    }
  }

  void updateTask(String id, String newTitle) {
    if (newTitle.length > 250) {
      throw Exception('Название длиннее 250 символов');
    }
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index != -1) {
      _tasks[index] = _tasks[index].copyWith(title: newTitle, updatedAt: DateTime.now());
      notifyListeners();
      _saveToPrefs();
    }
  }

  void addFolder(String name, {String? parentFolderId}) {
    if (name.isEmpty) return;
    if (name.length > 250) {
      throw Exception('Название длиннее 250 символов');
    }
    _folders.add(
      FolderItem(id: _uuid.v4(), name: name, parentFolderId: parentFolderId, updatedAt: DateTime.now()),
    );
    _foldersVersion++;
    notifyListeners();
    _saveToPrefs();
  }

  /// Adds a raw [folder] directly, used by import/sync flows.
  void addFolderRaw(FolderItem folder) {
    _folders.add(folder);
    _foldersVersion++;
    notifyListeners();
    _saveToPrefs();
  }

  /// Upserts a folder during import/sync, updating the existing record if it
  /// already exists. Returns true if the item was changed.
  bool upsertFolder(FolderItem folder) {
    final index = _folders.indexWhere((f) => f.id == folder.id);
    if (index == -1) {
      _folders.add(folder);
      return true;
    }
    if (folder.updatedAt.isAfter(_folders[index].updatedAt)) {
      _folders[index] = folder;
      return true;
    }
    return false;
  }

  /// Notifies listeners and persists the current state. Called after bulk
  /// operations such as import/sync merges.
  Future<void> persist() async {
    _foldersVersion++;
    notifyListeners();
    await _saveToPrefs();
  }

  void updateFolder(String id, String newName) {
    final index = _folders.indexWhere((f) => f.id == id);
    if (index != -1 && !_folders[index].isSystemStreak) {
      if (newName.length > 250) {
        throw Exception('Название длиннее 250 символов');
      }
      _folders[index] = _folders[index].copyWith(name: newName, updatedAt: DateTime.now());
      _foldersVersion++;
      notifyListeners();
      _saveToPrefs();
    }
  }

  void removeFolder(String id) {
    final index = _folders.indexWhere((f) => f.id == id);
    if (index != -1 && !_folders[index].isSystemStreak) {
      final now = DateTime.now();
      final childFolders =
          _folders
              .where((f) => f.parentFolderId == id)
              .map((f) => f.id)
              .toList();
      for (final childId in childFolders) {
        removeFolder(childId);
      }
      _folders[index] = _folders[index].copyWith(isDeleted: true, updatedAt: now);
      for (var i = 0; i < _tasks.length; i++) {
        if (_tasks[i].folderId == id) {
          _tasks[i] = _tasks[i].copyWith(isDeleted: true, updatedAt: now);
        }
      }
      _foldersVersion++;
      notifyListeners();
      _saveToPrefs();
    }
  }

  void clearAllTasks() {
    final now = DateTime.now();
    for (var i = 0; i < _tasks.length; i++) {
      _tasks[i] = _tasks[i].copyWith(isDeleted: true, updatedAt: now);
    }
    notifyListeners();
    _saveToPrefs();
  }

  void clearAllFolders() {
    _folders.removeWhere((f) => !f.isSystemStreak);
    _tasks.removeWhere((t) => t.folderId != null);
    _foldersVersion++;
    notifyListeners();
    _saveToPrefs();
  }

  void clearAllData() {
    final now = DateTime.now();
    for (var i = 0; i < _tasks.length; i++) {
      _tasks[i] = _tasks[i].copyWith(isDeleted: true, updatedAt: now);
    }
    for (var i = 0; i < _folders.length; i++) {
      if (!_folders[i].isSystemStreak) {
        _folders[i] = _folders[i].copyWith(isDeleted: true, updatedAt: now);
      }
    }
    _foldersVersion++;
    notifyListeners();
    _saveToPrefs();
  }
}
