import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task_info_block.dart';
import '../models/task_model.dart';
import 'package:uuid/uuid.dart';

import '../../../core/calendar_service.dart';
import '../../../core/home_widget_service.dart';
import '../../../core/logger_service.dart';
import '../../../core/notification_service.dart';

enum TaskFilter { all, active, completed, foldersOnly }

class _PersistenceSnapshot {
  final String tasksJson;
  final String foldersJson;
  final List<TaskItem> tasks;

  const _PersistenceSnapshot({
    required this.tasksJson,
    required this.foldersJson,
    required this.tasks,
  });
}

class TaskProvider with ChangeNotifier {
  final _uuid = const Uuid();
  final List<TaskItem> _tasks = [];
  final List<FolderItem> _folders = [];
  final _initCompleter = Completer<void>();
  Future<void> _saveQueue = Future<void>.value();
  Timer? _saveDebounce;
  bool _savePending = false;
  bool _pendingSaveWaitsForReady = false;
  Completer<void>? _pendingSaveCompleter;
  Future<void>? _flushFuture;
  int _persistenceWriteCount = 0;

  static const _persistenceDebounce = Duration(milliseconds: 300);

  @visibleForTesting
  int get persistenceWriteCount => _persistenceWriteCount;

  String _searchQuery = '';
  TaskFilter _filter = TaskFilter.all;
  int _streakCount = 1;
  int _tasksVersion = 0;
  int _foldersVersion = 0;
  String? _lastViewedFolderName;

  void _notifyTasksChanged() {
    _tasksVersion++;
    notifyListeners();
  }

  void _notifyFoldersChanged() {
    _foldersVersion++;
    notifyListeners();
  }

  void _notifyTasksAndFoldersChanged() {
    _tasksVersion++;
    _foldersVersion++;
    notifyListeners();
  }

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
  List<TaskItem> get tasks =>
      List.unmodifiable(_tasks.where((t) => !t.isDeleted));

  /// Active (non-deleted) folders, including the system streak folder.
  List<FolderItem> get folders =>
      List.unmodifiable(_folders.where((f) => !f.isDeleted));
  String get searchQuery => _searchQuery;
  TaskFilter get filter => _filter;
  int get streakCount => _streakCount;
  int get tasksVersion => _tasksVersion;
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
  /// Coalesces rapid mutations into one snapshot, then serializes writes so a
  /// slower earlier write cannot overwrite a newer mutation.
  Future<void> _saveToPrefs({bool waitForReady = true}) {
    _savePending = true;
    _pendingSaveWaitsForReady = _pendingSaveWaitsForReady || waitForReady;
    final completer = _pendingSaveCompleter ??= Completer<void>();
    _saveDebounce?.cancel();
    _saveDebounce = Timer(_persistenceDebounce, () {
      unawaited(
        flushPersistence().catchError((Object error, StackTrace stackTrace) {
          LoggerService.instance.w(
            'Debounced task persistence flush failed',
            error: error,
            stackTrace: stackTrace,
          );
        }),
      );
    });
    return completer.future;
  }

  /// Flushes the latest pending mutation to storage immediately.
  ///
  /// Lifecycle callbacks can be interrupted by the operating system, so this
  /// is best-effort. Normal mutations remain debounced to avoid serializing the
  /// complete task list for every keystroke/reorder operation.
  Future<void> flushPersistence() {
    final inFlight = _flushFuture;
    if (inFlight != null) return inFlight;

    final future = _flushPersistenceLoop();
    _flushFuture = future;
    return future.whenComplete(() {
      if (identical(_flushFuture, future)) _flushFuture = null;
    });
  }

  Future<void> _flushPersistenceLoop() async {
    do {
      _saveDebounce?.cancel();
      _saveDebounce = null;
      await _flushPendingPersistence();
      await _saveQueue;
    } while (_savePending);
  }

