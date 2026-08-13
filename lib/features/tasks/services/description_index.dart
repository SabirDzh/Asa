import '../../../core/description_document.dart';
import '../../../core/description_reference_parser.dart';
import '../models/task_info_block.dart';
import '../models/task_model.dart';
import 'description_link_resolver.dart';

/// Prevents a broad query from materializing an unbounded result list in UI.
const int kMaxDescriptionSearchResults = 200;

class DescriptionSearchResult {
  final TaskItem task;
  final List<String> matchedFields;
  final int score;

  const DescriptionSearchResult({
    required this.task,
    required this.matchedFields,
    required this.score,
  });
}

/// Bounded, rebuildable index for task descriptions.
///
/// The index is derived state and is intentionally not persisted. Source text
/// and attachment metadata remain the only durable representation.
class DescriptionIndex {
  final _tasksById = <String, TaskItem>{};
  final _folderPathsById = <String, String?>{};
  final _referencesByTaskId = <String, List<DescriptionReference>>{};
  final _tagsByTaskId = <String, Set<String>>{};
  final _blocksByTaskId = <String, Map<String, String>>{};
  final _sourceByTaskId = <String, String>{};
  final _backlinksByTaskId = <String, Map<String, String>>{};

  void rebuild(Iterable<TaskItem> tasks, Iterable<FolderItem> folders) {
    _tasksById.clear();
    _referencesByTaskId.clear();
    _tagsByTaskId.clear();
    _blocksByTaskId.clear();
    _sourceByTaskId.clear();
    _backlinksByTaskId.clear();
    _rebuildFolderPaths(folders);

    for (final task in tasks) {
      if (!task.isDeleted) _indexTask(task);
    }
    _rebuildBacklinks();
  }

  void updateTask(TaskItem task, Iterable<FolderItem> folders) {
    _rebuildFolderPaths(folders);
    if (task.isDeleted) {
      removeTask(task.id);
      return;
    }
    _tasksById[task.id] = task;
    _indexDescription(task);
    _rebuildBacklinks();
  }

  void removeTask(String taskId) {
    _tasksById.remove(taskId);
    _referencesByTaskId.remove(taskId);
    _tagsByTaskId.remove(taskId);
    _blocksByTaskId.remove(taskId);
    _sourceByTaskId.remove(taskId);
    _backlinksByTaskId.remove(taskId);
    for (final sources in _backlinksByTaskId.values) {
      sources.remove(taskId);
    }
    _rebuildBacklinks();
  }

  List<DescriptionSearchResult> search(String query) {
    final normalizedQuery = _normalize(query).replaceFirst(RegExp(r'^#+'), '');
    if (normalizedQuery.isEmpty) return const [];

    final results = <DescriptionSearchResult>[];
    for (final task in _tasksById.values) {
      final fields = <String>[];
      var score = 0;
      final title = _normalize(task.title);
      final folderPath = _normalize(_folderPathForTask(task));
      final description = _normalize(_descriptionText(task));
      final tags = _tagsByTaskId[task.id] ?? const <String>{};

      final titleScore = _fieldScore(
        title,
        normalizedQuery,
        exact: 1000,
        startsWith: 900,
        contains: 800,
      );
      if (titleScore > 0) {
        fields.add('title');
        score = score > titleScore ? score : titleScore;
      }
      final folderScore = _fieldScore(
        folderPath,
        normalizedQuery,
        exact: 700,
        startsWith: 650,
        contains: 600,
      );
      if (folderScore > 0) {
        fields.add('folder');
        score = score > folderScore ? score : folderScore;
      }
      if (tags.any((tag) => tag.contains(normalizedQuery))) {
        fields.add('tag');
        score = score > 500 ? score : 500;
      }
      final descriptionScore = _fieldScore(
        description,
        normalizedQuery,
        exact: 400,
        startsWith: 350,
        contains: 300,
      );
      if (descriptionScore > 0) {
        fields.add('description');
        score = score > descriptionScore ? score : descriptionScore;
      }
      if (score > 0) {
        results.add(
          DescriptionSearchResult(
            task: task,
            matchedFields: List.unmodifiable(fields),
            score: score,
          ),
        );
        // Keep the working set bounded while scanning, not only at return
        // time. This prevents a broad query from retaining every match until
        // after sorting, even when the caller only needs the top K results.
        if (results.length > kMaxDescriptionSearchResults) {
          results.sort(_compareSearchResults);
          results.removeLast();
        }
      }
    }

    results.sort(_compareSearchResults);
    return List.unmodifiable(results);
  }

  static int _compareSearchResults(
    DescriptionSearchResult a,
    DescriptionSearchResult b,
  ) {
    final scoreOrder = b.score.compareTo(a.score);
    if (scoreOrder != 0) return scoreOrder;
    final updatedOrder = b.task.updatedAt.compareTo(a.task.updatedAt);
    if (updatedOrder != 0) return updatedOrder;
    return a.task.id.compareTo(b.task.id);
  }

  DescriptionLinkResolution resolve(String target) {
    final normalizedTarget = _normalize(target);
    if (normalizedTarget.isEmpty) {
      return DescriptionLinkResolution(
        target: target,
        task: null,
        candidates: const [],
      );
    }

    final candidates =
        _tasksById.values.where((task) {
          final title = _normalize(task.title);
          if (!normalizedTarget.contains('/')) return title == normalizedTarget;
          return _normalize(_qualifiedTaskPath(task)) == normalizedTarget;
        }).toList();

    return DescriptionLinkResolution(
      target: target,
      task: candidates.length == 1 ? candidates.single : null,
      candidates: List.unmodifiable(candidates),
    );
  }

