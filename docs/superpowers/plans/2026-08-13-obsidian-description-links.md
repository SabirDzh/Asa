# Obsidian-Like Description Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring ASA task descriptions up to Obsidian parity for four features: clickable block references (`^id` and `[[Task#^id]]`), task transclusion (`![[Task]]`), backlink context snippets, and a WYSIWYG live-preview editor.

**Architecture:** The description pipeline is already three layers: `description_reference_parser.dart` (source → `DescriptionReference`), `description_index.dart` (derived index for resolution/backlinks), and `description_markdown.dart` (source → private-scheme Markdown → `DescriptionLinkBuilder` widgets). We extend each layer in place rather than restructuring: add a `blockId` to references, index block definitions + backlink snippets, render block chips/links and task embeds via new private schemes, and add a transparent-text `TextField` overlay for live editing.

**Tech Stack:** Flutter/Dart, `flutter_markdown_plus` (already used), `markdown` AST, `provider`. No new dependencies.

## Global Constraints

- No new packages. Use only `flutter`, `flutter_markdown_plus`, `markdown`, `provider`, and the existing `package:asa/*` code.
- Stored source text is never mutated: all new behavior is derived at render/index time (matches the existing "prepareDescriptionMarkdown" rewrite approach).
- All user-authored targets stay URI-encoded in private scheme query data (`asa-*://link?value=…`) and are resolved only in the widget layer, matching the existing security model.
- Bounded parsing: `kMaxParsedDescriptionReferences = 256` and `kMaxParsedDescriptionReferences`'s 10k-code-point source cap remain enforced.
- Transclusion recursion is capped at depth 1 (a transcluded description cannot transclude further). This is a hard guard against cycles.
- Tests are the source of truth for behavior; every task is TDD. Run `dart format`, `dart analyze`, and `flutter test <file>` per step.
- Commit after every task with a conventional-commit message ending in the standard Codebuff footer.

---

### Task 1: Parser recognizes block links (`[[Task#^id]]`, `[[#^id]]`, `![[Task#^id]]`)

**Files:**
- Modify: `lib/core/description_document.dart`
- Modify: `lib/core/description_reference_parser.dart`
- Test: `test/description_reference_parser_test.dart`

**Interfaces:**
- Consumes: `DescriptionReferenceType` (existing), `parseDescriptionDocument` (existing).
- Produces: `DescriptionReference.blockId` (`String?`, null for non-block refs). For `[[Task#^id]]` → `type: wikilink`, `target: 'Task'`, `blockId: 'id'`. For `[[#^id]]` → `type: wikilink`, `target: ''`, `blockId: 'id'`. For `![[Task#^id]]` → `type: embed`, `target: 'Task'`, `blockId: 'id'`. Standalone `^id` remains `type: blockReference`, `target: 'id'`, `blockId: null`.

- [ ] **Step 1: Write the failing tests**

Append to `test/description_reference_parser_test.dart` (inside `main`, before the closing `}`):

```dart
  test('parses block links with a task target', () {
    const source = '[[Read book#^intro]] and ![[Read book#^summary]]';

    final refs = parseDescriptionDocument(source).references;

    expect(refs, hasLength(2));
    expect(refs[0].type, DescriptionReferenceType.wikilink);
    expect(refs[0].target, 'Read book');
    expect(refs[0].blockId, 'intro');
    expect(refs[1].type, DescriptionReferenceType.embed);
    expect(refs[1].target, 'Read book');
    expect(refs[1].blockId, 'summary');
  });

  test('parses a same-document block link with an empty target', () {
    const source = 'See [[#^details]] here';

    final ref = parseDescriptionDocument(source).references.single;

    expect(ref.type, DescriptionReferenceType.wikilink);
    expect(ref.target, '');
    expect(ref.blockId, 'details');
  });

  test('keeps standalone ^id as a blockReference without a blockId', () {
    const source = 'A paragraph ^block-id';

    final ref = parseDescriptionDocument(source).references.single;

    expect(ref.type, DescriptionReferenceType.blockReference);
    expect(ref.target, 'block-id');
    expect(ref.blockId, isNull);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/description_reference_parser_test.dart`
Expected: FAIL — the new tests cannot find `refs[0].blockId` (compile error) or get null where a value is expected.

- [ ] **Step 3: Add `blockId` to the model**

In `lib/core/description_document.dart`, add the field and constructor param:

```dart
class DescriptionReference {
  final DescriptionReferenceType type;
  final String raw;
  final String target;
  final String? alias;
  final String? blockId;
  final int start;
  final int end;

  const DescriptionReference({
    required this.type,
    required this.raw,
    required this.target,
    required this.alias,
    this.blockId,
    required this.start,
    required this.end,
  });
```

- [ ] **Step 4: Parse `#^` inside `[[…]]` targets**

In `lib/core/description_reference_parser.dart`, replace the wikilink/embed target-splitting block (currently `final parts = content.split('|'); final target = parts.first.trim();`) and the following `if` gate. The current code is:

```dart
        final content = source.substring(linkStart + 2, close);
        final parts = content.split('|');
        final target = parts.first.trim();
        if (target.isNotEmpty &&
            !target.contains('\n') &&
            !target.contains('[[') &&
            !target.contains('`')) {
          final rawStart = isEmbed ? index : linkStart;
          references.add(
            DescriptionReference(
              type:
                  isEmbed
                      ? DescriptionReferenceType.embed
                      : DescriptionReferenceType.wikilink,
              raw: source.substring(rawStart, close + 2),
              target: target,
              alias:
                  parts.length > 1 && parts[1].trim().isNotEmpty
                      ? parts.sublist(1).join('|').trim()
                      : null,
              start: rawStart,
              end: close + 2,
            ),
          );
          index = close + 2;
          lineStart = false;
          continue;
        } else if (close != -1) {
```

Replace with:

```dart
        final content = source.substring(linkStart + 2, close);
        final parts = content.split('|');
        final rawTarget = parts.first.trim();
        final hashIndex = rawTarget.indexOf('#^');
        final target =
            hashIndex == -1 ? rawTarget : rawTarget.substring(0, hashIndex).trim();
        final blockId =
            hashIndex == -1 ? null : rawTarget.substring(hashIndex + 2).trim();
        final hasValidBlockId =
            blockId != null &&
            blockId.isNotEmpty &&
            RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(blockId);
        if ((target.isNotEmpty || hasValidBlockId) &&
            !rawTarget.contains('\n') &&
            !rawTarget.contains('[[') &&
            !rawTarget.contains('`')) {
          final rawStart = isEmbed ? index : linkStart;
          references.add(
            DescriptionReference(
              type:
                  isEmbed
                      ? DescriptionReferenceType.embed
                      : DescriptionReferenceType.wikilink,
              raw: source.substring(rawStart, close + 2),
              target: target,
              alias:
                  parts.length > 1 && parts[1].trim().isNotEmpty
                      ? parts.sublist(1).join('|').trim()
                      : null,
              blockId: hasValidBlockId ? blockId : null,
              start: rawStart,
              end: close + 2,
            ),
          );
          index = close + 2;
          lineStart = false;
          continue;
        } else if (close != -1) {
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/description_reference_parser_test.dart`
Expected: PASS (all pre-existing + new tests).

- [ ] **Step 6: Commit**

```bash
git add lib/core/description_document.dart lib/core/description_reference_parser.dart test/description_reference_parser_test.dart
git commit -m "$(cat <<'EOF'
feat(description): parse block links and block-id targets

Recognize [[Task#^id]], [[#^id]], and ![[Task#^id]] so the index and
renderer can resolve and render block-level references.

🤖 Generated with Codebuff
Co-Authored-By: Codebuff <noreply@codebuff.com>
EOF
)"
```

---

### Task 2: Index block definitions, block resolution, and backlink snippets

**Files:**
- Modify: `lib/features/tasks/services/description_link_resolver.dart`
- Modify: `lib/features/tasks/services/description_index.dart`
- Modify: `lib/features/tasks/providers/task_provider.dart`
- Test: `test/description_index_test.dart`

**Interfaces:**
- Consumes: `DescriptionReference.blockId` (Task 1), `resolve` (existing), `_referencesByTaskId` (existing).
- Produces:
  - `DescriptionBlockResolution { String blockId; TaskItem? task; String text; bool get isResolved; }`
  - `DescriptionBacklinkContext { TaskItem task; String snippet; }`
  - `DescriptionIndex.resolveBlock(String blockId) → DescriptionBlockResolution`
  - `DescriptionIndex.backlinkSnippets(String taskId) → Map<String, String>` (source task id → snippet)
  - `TaskProvider.resolveDescriptionBlock(String blockId) → DescriptionBlockResolution`
  - `TaskProvider.backlinkContextsForTask(String taskId) → List<DescriptionBacklinkContext>`

- [ ] **Step 1: Write the failing tests**

Append to `test/description_index_test.dart` (inside `main`, after the last test). Also update the existing `readBook`/`writeReport` fixtures to include a block and a block link so the new helpers have data:

```dart
  test('resolves a block definition to its task and paragraph text', () {
    final blockTask = TaskItem(
      id: 'block-owner',
      title: 'Block owner',
      infoBlocks: [
        TaskInfoBlock.description(
          id: 'details',
          text: 'Intro sentence.\n\nDeep paragraph ^key-point',
        ),
      ],
    );
    index.rebuild([readBook, writeReport, blockTask], [projects]);

    final resolution = index.resolveBlock('key-point');

    expect(resolution.isResolved, isTrue);
    expect(resolution.task?.id, 'block-owner');
    expect(resolution.text, 'Deep paragraph');
  });

  test('returns an unresolved block resolution for an unknown id', () {
    final resolution = index.resolveBlock('missing-block');

    expect(resolution.isResolved, isFalse);
    expect(resolution.task, isNull);
  });

  test('returns a backlink snippet around the linking reference', () {
    // writeReport already links [[Projects/Read book|the book]].
    final snippets = index.backlinkSnippets('read-book');

    expect(snippets.keys, contains('write-report'));
    expect(snippets['write-report'], contains('Depends on'));
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/description_index_test.dart`
Expected: FAIL — `resolveBlock` and `backlinkSnippets` are undefined.

- [ ] **Step 3: Add resolution/context types**

In `lib/features/tasks/services/description_link_resolver.dart`, add imports and classes:

```dart
import '../../../core/description_format.dart';
import '../models/task_info_block.dart';
import '../models/task_model.dart';
```

Append after `DescriptionLinkResolution`:

```dart
/// The result of resolving a `^block-id` reference to the task and paragraph
/// that defines it.
class DescriptionBlockResolution {
  final String blockId;
  final TaskItem? task;
  final String text;

  const DescriptionBlockResolution({
    required this.blockId,
    required this.task,
    required this.text,
  });

  bool get isResolved => task != null;
}

/// Content ready to be transcluded inline via `![[Task]]`.
class DescriptionEmbedContent {
  final String text;
  final DescriptionFormat format;
  final List<TaskAttachment> attachments;

  const DescriptionEmbedContent({
    required this.text,
    required this.format,
    required this.attachments,
  });
}

/// A task that links to another task, with the sentence around the link.
class DescriptionBacklinkContext {
  final TaskItem task;
  final String snippet;

  const DescriptionBacklinkContext({required this.task, required this.snippet});
}
```

- [ ] **Step 4: Index blocks and snippets**

In `lib/features/tasks/services/description_index.dart`:

Add fields next to the other `_…ByTaskId` maps:

```dart
  final _blocksByTaskId = <String, Map<String, String>>{};
  final _sourceByTaskId = <String, String>{};
  final _backlinksByTaskId = <String, Map<String, String>>{};
```

Clear the new maps in `rebuild` (next to the existing `.clear()` calls):

```dart
    _blocksByTaskId.clear();
    _sourceByTaskId.clear();
    _backlinksByTaskId.clear();
```

Add the two public methods after `backlinkTaskIds`:

```dart
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
```

In `_indexDescription`, store the source and block map. Replace the existing method body:

```dart
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
```

Add `_parseBlocks` and replace `_rebuildBacklinks` with the snippet-capturing version:

```dart
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
        final snippet = _referenceSnippet(source, reference.start, reference.end);
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
```

Note: keep `backlinkTaskIds` as-is (the provider and `_relatedTasks` still use it).

- [ ] **Step 5: Expose from the provider**

In `lib/features/tasks/providers/task_provider.dart`, after `resolveDescriptionLink`, add:

```dart
  DescriptionBlockResolution resolveDescriptionBlock(String blockId) {
    return _descriptionIndex.resolveBlock(blockId);
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
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/description_index_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/tasks/services/description_link_resolver.dart lib/features/tasks/services/description_index.dart lib/features/tasks/providers/task_provider.dart test/description_index_test.dart
git commit -m "$(cat <<'EOF'
feat(description): index block definitions and backlink snippets

Resolve ^block-id to its defining task and paragraph, and store the
sentence around each backlink so the UI can show link context.

🤖 Generated with Codebuff
Co-Authored-By: Codebuff <noreply@codebuff.com>
EOF
)"
```

---

### Task 3: Render block chips, block links, and task/block transclusion

**Files:**
- Modify: `lib/core/description_render_context.dart`
- Modify: `lib/core/description_markdown.dart`
- Modify: `lib/features/tasks/providers/task_provider.dart`
- Test: `test/description_markdown_test.dart`

**Interfaces:**
- Consumes: `DescriptionBlockResolution`, `DescriptionEmbedContent` (Task 2), `prepareDescriptionMarkdown`, `DescriptionLinkBuilder`, `DescriptionBody` (existing).
- Produces:
  - New private schemes: `kDescriptionBlockScheme = 'asa-block'` (value = block id for standalone `^id`, or value = task target + `block` param for `[[Task#^id]]`), `kDescriptionEmbedScheme = 'asa-embed'` (value = task target), `kDescriptionBlockEmbedScheme = 'asa-embed-block'` (value = task target + `block` param).
  - `DescriptionRenderContext` new fields: `onBlockTap`, `onBlockLinkTap`, `resolveEmbed`, `resolveBlock`.
  - `DescriptionBody` new field: `int embedDepth` (default 0).

- [ ] **Step 1: Write the failing tests**

In `test/description_markdown_test.dart`, add these tests (in the existing `main`, after the existing widget tests). They exercise the new schemes and callbacks through `prepareDescriptionMarkdown` + `DescriptionBody`:

```dart
  test('prepares block references, block links, and task embeds', () {
    final prepared = prepareDescriptionMarkdown(
      '^key-point [[Read book#^intro]] [[#^same]] ![[Read book]] ![[Read book#^note]]',
      const [],
    );

    expect(prepared, contains('asa-block://link?value=key-point'));
    expect(prepared, contains('asa-block://link?value=Read+book&block=intro'));
    expect(prepared, contains('asa-block://link?value=&block=same'));
    expect(prepared, contains('asa-embed://link?value=Read+book'));
    expect(prepared, contains('asa-embed-block://link?value=Read+book&block=note'));
  });

  testWidgets('renders a tappable block chip and block link', (tester) async {
    String? tappedBlock;
    String? tappedBlockLink;
    final target = TaskItem(id: 'read-book', title: 'Read book');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DescriptionBody(
            text: '^key-point and [[Read book#^intro]]',
            format: DescriptionFormat.markdown,
            attachments: const [],
            onAttachmentTap: (_) {},
            onExternalLinkTap: null,
            renderContext: DescriptionRenderContext(
              resolveLink: (value) => DescriptionLinkResolution(
                target: value,
                task: target,
                candidates: [target],
              ),
              onBlockTap: (id) => tappedBlock = id,
              onBlockLinkTap: (resolution, id) => tappedBlockLink = id,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('markdown-block-key-point')));
    expect(tappedBlock, 'key-point');
    await tester.tap(find.byKey(const ValueKey('markdown-block-link-intro')));
    expect(tappedBlockLink, 'intro');
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/description_markdown_test.dart`
Expected: FAIL — `asa-block` scheme not emitted; block chips/links not rendered.

- [ ] **Step 3: Extend `DescriptionRenderContext`**

In `lib/core/description_render_context.dart`:

```dart
import '../features/tasks/services/description_link_resolver.dart';
```

already exists. Add the new callback fields and constructor params:

```dart
class DescriptionRenderContext {
  final DescriptionLinkResolution Function(String target)? resolveLink;
  final void Function(DescriptionLinkResolution resolution)? onWikilinkTap;
  final void Function(String tag)? onTagTap;
  final Future<void> Function(TaskAttachment attachment)? onAttachmentEmbedTap;
  final void Function(String blockId)? onBlockTap;
  final void Function(DescriptionLinkResolution resolution, String blockId)?
  onBlockLinkTap;
  final DescriptionEmbedContent? Function(String target)? resolveEmbed;
  final DescriptionBlockResolution Function(String blockId)? resolveBlock;

  const DescriptionRenderContext({
    this.resolveLink,
    this.onWikilinkTap,
    this.onTagTap,
    this.onAttachmentEmbedTap,
    this.onBlockTap,
    this.onBlockLinkTap,
    this.resolveEmbed,
    this.resolveBlock,
  });
}
```

- [ ] **Step 4: Add schemes and rewrite in `prepareDescriptionMarkdown`**

In `lib/core/description_markdown.dart`, add constants near the existing scheme constants:

```dart
const String kDescriptionBlockScheme = 'asa-block';
const String kDescriptionEmbedScheme = 'asa-embed';
const String kDescriptionBlockEmbedScheme = 'asa-embed-block';
```

Add helpers after `_descriptionInternalHref`:

```dart
String _descriptionBlockHref(String target, String blockId) {
  return '$kDescriptionBlockScheme://link?value=${Uri.encodeQueryComponent(target)}&block=${Uri.encodeQueryComponent(blockId)}';
}

String _descriptionBlockEmbedHref(String target, String blockId) {
  return '$kDescriptionBlockEmbedScheme://link?value=${Uri.encodeQueryComponent(target)}&block=${Uri.encodeQueryComponent(blockId)}';
}

({String value, String? block}) _descriptionBlockValue(
  String href,
  String scheme,
) {
  final uri = Uri.tryParse(href);
  if (uri == null || uri.scheme != scheme) return (value: '', block: null);
  final value = uri.queryParameters['value']?.trim() ?? '';
  final block = uri.queryParameters['block']?.trim();
  return (value: value, block: (block == null || block.isEmpty) ? null : block);
}
```

In `prepareDescriptionMarkdown`, replace the `switch` cases:

```dart
    switch (reference.type) {
      case DescriptionReferenceType.wikilink:
        final label = _escapeMarkdownLabel(
          reference.alias?.trim().isNotEmpty == true
              ? reference.alias!
              : reference.target,
        );
        if (reference.blockId != null) {
          replacements.add((
            start: reference.start,
            end: reference.end,
            value:
                '[$label](${_descriptionBlockHref(reference.target, reference.blockId!)})',
          ));
        } else {
          replacements.add((
            start: reference.start,
            end: reference.end,
            value:
                '[$label](${_descriptionInternalHref(kDescriptionWikilinkScheme, reference.target)})',
          ));
        }
      case DescriptionReferenceType.embed:
        final attachment = _findDescriptionAttachment(
          reference.target,
          attachments,
        );
        final label = _escapeMarkdownLabel(reference.target);
        if (attachment != null) {
          replacements.add((
            start: reference.start,
            end: reference.end,
            value: attachmentEmbedMarkdown(attachment),
          ));
        } else if (reference.blockId != null) {
          replacements.add((
            start: reference.start,
            end: reference.end,
            value:
                '![$label](${_descriptionBlockEmbedHref(reference.target, reference.blockId!)})',
          ));
        } else {
          replacements.add((
            start: reference.start,
            end: reference.end,
            value:
                '![$label](${_descriptionInternalHref(kDescriptionEmbedScheme, reference.target)})',
          ));
        }
      case DescriptionReferenceType.tag:
        final label = _escapeMarkdownLabel(reference.raw);
        replacements.add((
          start: reference.start,
          end: reference.end,
          value:
              '[$label](${_descriptionInternalHref(kDescriptionTagScheme, reference.target)})',
        ));
      case DescriptionReferenceType.blockReference:
        replacements.add((
          start: reference.start,
          end: reference.end,
          value:
              '[${_escapeMarkdownLabel(reference.raw)}](${_descriptionInternalHref(kDescriptionBlockScheme, reference.target)})',
        ));
    }
```

- [ ] **Step 5: Render block chips and block links in `DescriptionLinkBuilder`**

In `DescriptionLinkBuilder.visitElementAfterWithContext`, right after the `href == null` guard and before the wikilink branch, add block handling. Insert:

```dart
    final blockRef = _descriptionBlockValue(href, kDescriptionBlockScheme);
    if (blockRef.block == null && blockRef.value.isNotEmpty) {
      // Standalone ^id chip.
      return _blockRefChip(
        label,
        blockRef.value,
        accentColor,
        onTap:
            renderContext?.onBlockTap == null
                ? null
                : () => renderContext!.onBlockTap!(blockRef.value),
      );
    }
    if (blockRef.block != null) {
      // [[Task#^id]] / [[#^id]] block link.
      final blockId = blockRef.block!;
      if (blockRef.value.isEmpty) {
        return _blockRefChip(
          label,
          blockId,
          accentColor,
          onTap:
              renderContext?.onBlockTap == null
                  ? null
                  : () => renderContext!.onBlockTap!(blockId),
        );
      }
      final resolution =
          renderContext?.resolveLink?.call(blockRef.value) ??
          DescriptionLinkResolution(
            target: blockRef.value,
            task: null,
            candidates: const [],
          );
      final color = resolution.isResolved ? accentColor : Colors.orange;
      return Semantics(
        link: true,
        label: label,
        child: InkWell(
          key: ValueKey('markdown-block-link-$blockId'),
          onTap:
              renderContext?.onBlockLinkTap == null
                  ? null
                  : () => renderContext!.onBlockLinkTap!(resolution, blockId),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link, size: 14, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style:
                      (preferredStyle ?? parentStyle)?.copyWith(
                        color: color,
                        decoration:
                            resolution.isUnresolved
                                ? TextDecoration.underline
                                : TextDecoration.none,
                      ) ??
                      TextStyle(color: color),
                ),
              ),
            ],
          ),
        ),
      );
    }
```

Add the `_blockRefChip` helper method to `DescriptionLinkBuilder` (as a method on the class, after `visitElementAfterWithContext`):

```dart
  Widget _blockRefChip(
    String label,
    String blockId,
    Color color,
    VoidCallback? onTap,
  ) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        key: ValueKey('markdown-block-$blockId'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 6: Render task/block embeds in `imageBuilder`**

In `DescriptionBody`, add `embedDepth`:

```dart
  final int embedDepth;

  const DescriptionBody({
    ...
    this.embedDepth = 0,
  });
```

In `DescriptionBody.build`, replace the `imageBuilder` closure body so that after the attachment lookup it also handles task embeds:

```dart
      imageBuilder: (uri, title, alt) {
        final mention = extractAttachmentMention(uri.toString(), alt ?? '');
        final attachment =
            mention == null
                ? null
                : _findDescriptionAttachment(mention.id, attachments);
        if (attachment != null) {
          return _descriptionAttachmentEmbed(
            attachment,
            alt,
            AppColors.primary,
            renderContext?.onAttachmentEmbedTap,
          );
        }
        final embedValue = _descriptionSchemeValue(
          uri.toString(),
          kDescriptionEmbedScheme,
        );
        if (embedValue != null) {
          return _taskEmbed(embedValue, null, renderContext, embedDepth, textColor, attachments, onAttachmentTap, onExternalLinkTap);
        }
        final blockEmbed = _descriptionBlockValue(
          uri.toString(),
          kDescriptionBlockEmbedScheme,
        );
        if (blockEmbed.block != null) {
          return _taskEmbed(blockEmbed.value, blockEmbed.block, renderContext, embedDepth, textColor, attachments, onAttachmentTap, onExternalLinkTap);
        }
        return Text(
          '[${alt?.trim().isNotEmpty == true ? alt!.trim() : 'image'}]',
        );
      },
```

Add the `_taskEmbed` free function and depth cap constant near the other top-level helpers:

```dart
const int kMaxDescriptionEmbedDepth = 1;

Widget _taskEmbed(
  String target,
  String? blockId,
  DescriptionRenderContext? renderContext,
  int depth,
  Color textColor,
  List<TaskAttachment> attachments,
  DescriptionAttachmentTap onAttachmentTap,
  DescriptionExternalLinkTap? onExternalLinkTap,
) {
  if (depth >= kMaxDescriptionEmbedDepth) {
    return Text('[[$target]]', style: TextStyle(color: textColor));
  }
  if (blockId != null) {
    final block = renderContext?.resolveBlock?.call(blockId);
    if (block == null || !block.isResolved) {
      return _unresolvedEmbed(target.isEmpty ? blockId : '$target#^$blockId');
    }
    return _embedContainer(
      target.isEmpty ? blockId : target,
      DescriptionBody(
        text: block.text,
        format: DescriptionFormat.markdown,
        attachments: const [],
        onAttachmentTap: onAttachmentTap,
        onExternalLinkTap: onExternalLinkTap,
        renderContext: renderContext,
        embedDepth: depth + 1,
      ),
    );
  }
  final content = renderContext?.resolveEmbed?.call(target);
  if (content == null) return _unresolvedEmbed(target);
  return _embedContainer(
    target,
    DescriptionBody(
      text: content.text,
      format: content.format,
      attachments: content.attachments,
      onAttachmentTap: onAttachmentTap,
      onExternalLinkTap: onExternalLinkTap,
      renderContext: renderContext,
      embedDepth: depth + 1,
    ),
  );
}

Widget _embedContainer(String target, Widget child) {
  return Container(
    key: ValueKey('description-embed-$target'),
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 6),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: child,
  );
}

Widget _unresolvedEmbed(String target) {
  return Container(
    key: ValueKey('description-embed-missing-$target'),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Colors.orange.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text('[[$target]]', style: const TextStyle(color: Colors.orange)),
  );
}
```

- [ ] **Step 7: Wire provider embed/block resolution**

In `lib/features/tasks/providers/task_provider.dart`, add after `resolveDescriptionBlock`:

```dart
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
      attachments: [
        for (final block in blocks) ...block.attachments,
      ],
    );
  }
```

(Ensure `DescriptionFormat` is imported: it comes via `task_info_block.dart` which `task_provider.dart` already imports.)

- [ ] **Step 8: Run tests to verify they pass**

Run: `flutter test test/description_markdown_test.dart`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/core/description_render_context.dart lib/core/description_markdown.dart lib/features/tasks/providers/task_provider.dart test/description_markdown_test.dart
git commit -m "$(cat <<'EOF'
feat(description): render block links and task transclusion

Turn ^id into tappable chips, [[Task#^id]] into block links, and
![[Task]] / ![[Task#^id]] into inline embeds with a depth cap.

🤖 Generated with Codebuff
Co-Authored-By: Codebuff <noreply@codebuff.com>
EOF
)"
```

---

### Task 4: Show backlink context snippets

**Files:**
- Modify: `lib/features/tasks/widgets/description_backlinks.dart`
- Modify: `lib/features/tasks/widgets/task_detail_sheet.dart`
- Test: `test/description_backlinks_test.dart`

**Interfaces:**
- Consumes: `TaskProvider.backlinkContextsForTask` (Task 2), `DescriptionBacklinks` (existing).
- Produces: `DescriptionBacklinks.backlinkSnippet` (`String Function(TaskItem task)?`, optional).

- [ ] **Step 1: Write the failing test**

In `test/description_backlinks_test.dart`, add a widget test that verifies the snippet is used as the subtitle for a backlink (the existing tests construct `DescriptionBacklinks` directly):

```dart
  testWidgets('renders a backlink snippet as the subtitle', (tester) async {
    final task = TaskItem(id: 't1', title: 'Read book');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DescriptionBacklinks(
            tags: const {},
            backlinks: [task],
            relatedTasks: const [],
            onTagTap: (_) {},
            onTaskTap: (_) {},
            tagsLabel: 'Tags',
            backlinksLabel: 'Backlinks',
            relatedLabel: 'Related',
            backlinkSnippet: (task) => 'Depends on [[Read book|the book]].',
          ),
        ),
      ),
    );

    expect(find.textContaining('Depends on'), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/description_backlinks_test.dart`
Expected: FAIL — `backlinkSnippet` parameter does not exist.

- [ ] **Step 3: Add the parameter and use it**

In `lib/features/tasks/widgets/description_backlinks.dart`, add the field and constructor param:

```dart
  final String Function(TaskItem task)? backlinkSnippet;
```

Add to the constructor after `taskSubtitle`:

```dart
    this.backlinkSnippet,
```

In `build`, pass a per-list subtitle into `_taskList` for backlinks. Change the `_taskList` signature to accept a `subtitle` function:

```dart
  Widget _taskList(
    BuildContext context,
    List<TaskItem> tasks, {
    required String keyPrefix,
    required String Function(TaskItem task) subtitle,
  }) {
    ...
              subtitle:
                  subtitle(task).isEmpty
                      ? null
                      : Text(subtitle(task), maxLines: 2, overflow: TextOverflow.ellipsis),
    ...
  }
```

Update the two call sites in `build`:

```dart
            _taskList(
              context,
              backlinks,
              keyPrefix: 'backlink',
              subtitle:
                  (task) =>
                      backlinkSnippet?.call(task) ??
                      (taskSubtitle?.call(task) ?? _defaultSubtitle(task)),
            ),
```

and

```dart
            _taskList(
              context,
              relatedTasks,
              keyPrefix: 'related',
              subtitle:
                  (task) => taskSubtitle?.call(task) ?? _defaultSubtitle(task),
            ),
```

- [ ] **Step 4: Wire snippets in the detail sheet**

In `lib/features/tasks/widgets/task_detail_sheet.dart`, in the `Builder` that renders `DescriptionBacklinks`, replace the `backlinks` computation and add `backlinkSnippet`:

```dart
                  builder: (context) {
                    final tags = taskProvider.tagsForTask(currentTask.id);
                    final contexts = taskProvider.backlinkContextsForTask(
                      currentTask.id,
                    );
                    final backlinks = contexts
                        .map((context) => context.task)
                        .toList();
                    final related = _relatedTasks(taskProvider, currentTask);
                    if (tags.isEmpty && backlinks.isEmpty && related.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return DescriptionBacklinks(
                      key: const ValueKey('description-backlinks-section'),
                      tags: tags,
                      backlinks: backlinks,
                      relatedTasks: related,
                      tagsLabel: settings.tr('description_tags'),
                      backlinksLabel: settings.tr('description_backlinks'),
                      relatedLabel: settings.tr('description_related'),
                      taskSubtitle: (task) => _taskSubtitle(context, task),
                      backlinkSnippet: (task) => contexts
                          .firstWhere((context) => context.task.id == task.id)
                          .snippet,
                      ...
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/description_backlinks_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/tasks/widgets/description_backlinks.dart lib/features/tasks/widgets/task_detail_sheet.dart test/description_backlinks_test.dart
git commit -m "$(cat <<'EOF'
feat(description): show backlink context snippets

Backlinks now display the sentence around the link instead of a generic
description preview.

🤖 Generated with Codebuff
Co-Authored-By: Codebuff <noreply@codebuff.com>
EOF
)"
```

---

### Task 5: Navigate to and highlight blocks from the detail/full sheets

**Files:**
- Modify: `lib/core/description_document.dart`
- Modify: `lib/features/tasks/widgets/description_full_sheet.dart`
- Modify: `lib/features/tasks/widgets/task_detail_sheet.dart`
- Test: `test/description_reference_parser_test.dart` (or a new `test/description_block_highlight_test.dart`)

**Interfaces:**
- Consumes: `DescriptionBlockResolution`, `DescriptionEmbedContent` (Task 2), `showFullDescriptionSheet` / `showTaskDetailSheet` (existing).
- Produces:
  - `splitDescriptionAroundBlock(String source, String blockId) → ({String before, String block, String after})?` in `description_document.dart`.
  - `showFullDescriptionSheet(..., {String? highlightBlockId})`
  - `showTaskDetailSheet(context, task, {String? highlightBlockId})`

- [ ] **Step 1: Write the failing test**

Create `test/description_block_highlight_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:asa/core/description_document.dart';

void main() {
  test('splits source around the paragraph defining a block', () {
    const source =
        'First paragraph.\n\nMiddle paragraph ^key\n\nLast paragraph.';

    final parts = splitDescriptionAroundBlock(source, 'key');

    expect(parts, isNotNull);
    expect(parts!.before, 'First paragraph.');
    expect(parts.block, 'Middle paragraph ^key');
    expect(parts.after, 'Last paragraph.');
  });

  test('returns null when the block id is not present', () {
    expect(splitDescriptionAroundBlock('No block here.', 'missing'), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/description_block_highlight_test.dart`
Expected: FAIL — `splitDescriptionAroundBlock` is undefined.

- [ ] **Step 3: Add the split helper**

In `lib/core/description_document.dart`, append:

```dart
({String before, String block, String after})? splitDescriptionAroundBlock(
  String source,
  String blockId,
) {
  final match = RegExp(
    r'(?m)^(.*\^' + RegExp.escape(blockId) + r'\s*)$',
  ).firstMatch(source);
  if (match == null) return null;
  var start = source.lastIndexOf('\n\n', match.start);
  start = start == -1 ? 0 : start + 2;
  var end = source.indexOf('\n\n', match.end);
  end = end == -1 ? source.length : end;
  return (before: source.substring(0, start), block: source.substring(start, end), after: source.substring(end));
}
```

- [ ] **Step 4: Highlight in `DescriptionFullSheet`**

In `lib/features/tasks/widgets/description_full_sheet.dart`:

Add `import 'package:flutter/material.dart';` (already) plus `import '../../../core/description_document.dart';`.

Add `highlightBlockId` to `showFullDescriptionSheet` and `DescriptionFullSheet`:

```dart
Future<void> showFullDescriptionSheet(
  BuildContext context, {
  ...
  String? highlightBlockId,
}) async {
  ...
          child: DescriptionFullSheet(
            ...
            highlightBlockId: highlightBlockId,
          ),
  ...
}

class DescriptionFullSheet extends StatelessWidget {
  ...
  final String? highlightBlockId;

  const DescriptionFullSheet({
    ...
    this.highlightBlockId,
  });
```

Change `DescriptionFullSheet` to a `StatefulWidget` (rename class and add state) so it can scroll after the first frame. Replace the body of the `Expanded > SingleChildScrollView > child:` with a `_HighlightableDescription` widget:

Add a new stateful widget in the same file:

```dart
class _HighlightableDescription extends StatefulWidget {
  final String text;
  final DescriptionFormat format;
  final List<TaskAttachment> attachments;
  final DescriptionAttachmentTap onAttachmentTap;
  final DescriptionExternalLinkTap? onExternalLinkTap;
  final DescriptionRenderContext? renderContext;
  final String? highlightBlockId;

  const _HighlightableDescription({
    required this.text,
    required this.format,
    required this.attachments,
    required this.onAttachmentTap,
    required this.onExternalLinkTap,
    this.renderContext,
    this.highlightBlockId,
  });

  @override
  State<_HighlightableDescription> createState() =>
      _HighlightableDescriptionState();
}

class _HighlightableDescriptionState extends State<_HighlightableDescription> {
  final _scrollController = ScrollController();
  final _highlightKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _highlightKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 200),
          alignment: 0.2,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final highlightId = widget.highlightBlockId;
    if (highlightId == null) {
      return DescriptionBody(
        text: widget.text,
        format: widget.format,
        attachments: widget.attachments,
        onAttachmentTap: widget.onAttachmentTap,
        onExternalLinkTap: widget.onExternalLinkTap,
        renderContext: widget.renderContext,
      );
    }
    final parts = splitDescriptionAroundBlock(widget.text, highlightId);
    if (parts == null) {
      return DescriptionBody(
        text: widget.text,
        format: widget.format,
        attachments: widget.attachments,
        onAttachmentTap: widget.onAttachmentTap,
        onExternalLinkTap: widget.onExternalLinkTap,
        renderContext: widget.renderContext,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (parts.before.trim().isNotEmpty)
          DescriptionBody(
            text: parts.before,
            format: widget.format,
            attachments: widget.attachments,
            onAttachmentTap: widget.onAttachmentTap,
            onExternalLinkTap: widget.onExternalLinkTap,
            renderContext: widget.renderContext,
          ),
        Container(
          key: _highlightKey,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          child: DescriptionBody(
            text: parts.block,
            format: widget.format,
            attachments: widget.attachments,
            onAttachmentTap: widget.onAttachmentTap,
            onExternalLinkTap: widget.onExternalLinkTap,
            renderContext: widget.renderContext,
          ),
        ),
        if (parts.after.trim().isNotEmpty)
          DescriptionBody(
            text: parts.after,
            format: widget.format,
            attachments: widget.attachments,
            onAttachmentTap: widget.onAttachmentTap,
            onExternalLinkTap: widget.onExternalLinkTap,
            renderContext: widget.renderContext,
          ),
      ],
    );
  }
}
```

Then, in `DescriptionFullSheet.build`, replace the `DescriptionBody(...)` inside `SingleChildScrollView` with:

```dart
                child: _HighlightableDescription(
                  text: text,
                  format: format,
                  attachments: attachments,
                  onAttachmentTap: onAttachmentTap,
                  onExternalLinkTap: onExternalLinkTap,
                  renderContext: renderContext,
                  highlightBlockId: highlightBlockId,
                ),
```

- [ ] **Step 5: Navigate from the detail sheet**

In `lib/features/tasks/widgets/task_detail_sheet.dart`:

Change `showTaskDetailSheet`:

```dart
Future<void> showTaskDetailSheet(
  BuildContext context,
  TaskItem task, {
  String? highlightBlockId,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    enableDrag: false,
    builder: (ctx) => DragToCloseSheet(
      trackScrollableDrag: true,
      child: _TaskDetailSheet(task: task, highlightBlockId: highlightBlockId),
    ),
  );
}
```

Add the field to `_TaskDetailSheet`:

```dart
class _TaskDetailSheet extends StatelessWidget {
  final TaskItem task;
  final String? highlightBlockId;

  const _TaskDetailSheet({required this.task, this.highlightBlockId});
```

In `_descriptionRenderContext`, add the new callbacks (and `resolveEmbed`/`resolveBlock`):

```dart
    return DescriptionRenderContext(
      resolveLink: provider.resolveDescriptionLink,
      resolveEmbed: provider.resolveDescriptionEmbed,
      resolveBlock: provider.resolveDescriptionBlock,
      onWikilinkTap: (resolution) { ... existing ... },
      onBlockTap: (blockId) => _openBlock(context, blockId),
      onBlockLinkTap: (resolution, blockId) {
        if (resolution.task != null) {
          unawaited(
            showTaskDetailSheet(
              context,
              resolution.task!,
              highlightBlockId: blockId,
            ),
          );
        }
      },
      onTagTap: (tag) { ... existing ... },
      onAttachmentEmbedTap: (attachment) => _openAttachment(context, attachment),
    );
```

Add the `_openBlock` method:

```dart
  void _openBlock(BuildContext context, String blockId) {
    final provider = context.read<TaskProvider>();
    final resolution = provider.resolveDescriptionBlock(blockId);
    if (!resolution.isResolved) return;
    unawaited(
      showTaskDetailSheet(
        context,
        resolution.task!,
        highlightBlockId: blockId,
      ),
    );
  }
```

In `build`, add a post-frame callback that opens the full description sheet when the current task owns the highlighted block. Add this at the top of `build` (before `return`), guarded so it runs once per sheet open:

```dart
    if (highlightBlockId != null) {
      final block = taskProvider.resolveDescriptionBlock(highlightBlockId!);
      if (block.isResolved && block.task!.id == currentTask.id) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          final description = currentTask.infoBlocks.firstWhere(
            (block) => block.type == TaskInfoBlockType.description,
            orElse: () => TaskInfoBlock.description(id: 'none', text: ''),
          );
          if (description.text.trim().isEmpty) return;
          unawaited(
            showFullDescriptionSheet(
              context,
              text: description.text,
              format: description.descriptionFormat,
              attachments: description.attachments,
              title: settings.tr('full_description'),
              onAttachmentTap: (attachment) => _openAttachment(context, attachment),
              onExternalLinkTap: (href, {title}) => _openExternalLink(context, href, title: title),
              renderContext: _descriptionRenderContext(context),
              highlightBlockId: highlightBlockId,
            ),
          );
        });
      }
    }
```

- [ ] **Step 6: Run tests**

Run: `flutter test test/description_block_highlight_test.dart test/description_markdown_test.dart`
Expected: PASS. Also run `flutter test test/task_detail_sheet_test.dart` if it exists, and `flutter test test/description_full_sheet_test.dart` if it exists, to confirm no regression.

- [ ] **Step 7: Commit**

```bash
git add lib/core/description_document.dart lib/features/tasks/widgets/description_full_sheet.dart lib/features/tasks/widgets/task_detail_sheet.dart test/description_block_highlight_test.dart
git commit -m "$(cat <<'EOF'
feat(description): navigate to and highlight referenced blocks

Tapping ^id or [[Task#^id]] opens the owning task and highlights the
defining block, auto-scrolled into view.

🤖 Generated with Codebuff
Co-Authored-By: Codebuff <noreply@codebuff.com>
EOF
)"
```

---

### Task 6: WYSIWYG live-preview editor

**Files:**
- Modify: `lib/features/tasks/widgets/description_editor.dart`
- Test: `test/description_editor_test.dart`

**Interfaces:**
- Consumes: `DescriptionBody` (existing), `DescriptionEditor` (existing).
- Produces: `DescriptionEditor` gains a third "live" mode (default) rendering markdown in place with a transparent-text `TextField` overlay. Source mode is unchanged.

- [ ] **Step 1: Write the failing test**

In `test/description_editor_test.dart`, add:

```dart
  testWidgets('live preview edits rendered markdown in place', (tester) async {
    final controller = TextEditingController(text: '**hello** world');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DescriptionEditor(
            controller: controller,
            fieldKey: const ValueKey('description-live-field'),
          ),
        ),
      ),
    );

    // Live mode is the default: rendered "hello" is visible and the overlay
    // field is present with transparent text.
    expect(find.byKey(const ValueKey('description-live-field')), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('world'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('description-live-field')),
      '**changed**',
    );
    expect(controller.text, '**changed**');
    expect(find.text('changed'), findsOneWidget);
  });

  testWidgets('can still switch back to source mode', (tester) async {
    final controller = TextEditingController(text: '**hello**');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DescriptionEditor(
            controller: controller,
            fieldKey: const ValueKey('description-field'),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.code));
    await tester.pump();
    expect(find.byKey(const ValueKey('description-field')), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/description_editor_test.dart`
Expected: FAIL — no `description-live-field`, live mode does not exist.

- [ ] **Step 3: Implement live mode in `DescriptionEditor`**

In `lib/features/tasks/widgets/description_editor.dart`, replace `bool _preview = false;` with a mode enum:

```dart
  bool _preview = false;
  bool _live = true;
```

Replace the `SegmentedButton` (two segments: source `false` / preview `true`) with a three-segment control. Replace the segment list and selection handling:

```dart
            child: SegmentedButton<int>(
              key: const ValueKey('description-editor-mode'),
              segments: [
                ButtonSegment<int>(
                  value: 0,
                  label: Text(
                    AppStrings.get('description_source', languageCode),
                  ),
                  icon: const Icon(Icons.code),
                ),
                ButtonSegment<int>(
                  value: 1,
                  label: Text(
                    AppStrings.get('description_live', languageCode),
                  ),
                  icon: const Icon(Icons.edit_outlined),
                ),
                ButtonSegment<int>(
                  value: 2,
                  label: Text(
                    AppStrings.get('description_preview', languageCode),
                  ),
                  icon: const Icon(Icons.visibility_outlined),
                ),
              ],
              selected: {_preview ? 2 : (_live ? 1 : 0)},
              onSelectionChanged: (selection) {
                final value = selection.first;
                setState(() {
                  _live = value == 1;
                  _preview = value == 2;
                });
              },
            ),
```

Add the new string key `description_live` to `lib/core/app_strings.dart` (both maps):

```dart
'description_live': 'Live',   // en
'description_live': 'Живой',  // ru
```

(Use the existing translation-file conventions; add next to `description_preview`.)

Change the mode rendering in `build` so that when `_live` is true (and `!_preview`), a live stack is shown instead of the source `TextFormField`. Replace the `if (!_preview) ... else Container(...)` block with a three-way branch:

```dart
        if (!_preview && !_live) ...[
          if (_showControls)
            DescriptionToolbar(... existing ...),
          TextFormField(... existing source field ...),
        ] else if (_live) ...[
          _LiveDescriptionField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            fieldKey: widget.fieldKey,
            maxLength: widget.maxLength,
            attachments: widget.attachments,
            renderContext: widget.renderContext,
            onAttachmentTap: attachmentTap,
            onExternalLinkTap: linkTap,
            onChanged: widget.onChanged,
          ),
        ] else
          Container(... existing preview ...),
```

Add the `_LiveDescriptionField` widget and its state at the bottom of `description_editor.dart`:

```dart
class _LiveDescriptionField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final Key? fieldKey;
  final int maxLength;
  final List<TaskAttachment> attachments;
  final DescriptionRenderContext? renderContext;
  final DescriptionAttachmentTap onAttachmentTap;
  final DescriptionExternalLinkTap? onExternalLinkTap;
  final ValueChanged<String>? onChanged;

  const _LiveDescriptionField({
    required this.controller,
    this.focusNode,
    this.fieldKey,
    required this.maxLength,
    required this.attachments,
    this.renderContext,
    required this.onAttachmentTap,
    this.onExternalLinkTap,
    this.onChanged,
  });

  @override
  State<_LiveDescriptionField> createState() => _LiveDescriptionFieldState();
}

class _LiveDescriptionFieldState extends State<_LiveDescriptionField> {
  late final FocusNode _focusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focused = _focusNode.hasFocus;
    _focusNode.addListener(_handleFocus);
  }

  @override
  void didUpdateWidget(_LiveDescriptionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocus);
      _focusNode = widget.focusNode ?? FocusNode();
      _focused = _focusNode.hasFocus;
      _focusNode.addListener(_handleFocus);
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  void _handleFocus() {
    if (mounted) setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Container(
      key: const ValueKey('description-editor-live'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: _focused
              ? Theme.of(context).colorScheme.primary
              : textColor.withValues(alpha: 0.18),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          IgnorePointer(
            child: DescriptionBody(
              text: widget.controller.text,
              format: DescriptionFormat.markdown,
              attachments: widget.attachments,
              onAttachmentTap: widget.onAttachmentTap,
              onExternalLinkTap: widget.onExternalLinkTap,
              renderContext: widget.renderContext,
            ),
          ),
          TextField(
            key: widget.fieldKey,
            controller: widget.controller,
            focusNode: _focusNode,
            maxLength: widget.maxLength,
            maxLines: null,
            minLines: 1,
            keyboardType: TextInputType.multiline,
            inputFormatters: [textInputFormatter(maxLength: widget.maxLength)],
            onChanged: widget.onChanged,
            style: const TextStyle(color: Colors.transparent),
            decoration: const InputDecoration(
              border: InputBorder.none,
              counterText: '',
              isCollapsed: true,
            ),
          ),
        ],
      ),
    );
  }
}
```

Note: `TextField` with transparent text keeps the caret and selection highlight visible while the rendered markdown shows through. Markdown syntax is hidden; inline-format length differences cause minor caret drift, which is accepted for this version.

- [ ] **Step 4: Update the existing mode-switch test**

The existing test `switches between source and preview without changing source` taps `Icons.visibility_outlined` (preview) and `Icons.code` (source). Since the default is now live, update it to first switch to source, then preview, asserting the live field appears by default. Rewrite that test to:

```dart
  testWidgets('switches between live, source, and preview modes', (
    tester,
  ) async {
    final controller = TextEditingController(text: '**hello**');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DescriptionEditor(
            controller: controller,
            fieldKey: const ValueKey('description-field'),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('description-editor-live')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.code));
    await tester.pump();
    expect(find.byKey(const ValueKey('description-field')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('description-editor-preview')),
      findsOneWidget,
    );
    expect(controller.text, '**hello**');
  });
```

(Remove the now-obsolete original `switches between source and preview without changing source` test, or replace it with the above.)

- [ ] **Step 5: Run tests**

Run: `flutter test test/description_editor_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/tasks/widgets/description_editor.dart lib/core/app_strings.dart test/description_editor_test.dart
git commit -m "$(cat <<'EOF'
feat(description): add WYSIWYG live-preview editing

Edit rendered markdown in place via a transparent-text overlay, with
source and read-only preview still available.

🤖 Generated with Codebuff
Co-Authored-By: Codebuff <noreply@codebuff.com>
EOF
)"
```

---

### Final verification

- [ ] Run `dart format lib test` then `dart format --output=none --set-exit-if-changed lib test`
- [ ] Run `dart analyze` — expect 0 issues
- [ ] Run `flutter test --concurrency=1` — expect all tests green (note: default-concurrency runs expose a pre-existing flaky `upsertTask keeps newer local task` that also fails on `main`; it is unrelated to this work)

---

## Self-Review

**Spec coverage:** All four requested features are covered — block refs/links (Tasks 1, 3, 5), transclusion (Task 3), backlink context (Tasks 2, 4), live preview (Task 6).

**Placeholder scan:** No TBD/TODO/"add error handling" placeholders; every code step shows the full replacement.

**Type consistency:** `DescriptionBlockResolution`, `DescriptionEmbedContent`, `DescriptionBacklinkContext`, `splitDescriptionAroundBlock`, and the scheme constants (`kDescriptionBlockScheme`, `kDescriptionEmbedScheme`, `kDescriptionBlockEmbedScheme`) are used consistently across tasks. `DescriptionBody.embedDepth` defaults to 0 and is threaded through `_taskEmbed` with `kMaxDescriptionEmbedDepth = 1`.