  Future<void> _flushPendingPersistence() async {
    if (!_savePending) return;

    _savePending = false;
    final waitForReady = _pendingSaveWaitsForReady;
    _pendingSaveWaitsForReady = false;
    final completer = _pendingSaveCompleter;
    _pendingSaveCompleter = null;

    final write = _saveQueue
        .catchError((Object error, StackTrace stackTrace) {
          LoggerService.instance.e(
            'Previous task persistence failed',
            error: error,
            stackTrace: stackTrace,
          );
        })
        .then((_) async {
          if (waitForReady) await ready;
          await _writeToPrefs(_snapshotState());
        });
    _saveQueue = write;

    try {
      await write;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    } on Object catch (error, stackTrace) {
      // Most mutation methods intentionally do not await persistence. Keep
      // those fire-and-forget calls handled while explicit flush/persist calls
      // still receive the write error through [_saveQueue].
      LoggerService.instance.e(
        'Task persistence write failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (completer != null && !completer.isCompleted) {
        // Mutation callers intentionally ignore this internal future; they
        // must not receive an unhandled rejected Future. Explicit callers of
        // flushPersistence() still receive the original write error below.
        completer.complete();
      }
      rethrow;
    }
  }

  _PersistenceSnapshot _snapshotState() {
    final tasks = List<TaskItem>.unmodifiable(_tasks);
    return _PersistenceSnapshot(
      tasksJson: jsonEncode(tasks.map((t) => t.toJson()).toList()),
      foldersJson: jsonEncode(_folders.map((f) => f.toJson()).toList()),
      tasks: tasks,
    );
  }

  @override
  void dispose() {
    // Normal app shutdown is flushed from the lifecycle observer. Do not start
    // asynchronous native work after ChangeNotifier disposal.
    _saveDebounce?.cancel();
    _saveDebounce = null;
    super.dispose();
  }