  Set<String> tagsForTask(String taskId) {
    return Set.unmodifiable(_tagsByTaskId[taskId] ?? const <String>{});
  }

  Set<String> backlinkTaskIds(String taskId) {
    return Set.unmodifiable(
      (_backlinksByTaskId[taskId] ?? const <String, String>{}).keys,
    );
  }

  DescriptionBlockResolution resolveBlock(String blockId) {
    for (final entry in _blocksByTaskId.entries) {
      final text = entry.value[blockId];
      if (text == null) continue;
      final task = _tasksById[entry.key];
      if (task != null) {
        return DescriptionBlockResolution(
          blockId: blockId,
          task: task,
          text: text,
        );
      }
    }
    return DescriptionBlockResolution(blockId: blockId, task: null, text: '');
  }

  Map<String, String> backlinkSnippets(String taskId) {
    return Map.unmodifiable(
      _backlinksByTaskId[taskId] ?? const <String, String>{},
    );
  }

  void _indexTask(TaskItem task) {
    _tasksById[task.id] = task;
    _indexDescription(task);
  }

  void _indexDescription(TaskItem task) {
    final text = _descriptionText(task);
    final document = parseDescriptionDocument(text);
    _referencesByTaskId[task.id] = document.references;
    _sourceByTaskId[task.id] = text;
    _blocksByTaskId[task.id] = _parseBlocks(text);
    _tagsByTaskId[task.id] = {
      for (final reference in document.references)
        if (reference.type == DescriptionReferenceType.tag)
          _normalize(reference.target),
    };
  }

  Map<String, String> _parseBlocks(String source) {
    final blocks = <String, String>{};
    final paragraphs = source.split(RegExp(r'\n\s*\n'));
    for (final paragraph in paragraphs) {
      final lines = paragraph.split('\n');
      final last = lines.last.trimRight();
      final match = RegExp(r'\^([A-Za-z0-9_-]+)\s*$').firstMatch(last);
      if (match == null) continue;
      final blockId = match.group(1)!;
      final cleanedLines = <String>[
        ...lines.sublist(0, lines.length - 1),
        last.substring(0, match.start),
      ];
      blocks[blockId] = cleanedLines.join('\n').trim();
    }
    return blocks;
  }

  void _rebuildBacklinks() {
    _backlinksByTaskId.clear();
    for (final entry in _referencesByTaskId.entries) {
      final sourceId = entry.key;
      final source = _sourceByTaskId[sourceId] ?? '';
      for (final reference in entry.value) {
        if (reference.type != DescriptionReferenceType.wikilink) continue;
        final resolution = resolve(reference.target);
        if (!resolution.isResolved || resolution.task!.id == sourceId) {
          continue;
        }
        final snippet = _referenceSnippet(
          source,
          reference.start,
          reference.end,
        );
        _backlinksByTaskId
            .putIfAbsent(resolution.task!.id, () => <String, String>{})
            .putIfAbsent(sourceId, () => snippet);
      }
    }
  }

  String _referenceSnippet(String source, int start, int end) {
    if (source.isEmpty) return '';
    final lineStart = source.lastIndexOf('\n', start) + 1;
    var lineEnd = source.indexOf('\n', end);
    if (lineEnd == -1) lineEnd = source.length;
    final line = source.substring(lineStart, lineEnd).trim();
    final cleaned = line.replaceAll(RegExp(r'[\[\]|]'), '');
    return _truncateCodePoints(cleaned.replaceAll(RegExp(r'\s+'), ' '), 120);
  }

  String _truncateCodePoints(String value, int maxCodePoints) {
    final codePoints = value.runes.toList();
    if (codePoints.length <= maxCodePoints) return value;
    return '${String.fromCharCodes(codePoints.take(maxCodePoints))}…';
  }

  void _rebuildFolderPaths(Iterable<FolderItem> folders) {
    final byId = {
      for (final folder in folders)
        if (!folder.isDeleted) folder.id: folder,
    };
    _folderPathsById.clear();
    for (final folder in byId.values) {
      _folderPathsById[folder.id] = _buildFolderPath(folder, byId, <String>{});
    }
  }

  String? _buildFolderPath(
    FolderItem folder,
    Map<String, FolderItem> byId,
    Set<String> visited,
  ) {
    // A cyclic legacy hierarchy has no meaningful qualified path. Propagate
    // null to every descendant so a Wikilink cannot resolve through a path
    // fabricated from the cycle boundary.
    if (!visited.add(folder.id)) return null;
    final parentId = folder.parentFolderId;
    if (parentId == null || !byId.containsKey(parentId)) return folder.name;
    final parentPath = _buildFolderPath(byId[parentId]!, byId, visited);
    if (parentPath == null) return null;
    return '$parentPath/${folder.name}';
  }

  String _folderPathForTask(TaskItem task) {
    if (task.folderId == null) return '';
    return _folderPathsById[task.folderId!] ?? '';
  }

  String _qualifiedTaskPath(TaskItem task) {
    final folderPath = _folderPathForTask(task);
    return folderPath.isEmpty ? task.title : '$folderPath/${task.title}';
  }

  String _descriptionText(TaskItem task) {
    return task.infoBlocks
        .where((block) => block.type == TaskInfoBlockType.description)
        .map((block) => block.text)
        .join('\n');
  }

  int _fieldScore(
    String field,
    String query, {
    required int exact,
    required int startsWith,
    required int contains,
  }) {
    if (field.isEmpty || !field.contains(query)) return 0;
    if (field == query) return exact;
    if (field.startsWith(query)) return startsWith;
    return contains;
  }

  String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
