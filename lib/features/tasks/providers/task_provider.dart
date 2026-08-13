import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task_info_block.dart';
import '../models/task_model.dart';
import '../services/description_index.dart';
import '../services/description_link_resolver.dart';
import 'package:uuid/uuid.dart';

import '../../../core/app_strings.dart';
import '../../../core/calendar_service.dart';
import '../../../core/description_format.dart';
import '../../../core/home_widget_service.dart';
import '../../../core/input_utils.dart';
import '../../../core/logger_service.dart';
import '../../../core/notification_service.dart';
import '../../../core/task_attachment_service.dart';

/// How long a soft-deleted task or folder is kept before it is permanently
/// purged from the local database.
///
/// Records older than this are removed during app startup and after every
/// import/sync merge (via [TaskProvider.persist]). Purged records cannot be
/// restored, and the attachment files they reference are deleted from disk, so
/// the persisted JSON never grows without bound.
const Duration kDeletedItemRetention = Duration(days: 7);

enum TaskFilter { all, active, completed, foldersOnly }

class _CalendarPeriod {
  final DateTime start;
  final DateTime end;

  const _CalendarPeriod(this.start, this.end);
}

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
  final _descriptionIndex = DescriptionIndex();
  final List<TaskItem> _tasks = [];
  final List<FolderItem> _folders = [];
  final _initCompleter = Completer<void>();
  Future<void> _saveQueue = Future<void>.value();
  Timer? _saveDebounce;
  bool _savePending = false;
  bool _pendingSaveWaitsForReady = false;
  Completer<void>? _pendingSaveCompleter;
  Future<void>? _flushFuture;
  Future<void> _calendarCleanupOperation = Future<void>.value();
  final Map<String, Future<void>> _calendarOperations =
      <String, Future<void>>{};
  int _persistenceWriteCount = 0;

  static const _persistenceDebounce = Duration(milliseconds: 300);
  static const _stateStorageKey = 'saved_state_v2';
  static const _tasksStorageKey = 'saved_tasks';
  static const _foldersStorageKey = 'saved_folders';
  static const _tasksBackupStorageKey = 'saved_tasks_backup';
  static const _foldersBackupStorageKey = 'saved_folders_backup';
  static const _pendingCalendarCleanupKey = 'pending_calendar_cleanup';

  @visibleForTesting
  int get persistenceWriteCount => _persistenceWriteCount;

  String _searchQuery = '';
  TaskFilter _filter = TaskFilter.all;
  int _streakCount = 1;
  int _tasksVersion = 0;
  int _foldersVersion = 0;
  String? _lastViewedFolderName;
  String _languageCode = 'ru';

  void _rebuildDescriptionIndex() {
    _descriptionIndex.rebuild(_tasks, _folders);
  }

  void _notifyTasksChanged() {
    _rebuildDescriptionIndex();
    _tasksVersion++;
    notifyListeners();
  }

  void _notifyFoldersChanged() {
    _rebuildDescriptionIndex();
    _foldersVersion++;
    notifyListeners();
  }

  void _notifyTasksAndFoldersChanged() {
    _rebuildDescriptionIndex();
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
      _rebuildDescriptionIndex();
      // The in-memory removal runs synchronously; only attachment file
      // deletion is deferred, so startup is never blocked by cleanup.
      unawaited(_purgeSoftDeletedItems());
      unawaited(_retryPendingCalendarCleanup());
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

  List<DescriptionSearchResult> searchKnowledge(String query) {
    return _descriptionIndex.search(query);
  }

  DescriptionLinkResolution resolveDescriptionLink(String target) {
    return _descriptionIndex.resolve(target);
  }

  DescriptionBlockResolution resolveDescriptionBlock(String blockId) {
    return _descriptionIndex.resolveBlock(blockId);
  }

  DescriptionEmbedContent? resolveDescriptionEmbed(String target) {
    final resolution = _descriptionIndex.resolve(target);
    if (!resolution.isResolved) return null;
    final task = resolution.task!;
    final blocks =
        task.infoBlocks
            .where((block) => block.type == TaskInfoBlockType.description)
            .toList();
    return DescriptionEmbedContent(
      text: blocks.map((block) => block.text).join('\n\n'),
      format: DescriptionFormat.markdown,
      attachments: [for (final block in blocks) ...block.attachments],
    );
  }

  List<DescriptionBacklinkContext> backlinkContextsForTask(String taskId) {
    final snippets = _descriptionIndex.backlinkSnippets(taskId);
    return List.unmodifiable(
      _tasks
          .where((task) => !task.isDeleted && snippets.containsKey(task.id))
          .map(
            (task) => DescriptionBacklinkContext(
              task: task,
              snippet: snippets[task.id] ?? '',
            ),
          )
          .toList(),
    );
  }

  List<TaskItem> backlinksForTask(String taskId) {
    final ids = _descriptionIndex.backlinkTaskIds(taskId);
    return List.unmodifiable(
      _tasks.where((task) => !task.isDeleted && ids.contains(task.id)),
    );
  }

  Set<String> tagsForTask(String taskId) {
    return _descriptionIndex.tagsForTask(taskId);
  }

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

  /// Keeps the streak folder name in sync with the active app language.
  ///
  /// The name is persisted, but it is also re-derived on every startup from
  /// the saved language, so a runtime switch only needs to rename the live
  /// record for the current session.
  void setLanguage(String languageCode) {
    if (languageCode != 'ru' && languageCode != 'en') return;
    if (languageCode == _languageCode) return;
    _languageCode = languageCode;
    final index = _folders.indexWhere((f) => f.isSystemStreak);
    if (index == -1) return;
    final folder = _folders[index];
    final newName = _streakFolderName(_streakCount);
    if (folder.name == newName) return;
    _folders[index] = folder.copyWith(name: newName);
    _notifyFoldersChanged();
    _saveToPrefs(waitForReady: false);
  }

  String _streakFolderName(int count) =>
      AppStrings.streakFolderName(_languageCode, count);

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
      // Keep the last structurally valid pair as a recovery snapshot. A
      // partially written/corrupted current value must never overwrite the
      // only known-good backup during the next startup.
      final previousTasks = prefs.getString(_tasksStorageKey);
      if (_isValidPersistedList(previousTasks)) {
        await prefs.setString(_tasksBackupStorageKey, previousTasks!);
      }
      final previousFolders = prefs.getString(_foldersStorageKey);
      if (_isValidPersistedList(previousFolders)) {
        await prefs.setString(_foldersBackupStorageKey, previousFolders!);
      }

      // Keep tasks and folders in one versioned envelope as the authoritative
      // snapshot. SharedPreferences writes are per-key, so a paired envelope
      // prevents a crash between the legacy task/folder writes from producing
      // a mixed generation on the next startup.
      await prefs.setString(
        _stateStorageKey,
        jsonEncode({
          'version': 2,
          'tasks': jsonDecode(snapshot.tasksJson),
          'folders': jsonDecode(snapshot.foldersJson),
        }),
      );
      await prefs.setString(_tasksStorageKey, snapshot.tasksJson);
      await prefs.setString(_foldersStorageKey, snapshot.foldersJson);
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
      final versionedSnapshot = _readVersionedSnapshot(prefs);
      final currentTasks = prefs.getString(_tasksStorageKey);
      final backupTasks = prefs.getString(_tasksBackupStorageKey);
      final tasks =
          versionedSnapshot == null
              ? _readPersistedList(
                prefs,
                _tasksStorageKey,
                _tasksBackupStorageKey,
                'tasks',
              )
              : _decodePersistedList(versionedSnapshot.tasksJson, 'tasks');
      if (versionedSnapshot == null &&
          !_isValidPersistedList(currentTasks) &&
          _isValidPersistedList(backupTasks)) {
        // Repair immediately instead of waiting for the debounced mutation
        // flush triggered later by startup housekeeping.
        await prefs.setString(_tasksStorageKey, backupTasks!);
      }
      for (final entry in tasks) {
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

      final currentFolders = prefs.getString(_foldersStorageKey);
      final backupFolders = prefs.getString(_foldersBackupStorageKey);
      final folders =
          versionedSnapshot == null
              ? _readPersistedList(
                prefs,
                _foldersStorageKey,
                _foldersBackupStorageKey,
                'folders',
              )
              : _decodePersistedList(versionedSnapshot.foldersJson, 'folders');
      if (versionedSnapshot == null &&
          !_isValidPersistedList(currentFolders) &&
          _isValidPersistedList(backupFolders)) {
        await prefs.setString(_foldersStorageKey, backupFolders!);
      }
      for (final entry in folders) {
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
    } on Object catch (error, stackTrace) {
      // Preferences are local storage, not a reason to crash the app. Keep the
      // in-memory store usable and make the failure visible in diagnostics.
      LoggerService.instance.e(
        'Task persistence load failed; starting with empty local state',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  _PersistenceSnapshot? _readVersionedSnapshot(SharedPreferences prefs) {
    final encoded = prefs.getString(_stateStorageKey);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map || decoded['version'] != 2) {
        throw const FormatException('Unsupported persisted state version');
      }
      final tasks = decoded['tasks'];
      final folders = decoded['folders'];
      if (tasks is! List || folders is! List) {
        throw const FormatException('Persisted state lists are invalid');
      }
      return _PersistenceSnapshot(
        tasksJson: jsonEncode(tasks),
        foldersJson: jsonEncode(folders),
        tasks: const <TaskItem>[],
      );
    } on Object catch (error, stackTrace) {
      LoggerService.instance.w(
        'Versioned task persistence snapshot is invalid; using legacy recovery',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  List<dynamic> _readPersistedList(
    SharedPreferences prefs,
    String key,
    String backupKey,
    String kind,
  ) {
    final current = prefs.getString(key);
    try {
      return _decodePersistedList(current, kind);
    } on Object catch (error, stackTrace) {
      LoggerService.instance.w(
        'Corrupted persisted $kind; trying recovery snapshot',
        error: error,
        stackTrace: stackTrace,
      );
    }

    final backup = prefs.getString(backupKey);
    try {
      final recovered = _decodePersistedList(backup, kind);
      LoggerService.instance.i('Recovered persisted $kind from backup');
      return recovered;
    } on Object catch (error, stackTrace) {
      if (backup != null) {
        LoggerService.instance.e(
          'Persisted $kind recovery snapshot is also invalid',
          error: error,
          stackTrace: stackTrace,
        );
      }
      return const <dynamic>[];
    }
  }

  List<dynamic> _decodePersistedList(String? encoded, String kind) {
    if (encoded == null || encoded.isEmpty) return const <dynamic>[];
    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      throw FormatException('Persisted $kind must be a JSON list');
    }
    return decoded;
  }

  bool _isValidPersistedList(String? encoded) {
    if (encoded == null || encoded.isEmpty) return false;
    try {
      return jsonDecode(encoded) is List;
    } on Object {
      return false;
    }
  }

  /// Permanently removes soft-deleted tasks and folders older than
  /// [kDeletedItemRetention].
  ///
  /// Attachment files of purged tasks are deleted from disk. Legacy records
  /// without a persisted `updatedAt` default to the current time and are
  /// therefore kept, so old data is never accidentally purged. The system
  /// streak folder is exempt. Nothing is persisted when there is nothing to
  /// purge.
  Future<void> _purgeSoftDeletedItems() async {
    final cutoff = DateTime.now().subtract(kDeletedItemRetention);
    final purgedTasks = <TaskItem>[];
    _tasks.removeWhere((task) {
      if (!task.isDeleted || !task.updatedAt.isBefore(cutoff)) return false;
      purgedTasks.add(task);
      return true;
    });
    final purgedFolders = <FolderItem>[];
    _folders.removeWhere((folder) {
      if (!folder.isDeleted ||
          folder.isSystemStreak ||
          !folder.updatedAt.isBefore(cutoff)) {
        return false;
      }
      purgedFolders.add(folder);
      return true;
    });
    if (purgedTasks.isEmpty && purgedFolders.isEmpty) return;

    if (purgedTasks.isNotEmpty) {
      try {
        await _deleteAttachmentsForTasks(purgedTasks);
      } on Object catch (error, stackTrace) {
        LoggerService.instance.w(
          'Attachment cleanup for purged tasks failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    _notifyTasksAndFoldersChanged();
    _saveToPrefs(waitForReady: false);
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

        // Consecutive day increments the streak. One missed day keeps it as a
        // grace day; two or more missed days reset it to 1.
        if (daysDiff == 1) {
          currentStreak += 1;
        } else if (daysDiff >= 3) {
          currentStreak = 1;
        }
      } catch (_) {
        currentStreak = 1;
      }
    }

    _streakCount = currentStreak;
    await prefs.setString('lastLoginDate', todayStr);
    await prefs.setInt('streakCount', _streakCount);

    final streakFolderName = _streakFolderName(_streakCount);
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

  List<TaskItem> get filteredRootTasks {
    if (_filter == TaskFilter.foldersOnly) return [];
    final matchingIds =
        _searchQuery.isEmpty
            ? null
            : _descriptionIndex
                .search(_searchQuery)
                .map((result) => result.task.id)
                .toSet();
    return _tasks.where((task) {
      if (task.isDeleted || task.folderId != null) return false;
      if (_filter == TaskFilter.active && task.isCompleted) return false;
      if (_filter == TaskFilter.completed && !task.isCompleted) return false;
      return matchingIds == null || matchingIds.contains(task.id);
    }).toList();
  }

  List<TaskItem> get filteredInProgressTasks {
    if (_filter == TaskFilter.completed || _filter == TaskFilter.foldersOnly) {
      return [];
    }
    final matchingIds =
        _searchQuery.isEmpty
            ? null
            : _descriptionIndex
                .search(_searchQuery)
                .map((result) => result.task.id)
                .toSet();
    return _tasks.where((t) {
      if (t.isDeleted || t.isCompleted) return false;
      if (matchingIds == null) return true;
      return matchingIds.contains(t.id);
    }).toList();
  }

  List<TaskItem> get filteredCompletedTasks {
    if (_filter == TaskFilter.active || _filter == TaskFilter.foldersOnly) {
      return [];
    }
    final matchingIds =
        _searchQuery.isEmpty
            ? null
            : _descriptionIndex
                .search(_searchQuery)
                .map((result) => result.task.id)
                .toSet();
    return _tasks.where((t) {
      if (t.isDeleted || !t.isCompleted) return false;
      if (matchingIds == null) return true;
      return matchingIds.contains(t.id);
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
  /// Moves a task into [targetFolderId]. A null target places it in the
  /// visible root task list. The protected streak folder is never a target.
  bool moveTaskToFolder(String taskId, String? targetFolderId) {
    if (targetFolderId == 'system_streak_folder') return false;
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return false;
    _tasks[index] = _tasks[index].copyWith(
      folderId: targetFolderId,
      updatedAt: DateTime.now(),
    );
    _notifyTasksChanged();
    _saveToPrefs();
    return true;
  }

  /// Moves a folder into [targetParentFolderId]. Returns false when the move
  /// is rejected (self-move, missing/deleted target, the protected streak
  /// folder, a folder cycle, or a deleted/system folder source), so callers
  /// can avoid reporting a successful move that never happened.
  bool moveFolderToFolder(String folderId, String? targetParentFolderId) {
    if (folderId == targetParentFolderId) return false;
    if (targetParentFolderId != null &&
        !_folders.any((f) => f.id == targetParentFolderId && !f.isDeleted)) {
      return false;
    }
    if (targetParentFolderId == 'system_streak_folder') return false;
    if (_wouldCreateFolderCycle(folderId, targetParentFolderId)) return false;

    final index = _folders.indexWhere((f) => f.id == folderId);
    if (index == -1 ||
        _folders[index].isDeleted ||
        _folders[index].isSystemStreak) {
      return false;
    }
    _folders[index] = _folders[index].copyWith(
      parentFolderId: targetParentFolderId,
      updatedAt: DateTime.now(),
    );
    _notifyFoldersChanged();
    _saveToPrefs();
    return true;
  }

  /// Moves a task out of its current folder into that folder's parent.
  /// Tasks already at the root or whose current folder no longer exists are
  /// left untouched and false is returned.
  bool moveTaskToParentFolder(String taskId) {
    final taskIndex = _tasks.indexWhere((task) => task.id == taskId);
    if (taskIndex == -1) return false;

    final currentFolderId = _tasks[taskIndex].folderId;
    if (currentFolderId == null) return false;
    final folderIndex = _folders.indexWhere(
      (folder) => folder.id == currentFolderId && !folder.isDeleted,
    );
    if (folderIndex == -1) return false;

    return moveTaskToFolder(taskId, _folders[folderIndex].parentFolderId);
  }

  /// Whether [taskId] can be moved one level up via swipe-to-parent.
  /// Root-level tasks cannot move up; tasks in any valid folder can move to
  /// that folder's parent, including the visible root.
  bool canMoveTaskToParent(String taskId) {
    final taskIndex = _tasks.indexWhere((task) => task.id == taskId);
    if (taskIndex == -1) return false;

    final currentFolderId = _tasks[taskIndex].folderId;
    if (currentFolderId == null) return false;
    final folderIndex = _folders.indexWhere(
      (folder) => folder.id == currentFolderId && !folder.isDeleted,
    );
    if (folderIndex == -1) return false;

    return true;
  }

  /// Moves a nested folder into its current parent's parent. Root folders are
  /// already at the highest level and are intentionally left untouched (false
  /// is returned).
  bool moveFolderToParentFolder(String folderId) {
    final folderIndex = _folders.indexWhere(
      (folder) => folder.id == folderId && !folder.isDeleted,
    );
    if (folderIndex == -1) return false;

    final currentParentId = _folders[folderIndex].parentFolderId;
    if (currentParentId == null) return false;
    final parentIndex = _folders.indexWhere(
      (folder) => folder.id == currentParentId && !folder.isDeleted,
    );
    if (parentIndex == -1) return false;

    return moveFolderToFolder(folderId, _folders[parentIndex].parentFolderId);
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

  void addTask(
    String title, {
    String? folderId,
    DateTime? startTime,
    DateTime? endTime,
    List<TaskInfoBlock> infoBlocks = const [],
  }) {
    if (title.isEmpty) return;
    if (title.length > 250) {
      throw const TitleTooLongException();
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
    // Raw tasks come from import/sync. Preserve legacy quantity blocks even
    // when they predate the current creation limit.
    _validateInfoBlocks(task.infoBlocks, allowQuantityOverflow: true);
    _tasks.add(task);
    _notifyTasksChanged();
    _saveToPrefs();
  }

  /// Upserts a task during import/sync, updating the existing record if it
  /// already exists. Returns true if the item was changed.
  ///
  /// Mutates in-memory state only; the bulk import/sync flow finalizes the
  /// batch with [persist], which notifies listeners and flushes once.
  bool upsertTask(TaskItem task) {
    final normalizedTask = _normalizeImportedTask(task);
    final index = _tasks.indexWhere((t) => t.id == normalizedTask.id);
    // Preserve overflow for a new imported legacy task. For an existing task,
    // apply the normal grandfathering rule so sync cannot add a new block.
    _validateInfoBlocks(
      normalizedTask.infoBlocks,
      existingBlocks: index == -1 ? null : _tasks[index].infoBlocks,
      allowQuantityOverflow: index == -1,
    );
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
      infoBlocks: completing ? _completeQuantityBlocks(task.infoBlocks) : null,
      updatedAt: DateTime.now(),
    );
    _notifyTasksChanged();
    _saveToPrefs();
  }

  /// Applies a completion action already persisted by an Android widget
  /// background callback. Unlike [toggleTask], this is idempotent and cannot
  /// accidentally reopen a task when the callback ran before the app resumed.
  /// Deleted tasks are skipped so a stale callback cannot bump `updatedAt` and
  /// reset the soft-delete retention clock.
  void completeTaskFromWidget(String id) {
    final index = _tasks.indexWhere((task) => task.id == id);
    if (index == -1 || _tasks[index].isDeleted || _tasks[index].isCompleted) {
      return;
    }
    final task = _tasks[index];
    var elapsedSeconds = task.timerElapsedSeconds;
    if (task.timerStartedAt != null) {
      elapsedSeconds += DateTime.now()
          .difference(task.timerStartedAt!)
          .inSeconds
          .clamp(0, 1 << 31);
    }
    _tasks[index] = task.copyWith(
      isCompleted: true,
      timerStartedAt: null,
      timerElapsedSeconds: elapsedSeconds,
      infoBlocks: _completeQuantityBlocks(task.infoBlocks),
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
    final calendarId = task.calendarId;
    final eventId = task.calendarEventId;
    if (calendarId == null || eventId == null) return;
    unawaited(
      _enqueueCalendarOperation(
        task.id,
        () => _deleteTaskCalendarEvent(calendarId, eventId),
      ).catchError((_) {}),
    );
  }

  /// Serializes calendar mutations per task. Native calendar providers can
  /// complete requests out of order, so a task's second update must not race
  /// its first update or deletion.
  Future<void> _enqueueCalendarOperation(
    String taskId,
    Future<void> Function() operation,
  ) {
    final previous = _calendarOperations[taskId] ?? Future<void>.value();
    final next = previous.then((_) => operation());
    final guarded = next.catchError((Object error, StackTrace stackTrace) {
      LoggerService.instance.w(
        'Queued calendar operation failed',
        error: error,
        stackTrace: stackTrace,
      );
    });
    _calendarOperations[taskId] = guarded;
    unawaited(
      guarded.then((_) {
        if (identical(_calendarOperations[taskId], guarded)) {
          _calendarOperations.remove(taskId);
        }
      }),
    );
    return next;
  }

  Future<void> _deleteTaskCalendarEvent(
    String calendarId,
    String eventId,
  ) async {
    try {
      final deleted = await CalendarService.deleteEvent(calendarId, eventId);
      if (!deleted) {
        await _queuePendingCalendarCleanup(calendarId, eventId);
      }
    } on Object catch (error, stackTrace) {
      LoggerService.instance.w(
        'Failed to remove linked calendar event',
        error: error,
        stackTrace: stackTrace,
      );
      await _queuePendingCalendarCleanup(calendarId, eventId);
    }
  }

  Future<void> _queuePendingCalendarCleanup(String calendarId, String eventId) {
    final next = _calendarCleanupOperation.then(
      (_) => _queuePendingCalendarCleanupUnlocked(calendarId, eventId),
    );
    _calendarCleanupOperation = next.catchError((_) {});
    return next;
  }

  Future<void> _queuePendingCalendarCleanupUnlocked(
    String calendarId,
    String eventId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = <Map<String, dynamic>>[];
      final raw = prefs.getString(_pendingCalendarCleanupKey);
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final entry in decoded) {
              if (entry is Map &&
                  entry['calendarId'] is String &&
                  entry['eventId'] is String) {
                pending.add({
                  'calendarId': entry['calendarId'],
                  'eventId': entry['eventId'],
                });
              }
            }
          }
        } on Object {
          // Replace a corrupt retry queue with the current known item.
        }
      }
      if (!pending.any(
        (entry) =>
            entry['calendarId'] == calendarId && entry['eventId'] == eventId,
      )) {
        pending.add({'calendarId': calendarId, 'eventId': eventId});
      }
      await prefs.setString(_pendingCalendarCleanupKey, jsonEncode(pending));
    } on Object catch (error, stackTrace) {
      LoggerService.instance.w(
        'Failed to persist pending calendar cleanup',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _retryPendingCalendarCleanup() {
    final next = _calendarCleanupOperation.then(
      (_) => _retryPendingCalendarCleanupUnlocked(),
    );
    _calendarCleanupOperation = next.catchError((_) {});
    return next;
  }

  Future<void> _retryPendingCalendarCleanupUnlocked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingCalendarCleanupKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        await prefs.remove(_pendingCalendarCleanupKey);
        return;
      }
      final remaining = <Map<String, dynamic>>[];
      for (final entry in decoded) {
        if (entry is! Map ||
            entry['calendarId'] is! String ||
            entry['eventId'] is! String) {
          continue;
        }
        final calendarId = entry['calendarId'] as String;
        final eventId = entry['eventId'] as String;
        try {
          if (!await CalendarService.deleteEvent(calendarId, eventId)) {
            remaining.add({'calendarId': calendarId, 'eventId': eventId});
          }
        } on Object catch (error, stackTrace) {
          remaining.add({'calendarId': calendarId, 'eventId': eventId});
          LoggerService.instance.w(
            'Pending calendar cleanup retry failed',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      if (remaining.isEmpty) {
        await prefs.remove(_pendingCalendarCleanupKey);
      } else {
        await prefs.setString(
          _pendingCalendarCleanupKey,
          jsonEncode(remaining),
        );
      }
    } on Object catch (error, stackTrace) {
      LoggerService.instance.w(
        'Failed to process pending calendar cleanup queue',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _deleteCalendarEventsForTasks(Iterable<TaskItem> tasks) async {
    final cleanupOperations = <Future<void>>[];
    for (final task in tasks) {
      final calendarId = task.calendarId;
      final eventId = task.calendarEventId;
      if (calendarId == null || eventId == null) continue;
      cleanupOperations.add(
        _enqueueCalendarOperation(
          task.id,
          () => _deleteTaskCalendarEvent(calendarId, eventId),
        ),
      );
    }
    await Future.wait(cleanupOperations);
  }

  void updateTask(
    String id,
    String newTitle, {
    List<TaskInfoBlock>? infoBlocks,
  }) {
    if (newTitle.length > 250) {
      throw const TitleTooLongException();
    }
    final index = _tasks.indexWhere((t) => t.id == id);
    if (infoBlocks != null) {
      _validateInfoBlocks(
        infoBlocks,
        existingBlocks: index == -1 ? null : _tasks[index].infoBlocks,
      );
    }
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
    final index = _tasks.indexWhere((task) => task.id == taskId);
    _validateInfoBlocks(
      blocks,
      existingBlocks: index == -1 ? null : _tasks[index].infoBlocks,
    );
    if (index == -1 || _tasks[index].isDeleted) return;
    _tasks[index] = _tasks[index].copyWith(
      infoBlocks: blocks,
      updatedAt: DateTime.now(),
    );
    _notifyTasksChanged();
    _saveToPrefs();
  }

  List<TaskInfoBlock> _completeQuantityBlocks(List<TaskInfoBlock> blocks) {
    return [
      for (final block in blocks)
        block.type == TaskInfoBlockType.quantity
            ? block.copyWith(currentValue: block.targetValue)
            : block,
    ];
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

  void _validateInfoBlocks(
    List<TaskInfoBlock> blocks, {
    List<TaskInfoBlock>? existingBlocks,
    bool allowQuantityOverflow = false,
  }) {
    final descriptionCount =
        blocks
            .where((block) => block.type == TaskInfoBlockType.description)
            .length;
    if (descriptionCount > kMaxTaskDescriptionBlocksPerTask) {
      throw const FormatException(
        'A task can contain only one description block',
      );
    }

    final attachmentCount = blocks.fold<int>(
      0,
      (total, block) => total + block.attachments.length,
    );
    if (attachmentCount > kMaxTaskAttachmentsPerTask) {
      throw const FormatException('Too many task attachments');
    }

    if (allowQuantityOverflow) return;

    final quantityCount =
        blocks
            .where((block) => block.type == TaskInfoBlockType.quantity)
            .length;
    final existingQuantityCount =
        existingBlocks
            ?.where((block) => block.type == TaskInfoBlockType.quantity)
            .length ??
        0;
    // Legacy tasks may already exceed today's limit. They can be edited and
    // saved without data loss, but cannot gain another quantity block.
    final maxAllowedQuantityCount =
        existingQuantityCount > kMaxTaskQuantityBlocksPerTask
            ? existingQuantityCount
            : kMaxTaskQuantityBlocksPerTask;
    if (quantityCount > maxAllowedQuantityCount) {
      throw const FormatException('Too many task quantity blocks');
    }
  }

  TaskItem _normalizeImportedTask(TaskItem task) {
    var remaining = kMaxTaskAttachmentsPerTask;
    var truncated = false;
    final normalizedBlocks = normalizeTaskInfoBlocks(task.infoBlocks);
    final mergedDescriptionBlocks =
        normalizedBlocks.length != task.infoBlocks.length;

    final attachmentBlocks = <TaskInfoBlock>[];
    for (final block in normalizedBlocks) {
      if (block.type != TaskInfoBlockType.description) {
        attachmentBlocks.add(block);
        continue;
      }
      final keepCount = block.attachments.length.clamp(0, remaining);
      if (keepCount != block.attachments.length) truncated = true;
      attachmentBlocks.add(
        block.copyWith(attachments: block.attachments.take(keepCount).toList()),
      );
      remaining -= keepCount;
    }

    if (!truncated && !mergedDescriptionBlocks) return task;
    if (mergedDescriptionBlocks) {
      LoggerService.instance.w(
        'Merged duplicate task description blocks during normalization',
      );
    }
    if (truncated) {
      LoggerService.instance.w(
        'Trimmed task attachments to the supported limit',
      );
    }
    return task.copyWith(
      infoBlocks: attachmentBlocks,
      updatedAt: task.updatedAt,
    );
  }

  /// Links the task to a calendar event on [calendarId] at [date].
  /// Updates the existing event if [task.calendarEventId] is already set.
  ///
  /// A conflict is reported before the native write unless
  /// [allowOverlapping] is true. The UI can then ask for explicit confirmation
  /// and retry without holding this per-task queue open on a dialog.
  Future<void> linkTaskToCalendar(
    String id,
    String calendarId,
    DateTime date, {
    bool allowOverlapping = false,
  }) {
    return _enqueueCalendarOperation(id, () async {
      final index = _tasks.indexWhere((t) => t.id == id);
      if (index == -1 || _tasks[index].isDeleted) return;

      final task = _tasks[index];
      final period = _calendarPeriodForTask(task, date);
      if (!allowOverlapping &&
          await CalendarService.hasOverlappingEvents(
            calendarId: calendarId,
            start: period.start,
            end: period.end,
            excludeEventId: task.calendarEventId,
          )) {
        throw const CalendarEventConflictException();
      }

      final eventId = await _createCalendarEvent(
        calendarId: calendarId,
        title: task.title,
        period: period,
        eventId: task.calendarEventId,
      );

      final currentIndex = _tasks.indexWhere((t) => t.id == id);
      if (currentIndex != -1 && !_tasks[currentIndex].isDeleted) {
        _tasks[currentIndex] = _tasks[currentIndex].copyWith(
          dueDate: date,
          calendarId: calendarId,
          calendarEventId: eventId,
          updatedAt: DateTime.now(),
        );
        _notifyTasksChanged();
        _saveToPrefs();
      }
    });
  }

  /// Unlinks the task from its calendar event without deleting the task.
  Future<void> unlinkTaskFromCalendar(String id) {
    return _enqueueCalendarOperation(id, () async {
      final index = _tasks.indexWhere((t) => t.id == id);
      if (index == -1) return;

      final task = _tasks[index];
      if (task.calendarId != null && task.calendarEventId != null) {
        final deleted = await CalendarService.deleteEvent(
          task.calendarId!,
          task.calendarEventId!,
        );
        if (!deleted) {
          await _queuePendingCalendarCleanup(
            task.calendarId!,
            task.calendarEventId!,
          );
          return;
        }
      }

      final currentIndex = _tasks.indexWhere((t) => t.id == id);
      if (currentIndex == -1) return;
      _tasks[currentIndex] = _tasks[currentIndex].copyWith(
        calendarId: null,
        calendarEventId: null,
        updatedAt: DateTime.now(),
      );
      _notifyTasksChanged();
      _saveToPrefs();
    });
  }

  /// Updates the time fields of a task. Pass null to clear a field.
  /// Also updates the linked calendar event if one exists. Linked updates are
  /// serialized and check for overlaps before changing local task state.
  Future<void> setTaskTime(
    String id, {
    DateTime? startTime,
    DateTime? endTime,
    bool allowOverlapping = false,
  }) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) return Future<void>.value();
    final task = _tasks[index];
    if (task.calendarId == null || task.calendarEventId == null) {
      _applyTaskTime(id, startTime: startTime, endTime: endTime);
      return Future<void>.value();
    }

    return _enqueueCalendarOperation(
      id,
      () => _setLinkedTaskTime(
        id,
        startTime: startTime,
        endTime: endTime,
        allowOverlapping: allowOverlapping,
      ),
    );
  }

  Future<void> _setLinkedTaskTime(
    String id, {
    DateTime? startTime,
    DateTime? endTime,
    required bool allowOverlapping,
  }) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final task = _tasks[index];
    if (task.calendarId == null || task.calendarEventId == null) {
      _applyTaskTime(id, startTime: startTime, endTime: endTime);
      return;
    }

    final period = _calendarPeriodForValues(
      task,
      startTime: startTime,
      endTime: endTime,
    );
    if (!allowOverlapping &&
        await CalendarService.hasOverlappingEvents(
          calendarId: task.calendarId!,
          start: period.start,
          end: period.end,
          excludeEventId: task.calendarEventId,
        )) {
      throw const CalendarEventConflictException();
    }

    final eventId = await _createCalendarEvent(
      calendarId: task.calendarId!,
      title: task.title,
      period: period,
      eventId: task.calendarEventId,
    );
    _applyTaskTime(id, startTime: startTime, endTime: endTime);

    if (eventId != task.calendarEventId) {
      final currentIndex = _tasks.indexWhere((item) => item.id == id);
      if (currentIndex != -1 && !_tasks[currentIndex].isDeleted) {
        _tasks[currentIndex] = _tasks[currentIndex].copyWith(
          calendarEventId: eventId,
          updatedAt: DateTime.now(),
        );
        _notifyTasksChanged();
        _saveToPrefs();
      }
    }
  }

  void _applyTaskTime(String id, {DateTime? startTime, DateTime? endTime}) {
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
  }

  /// Updates the linked calendar event to reflect the current task title,
  /// due date and time period. The date part is taken from [dueDate], while
  /// the time part is taken from [startTime] / [endTime] when present.
  Future<void> syncTaskCalendarEvent(String id) {
    return _enqueueCalendarOperation(id, () => _syncTaskCalendarEvent(id));
  }

  Future<void> _syncTaskCalendarEvent(String id) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final task = _tasks[index];
    if (task.calendarId == null || task.calendarEventId == null) return;

    final baseDate = task.dueDate;
    if (baseDate == null) return;
    final period = _calendarPeriodForTask(task, baseDate);

    await _createCalendarEvent(
      calendarId: task.calendarId!,
      title: task.title,
      period: period,
      eventId: task.calendarEventId,
    );
  }

  Future<String> _createCalendarEvent({
    required String calendarId,
    required String title,
    required _CalendarPeriod period,
    String? eventId,
  }) async {
    final createdEventId = await CalendarService.createOrUpdateEvent(
      calendarId: calendarId,
      title: title,
      date: period.start,
      endTime: period.end,
      eventId: eventId,
      description: 'Task from Asa',
    );
    if (createdEventId == null || createdEventId.isEmpty) {
      throw const CalendarEventUpdateException();
    }
    return createdEventId;
  }

  _CalendarPeriod _calendarPeriodForTask(TaskItem task, DateTime date) {
    return _calendarPeriodForValues(
      task,
      startTime: task.startTime,
      endTime: task.endTime,
      date: date,
    );
  }

  _CalendarPeriod _calendarPeriodForValues(
    TaskItem task, {
    DateTime? startTime,
    DateTime? endTime,
    DateTime? date,
  }) {
    final baseDate = date ?? task.dueDate ?? DateTime.now();
    var start = DateTime(baseDate.year, baseDate.month, baseDate.day);
    if (startTime != null) {
      start = DateTime(
        baseDate.year,
        baseDate.month,
        baseDate.day,
        startTime.hour,
        startTime.minute,
      );
    }

    var end =
        endTime == null
            ? start.add(const Duration(hours: 1))
            : DateTime(
              baseDate.year,
              baseDate.month,
              baseDate.day,
              endTime.hour,
              endTime.minute,
            );
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    return _CalendarPeriod(start, end);
  }

  void addFolder(String name, {String? parentFolderId, String? iconAsset}) {
    if (name.isEmpty) return;
    if (name.length > 250) {
      throw const TitleTooLongException();
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
  ///
  /// Mutates in-memory state only; the bulk import/sync flow finalizes the
  /// batch with [persist], which notifies listeners and flushes once.
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
    // Imported or synced items may include old soft-deleted records; purge
    // them so a stale peer cannot keep resurrecting deleted data.
    await _purgeSoftDeletedItems();
    _notifyTasksAndFoldersChanged();
    // Bulk upserts mutate in-memory state without marking individual saves;
    // mark a pending write so flushPersistence serializes the whole batch
    // (including folder-only imports that have no task upserts).
    _saveToPrefs(waitForReady: false);
    await flushPersistence();
  }

  void updateFolder(String id, String newName, {String? iconAsset}) {
    final index = _folders.indexWhere((f) => f.id == id);
    if (index != -1 && !_folders[index].isSystemStreak) {
      if (newName.length > 250) {
        throw const TitleTooLongException();
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

  Future<void> _deleteAttachmentsForTasks(Iterable<TaskItem> tasks) async {
    final paths = <String>{};
    for (final task in tasks) {
      for (final block in task.infoBlocks) {
        for (final attachment in block.attachments) {
          if (attachment.type != TaskAttachmentType.link) {
            paths.add(attachment.value);
          }
        }
      }
    }

    await Future.wait(paths.map((path) => deleteStoredTaskAttachment(path)));
  }

  Future<void> clearAllTasks() async {
    final tasksToClear = List<TaskItem>.of(_tasks);
    await _deleteAttachmentsForTasks(tasksToClear);
    await _deleteCalendarEventsForTasks(tasksToClear);

    final now = DateTime.now();
    for (var i = 0; i < _tasks.length; i++) {
      _tasks[i] = _tasks[i].copyWith(isDeleted: true, updatedAt: now);
    }
    _notifyTasksChanged();
    _saveToPrefs();
  }

  Future<void> clearAllFolders() async {
    final tasksToClear = _tasks
        .where((task) => task.folderId != null)
        .toList(growable: false);
    await _deleteAttachmentsForTasks(tasksToClear);
    await _deleteCalendarEventsForTasks(tasksToClear);

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
      }
    }
    _notifyTasksAndFoldersChanged();
    _saveToPrefs();
  }

  Future<void> clearAllData() async {
    final tasksToClear = List<TaskItem>.of(_tasks);
    await _deleteAttachmentsForTasks(tasksToClear);
    await _deleteCalendarEventsForTasks(tasksToClear);
    await deleteAllStoredTaskAttachments();

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