  Future<void> _writeToPrefs(_PersistenceSnapshot snapshot) async {
    try {
      _persistenceWriteCount++;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_tasks', snapshot.tasksJson);
      await prefs.setString('saved_folders', snapshot.foldersJson);
      HomeWidgetService.updateData(this);
      try {
        await NotificationService.syncTasks(snapshot.tasks);
      } on Object catch (error, stackTrace) {
        LoggerService.instance.w(
          'Task notification sync failed; data was saved',
          error: error,
          stackTrace: stackTrace,
        );
      }
    } on Exception catch (error, stackTrace) {
      LoggerService.instance.e(
        'Task persistence failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tasksStr = prefs.getString('saved_tasks');
      final foldersStr = prefs.getString('saved_folders');

      if (tasksStr != null && tasksStr.isNotEmpty) {
        final List decoded = jsonDecode(tasksStr);
        for (final entry in decoded) {
          try {
            final task = TaskItem.fromJson(entry);
            final normalizedTask = _normalizeImportedTask(task);
            if (!_tasks.any((existing) => existing.id == normalizedTask.id)) {
              _tasks.add(normalizedTask);
            }
          } catch (error, stackTrace) {
            LoggerService.instance.w(
              'Skipping malformed persisted task',
              error: error,
              stackTrace: stackTrace,
            );
          }
        }
      }

      if (foldersStr != null && foldersStr.isNotEmpty) {
        final List decoded = jsonDecode(foldersStr);
        for (final entry in decoded) {
          try {
            final folder = FolderItem.fromJson(entry);
            // The streak folder is an app-owned invariant, not user data. Drop
            // persisted copies so checkDailyStreak() recreates one canonical
            // record, and detach any user folder that referenced it.
            if (folder.id == 'system_streak_folder' || folder.isSystemStreak) {
              continue;
            }
            if (folder.parentFolderId == 'system_streak_folder') {
              folder.parentFolderId = null;
            }
            if (!_folders.any((existing) => existing.id == folder.id)) {
              _folders.add(folder);
            }
          } catch (error, stackTrace) {
            LoggerService.instance.w(
              'Skipping malformed persisted folder',
              error: error,
              stackTrace: stackTrace,
            );
          }
        }
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

    final streakFolderName = 'День $_streakCount';
    final existingIndex = _folders.indexWhere((f) => f.isSystemStreak);

    if (existingIndex != -1) {
      // Update in place so the streak keeps its ID, position, and any
      // tasks that were dropped into it. Recreating it would orphan tasks.
      _folders[existingIndex] = _folders[existingIndex].copyWith(
        name: streakFolderName,
      );
    } else {
      _folders.insert(
        0,
        FolderItem(
          id: 'system_streak_folder',
          name: streakFolderName,
          isSystemStreak: true,
          parentFolderId: null,
        ),
      );
    }
    _notifyFoldersChanged();
    unawaited(_saveToPrefs(waitForReady: false));
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

  bool isTimerRunning(String id) {
    final index = _tasks.indexWhere((task) => task.id == id);
    return index != -1 && _tasks[index].timerStartedAt != null;
  }

  Duration elapsedForTask(String id, {DateTime? now}) {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index == -1) return Duration.zero;
    final task = _tasks[index];
    var seconds = task.timerElapsedSeconds;
    if (task.timerStartedAt != null) {
      seconds +=
          (now ?? DateTime.now()).difference(task.timerStartedAt!).inSeconds;
    }
    return Duration(seconds: seconds.clamp(0, 1 << 31));
  }

  void startTimer(String id, {DateTime? startedAt}) {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index == -1 || _tasks[index].isDeleted || _tasks[index].isCompleted) {
      return;
    }
    if (_tasks[index].timerStartedAt != null) return;
    _tasks[index] = _tasks[index].copyWith(
      timerStartedAt: startedAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _notifyTasksChanged();
    _saveToPrefs();
  }

  void stopTimer(String id, {DateTime? stoppedAt}) {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index == -1) return;
    final task = _tasks[index];
    final startedAt = task.timerStartedAt;
    if (startedAt == null) return;
    final elapsed =
        (stoppedAt ?? DateTime.now()).difference(startedAt).inSeconds;
    _tasks[index] = task.copyWith(
      timerStartedAt: null,
      timerElapsedSeconds: task.timerElapsedSeconds + elapsed.clamp(0, 1 << 31),
      updatedAt: DateTime.now(),
    );
    _notifyTasksChanged();
    _saveToPrefs();
  }

  void resetTimer(String id) {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index == -1) return;
    _tasks[index] = _tasks[index].copyWith(
      timerStartedAt: null,
      timerElapsedSeconds: 0,
      updatedAt: DateTime.now(),
    );
    _notifyTasksChanged();
    _saveToPrefs();
  }

  // ── Drag & Move methods ─────────────────────────────────────
  void moveTaskToFolder(String taskId, String? targetFolderId) {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      _tasks[index] = _tasks[index].copyWith(
        folderId: targetFolderId,
        updatedAt: DateTime.now(),
      );
      _notifyTasksChanged();
      _saveToPrefs();
    }
  }

  void moveFolderToFolder(String folderId, String? targetParentFolderId) {
    if (folderId == targetParentFolderId) return;
    if (targetParentFolderId != null &&
        !_folders.any((f) => f.id == targetParentFolderId && !f.isDeleted)) {
      return;
    }
    if (targetParentFolderId == 'system_streak_folder') return;
    if (_wouldCreateFolderCycle(folderId, targetParentFolderId)) return;

    final index = _folders.indexWhere((f) => f.id == folderId);
    if (index != -1 &&
        !_folders[index].isDeleted &&
        !_folders[index].isSystemStreak) {
      _folders[index] = _folders[index].copyWith(
        parentFolderId: targetParentFolderId,
        updatedAt: DateTime.now(),
      );
      _notifyFoldersChanged();
      _saveToPrefs();
    }
  }

  /// Returns true when [targetParentFolderId] is [folderId] or one of its
  /// descendants. A visited set also prevents malformed legacy data from
  /// causing an infinite walk while validating a move.
  bool _wouldCreateFolderCycle(String folderId, String? targetParentFolderId) {
    var currentId = targetParentFolderId;
    final visited = <String>{};
    while (currentId != null) {
      if (currentId == folderId) return true;
      if (!visited.add(currentId)) return true;
      final index = _folders.indexWhere((f) => f.id == currentId);
      if (index == -1) return false;
      currentId = _folders[index].parentFolderId;
    }
    return false;
  }

  void _reorderFoldersByParent(
    String? parentFolderId,
    int oldIndex,
    int newIndex,
  ) {
    final list =
        _folders
            .where((f) => f.parentFolderId == parentFolderId && !f.isDeleted)
            .toList();
    if (oldIndex < 0 ||
        newIndex < 0 ||
        oldIndex >= list.length ||
        newIndex >= list.length) {
      return;
    }

    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);

    final ids = list.map((f) => f.id).toSet();
    final newFolders = <FolderItem>[
      ..._folders.where((f) => !ids.contains(f.id)),
      ...list,
    ];

    _folders
      ..clear()
      ..addAll(newFolders);
    _notifyFoldersChanged();
    _saveToPrefs();
  }

  void reorderRootFolders(int oldIndex, int newIndex) {
    if (oldIndex < 0 || newIndex < 0) return;
    // Reordering a filtered/searched list is ambiguous and can cause data
    // loss, so only reorder when the full root list is visible.
    if (_searchQuery.isNotEmpty || _filter != TaskFilter.all) return;
    _reorderFoldersByParent(null, oldIndex, newIndex);
  }

  void reorderSubfolders(String parentFolderId, int oldIndex, int newIndex) {
    _reorderFoldersByParent(parentFolderId, oldIndex, newIndex);
  }

  void reorderFolderTasks(String folderId, int oldIndex, int newIndex) {
    final folderTasks =
        _tasks.where((t) => t.folderId == folderId && !t.isDeleted).toList();
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
    _notifyTasksChanged();
    _saveToPrefs();
  }

  void addTask(
    String title, {
    String? folderId,
    DateTime? startTime,
    DateTime? endTime,
    List<TaskInfoBlock> infoBlocks = const [],
  }) {
    if (title.isEmpty) return;
    if (title.length > 250) {
      throw Exception('Название длиннее 250 символов');
    }
    _validateInfoBlocks(infoBlocks);
    _tasks.add(
      TaskItem(
        id: _uuid.v4(),
        title: title,
        folderId: folderId,
        startTime: startTime,
        endTime: endTime,
        expectedDuration:
            startTime != null && endTime != null
                ? TaskItem.durationForPeriod(startTime, endTime)
                : null,
        infoBlocks: infoBlocks,
        updatedAt: DateTime.now(),
      ),
    );
    _notifyTasksChanged();
    _saveToPrefs();
  }

  /// Adds a raw [task] directly, used by import/sync flows.
  void addTaskRaw(TaskItem task) {
    _validateInfoBlocks(task.infoBlocks);
    _tasks.add(task);
    _notifyTasksChanged();
    _saveToPrefs();
  }

  /// Upserts a task during import/sync, updating the existing record if it
  /// already exists. Returns true if the item was changed.
  bool upsertTask(TaskItem task) {
    final normalizedTask = _normalizeImportedTask(task);
    final index = _tasks.indexWhere((t) => t.id == normalizedTask.id);
    if (index == -1) {
      _tasks.add(normalizedTask);
      return true;
    }
    if (normalizedTask.updatedAt.isAfter(_tasks[index].updatedAt)) {
      _tasks[index] = normalizedTask;
      return true;
    }
    return false;
  }

  void toggleTask(String id) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final task = _tasks[index];
    final completing = !task.isCompleted;
    var elapsedSeconds = task.timerElapsedSeconds;
    if (completing && task.timerStartedAt != null) {
      elapsedSeconds += DateTime.now()
          .difference(task.timerStartedAt!)
          .inSeconds
          .clamp(0, 1 << 31);
    }

    _tasks[index] = task.copyWith(
      isCompleted: completing,
      timerStartedAt: completing ? null : task.timerStartedAt,
      timerElapsedSeconds: elapsedSeconds,
      updatedAt: DateTime.now(),
    );
    _notifyTasksChanged();
    _saveToPrefs();
  }

  void removeTask(String id) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index != -1) {
      final task = _tasks[index];
      _tasks[index] = task.copyWith(isDeleted: true, updatedAt: DateTime.now());
      _notifyTasksChanged();
      _saveToPrefs();
      _removeTaskCalendarEvent(task);
    }
  }

  void _removeTaskCalendarEvent(TaskItem task) {
    if (task.calendarId != null && task.calendarEventId != null) {
      CalendarService.deleteEvent(
        task.calendarId!,
        task.calendarEventId!,
      ).catchError((_) {});
    }
  }

  void updateTask(
    String id,
    String newTitle, {
    List<TaskInfoBlock>? infoBlocks,
  }) {
    if (newTitle.length > 250) {
      throw Exception('Название длиннее 250 символов');
    }
    if (infoBlocks != null) _validateInfoBlocks(infoBlocks);
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index != -1) {
      _tasks[index] = _tasks[index].copyWith(
        title: newTitle,
        infoBlocks: infoBlocks,
        updatedAt: DateTime.now(),
      );
      _notifyTasksChanged();
      _saveToPrefs();
      syncTaskCalendarEvent(id).catchError((_) {});
    }
  }

  void updateTaskInfoBlocks(String taskId, List<TaskInfoBlock> blocks) {
    _validateInfoBlocks(blocks);
    final index = _tasks.indexWhere((task) => task.id == taskId);
    if (index == -1 || _tasks[index].isDeleted) return;
    _tasks[index] = _tasks[index].copyWith(
      infoBlocks: blocks,
      updatedAt: DateTime.now(),
    );
    _notifyTasksChanged();
    _saveToPrefs();
  }

  void adjustQuantityBlock(String taskId, String blockId, double delta) {
    if (!delta.isFinite) return;
    final index = _tasks.indexWhere((task) => task.id == taskId);
    if (index == -1 || _tasks[index].isDeleted) return;

    final blocks = _tasks[index].infoBlocks;
    final blockIndex = blocks.indexWhere(
      (block) =>
          block.id == blockId && block.type == TaskInfoBlockType.quantity,
    );
    if (blockIndex == -1) return;

    final block = blocks[blockIndex];
    final nextValue =
        (block.currentValue + delta).clamp(0.0, block.targetValue).toDouble();
    final updatedBlocks = List<TaskInfoBlock>.of(blocks);
    updatedBlocks[blockIndex] = block.copyWith(currentValue: nextValue);
    _tasks[index] = _tasks[index].copyWith(
      infoBlocks: updatedBlocks,
      updatedAt: DateTime.now(),
    );
    _notifyTasksChanged();
    _saveToPrefs();
  }

  void _validateInfoBlocks(List<TaskInfoBlock> blocks) {
    final attachmentCount = blocks.fold<int>(
      0,
      (total, block) => total + block.attachments.length,
    );
    if (attachmentCount > kMaxTaskAttachmentsPerTask) {
      throw const FormatException('Too many task attachments');
    }
  }

  TaskItem _normalizeImportedTask(TaskItem task) {
    var remaining = kMaxTaskAttachmentsPerTask;
    var truncated = false;
    final normalizedBlocks = <TaskInfoBlock>[];

    for (final block in task.infoBlocks) {
      if (block.type != TaskInfoBlockType.description) {
        normalizedBlocks.add(block);
        continue;
      }
      final keepCount = block.attachments.length.clamp(0, remaining);
      if (keepCount != block.attachments.length) truncated = true;
      normalizedBlocks.add(
        block.copyWith(attachments: block.attachments.take(keepCount).toList()),
      );
      remaining -= keepCount;
    }

    if (!truncated) return task;
    LoggerService.instance.w('Trimmed task attachments to the supported limit');
    return task.copyWith(
      infoBlocks: normalizedBlocks,
      updatedAt: task.updatedAt,
    );
  }

  /// Links the task to a calendar event on [calendarId] at [date].
  /// Updates the existing event if [task.calendarEventId] is already set.
  Future<void> linkTaskToCalendar(
    String id,
    String calendarId,
    DateTime date,
  ) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final task = _tasks[index];
    final eventId = await CalendarService.createOrUpdateEvent(
      calendarId: calendarId,
      title: task.title,
      date: date,
      eventId: task.calendarEventId,
      description: 'Task from Asa',
    );

    if (eventId != null) {
      _tasks[index] = task.copyWith(
        dueDate: date,
        calendarId: calendarId,
        calendarEventId: eventId,
        updatedAt: DateTime.now(),
      );
      _notifyTasksChanged();
      _saveToPrefs();
    }
  }

  /// Unlinks the task from its calendar event without deleting the task.
  Future<void> unlinkTaskFromCalendar(String id) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final task = _tasks[index];
    if (task.calendarId != null && task.calendarEventId != null) {
      await CalendarService.deleteEvent(
        task.calendarId!,
        task.calendarEventId!,
      );
    }

    _tasks[index] = task.copyWith(
      calendarId: null,
      calendarEventId: null,
      updatedAt: DateTime.now(),
    );
    _notifyTasksChanged();
    _saveToPrefs();
  }

  /// Updates the time fields of a task. Pass null to clear a field.
  /// Also updates the linked calendar event if one exists.
  void setTaskTime(String id, {DateTime? startTime, DateTime? endTime}) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final calculatedDuration =
        startTime != null && endTime != null
            ? TaskItem.durationForPeriod(startTime, endTime)
            : null;
    _tasks[index] = _tasks[index].copyWith(
      startTime: startTime,
      endTime: endTime,
      expectedDuration: calculatedDuration,
      updatedAt: DateTime.now(),
    );
    _notifyTasksChanged();
    _saveToPrefs();
    syncTaskCalendarEvent(id).catchError((_) {});
  }

  /// Updates the linked calendar event to reflect the current task title,
  /// due date and time period. The date part is taken from [dueDate], while
  /// the time part is taken from [startTime] / [endTime] when present.
  Future<void> syncTaskCalendarEvent(String id) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final task = _tasks[index];
    if (task.calendarId == null || task.calendarEventId == null) return;

    final baseDate = task.dueDate;
    if (baseDate == null) return;

    DateTime start = baseDate;
    if (task.startTime != null) {
      start = DateTime(
        baseDate.year,
        baseDate.month,
        baseDate.day,
        task.startTime!.hour,
        task.startTime!.minute,
      );
    }

    DateTime? end;
    if (task.endTime != null) {
      end = DateTime(
        baseDate.year,
        baseDate.month,
        baseDate.day,
        task.endTime!.hour,
        task.endTime!.minute,
      );
      if (end.isBefore(start)) {
        end = end.add(const Duration(days: 1));
      }
    }

    await CalendarService.createOrUpdateEvent(
      calendarId: task.calendarId!,
      title: task.title,
      date: start,
      eventId: task.calendarEventId,
      description: 'Task from Asa',
      endTime: end,
    );
  }

  void addFolder(String name, {String? parentFolderId, String? iconAsset}) {
    if (name.isEmpty) return;
    if (name.length > 250) {
      throw Exception('Название длиннее 250 символов');
    }
    if (parentFolderId != null &&
        (!_folders.any((f) => f.id == parentFolderId && !f.isDeleted) ||
            parentFolderId == 'system_streak_folder')) {
      return;
    }
    _folders.add(
      FolderItem(
        id: _uuid.v4(),
        name: name,
        parentFolderId: parentFolderId,
        iconAsset: iconAsset,
        updatedAt: DateTime.now(),
      ),
    );
    _notifyFoldersChanged();
    _saveToPrefs();
  }

  /// Adds a raw [folder] directly, used by import/sync flows.
  void addFolderRaw(FolderItem folder) {
    if (folder.id == 'system_streak_folder' ||
        folder.isSystemStreak ||
        folder.parentFolderId == 'system_streak_folder') {
      return;
    }
    _folders.add(folder);
    _notifyFoldersChanged();
    _saveToPrefs();
  }

  /// Upserts a folder during import/sync, updating the existing record if it
  /// already exists. Returns true if the item was changed.
  bool upsertFolder(FolderItem folder) {
    if (folder.id == 'system_streak_folder' ||
        folder.isSystemStreak ||
        folder.parentFolderId == 'system_streak_folder') {
      return false;
    }
    final index = _folders.indexWhere((f) => f.id == folder.id);
    if (index != -1 && !folder.updatedAt.isAfter(_folders[index].updatedAt)) {
      return false;
    }

    final safeFolder =
        _wouldCreateFolderCycle(folder.id, folder.parentFolderId)
            ? folder.copyWith(parentFolderId: null)
            : folder;
    if (index == -1) {
      _folders.add(safeFolder);
    } else {
      _folders[index] = safeFolder;
    }
    return true;
  }

  /// Notifies listeners and persists the current state. Called after bulk
  /// operations such as import/sync merges.
  Future<void> persist() async {
    _notifyTasksAndFoldersChanged();
    await flushPersistence();
  }

  void updateFolder(String id, String newName, {String? iconAsset}) {
    final index = _folders.indexWhere((f) => f.id == id);
    if (index != -1 && !_folders[index].isSystemStreak) {
      if (newName.length > 250) {
        throw Exception('Название длиннее 250 символов');
      }
      _folders[index] = _folders[index].copyWith(
        name: newName,
        iconAsset: iconAsset,
        updatedAt: DateTime.now(),
      );
      _notifyFoldersChanged();
      _saveToPrefs();
    }
  }

  void removeFolder(String id) {
    final changed = _removeFolderTree(id, DateTime.now(), <String>{});
    if (!changed) return;

    _notifyTasksAndFoldersChanged();
    _saveToPrefs();
  }

  bool _removeFolderTree(String id, DateTime updatedAt, Set<String> visited) {
    if (!visited.add(id)) return false;

    final index = _folders.indexWhere((f) => f.id == id);
    if (index == -1 ||
        _folders[index].isDeleted ||
        _folders[index].isSystemStreak) {
      return false;
    }

    var changed = false;
    final childIds =
        _folders.where((f) => f.parentFolderId == id).map((f) => f.id).toList();
    for (final childId in childIds) {
      changed = _removeFolderTree(childId, updatedAt, visited) || changed;
    }

    _folders[index] = _folders[index].copyWith(
      isDeleted: true,
      updatedAt: updatedAt,
    );
    changed = true;
    for (var i = 0; i < _tasks.length; i++) {
      if (_tasks[i].folderId == id && !_tasks[i].isDeleted) {
        final task = _tasks[i];
        _tasks[i] = task.copyWith(isDeleted: true, updatedAt: updatedAt);
        _removeTaskCalendarEvent(task);
      }
    }
    return changed;
  }

  void clearAllTasks() {
    final now = DateTime.now();
    for (var i = 0; i < _tasks.length; i++) {
      _tasks[i] = _tasks[i].copyWith(isDeleted: true, updatedAt: now);
    }
    _notifyTasksChanged();
    _saveToPrefs();
  }

  void clearAllFolders() {
    final now = DateTime.now();
    for (var i = 0; i < _folders.length; i++) {
      if (!_folders[i].isSystemStreak && !_folders[i].isDeleted) {
        _folders[i] = _folders[i].copyWith(isDeleted: true, updatedAt: now);
      }
    }
    for (var i = 0; i < _tasks.length; i++) {
      if (_tasks[i].folderId != null && !_tasks[i].isDeleted) {
        final task = _tasks[i];
        _tasks[i] = task.copyWith(isDeleted: true, updatedAt: now);
        _removeTaskCalendarEvent(task);
      }
    }
    _notifyTasksAndFoldersChanged();
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
    _notifyTasksAndFoldersChanged();
    _saveToPrefs();
  }
}
