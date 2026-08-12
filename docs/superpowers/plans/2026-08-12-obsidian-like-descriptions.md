# Obsidian-like Task Descriptions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evolve ASA descriptions from safe GFM Markdown with attachments into an Obsidian-like, linkable knowledge layer while preserving existing tasks, exports, attachment security, and SharedPreferences data.

**Architecture:** Keep the existing `TaskInfoBlock.text`, `DescriptionFormat`, and JSON format as the source of truth. Add a pure-Dart description parser and index that understand Wikilinks, embeds, tags, callouts, and block references without importing Flutter UI code. Pass resolver callbacks into the existing Markdown renderer, then build the editor toolbar, backlinks, and navigation on top of those stable backend contracts. Use task IDs internally for navigation, but keep user-authored links title/path based so exported data remains readable.

**Tech Stack:** Flutter/Dart 3.7+, `markdown` 7.3.1, `flutter_markdown_plus` 1.0.12, Provider, existing `TaskProvider`, SharedPreferences persistence, existing attachment service, Flutter widget/unit tests.

## Global Constraints

- Do not replace SharedPreferences or introduce a database in this plan; keep the current persistence layer and add bounded in-memory indexes.
- Existing `TaskInfoBlock` JSON must remain readable; new metadata fields must be optional and ignored safely by older builds.
- Existing plain-text descriptions, Markdown descriptions, `@attachment` mentions, links, images, files, exports, and imports must continue to work unchanged.
- Never allow arbitrary `javascript:`, `file:`, data URLs, or unapproved network resources from Markdown or embeds.
- External Markdown images remain disabled by default; only stored ASA attachments may render as interactive content.
- Duplicate task titles must never silently open the wrong task; the resolver must return an explicit ambiguous/unresolved result.
- Keep the current limits: `kMaxTaskDescriptionLength`, `kMaxTaskAttachmentsPerTask`, one description block per task, and existing attachment metadata validation.
- Every implementation task ends with focused tests, `dart analyze`, and a conventional commit. Do not push until the full plan is approved and all milestones pass.

---

## Scope and compatibility decisions

ASA currently has:

- GFM Markdown rendering through `DescriptionBody` in `lib/core/description_markdown.dart`.
- `DescriptionFormat.plainText` and `DescriptionFormat.markdown` in `lib/core/description_format.dart`.
- Attachment metadata and persistence in `TaskInfoBlock`.
- Safe `http`/`https` links, internal `attachment://` mentions, and `@filename` editor suggestions.
- Task/folder persistence and title-only filtering in `TaskProvider`.

The plan closes the largest Obsidian gaps in this order:

1. **Backend foundation:** parse and index document structure without changing stored text.
2. **Internal knowledge links:** `[[Task title]]`, aliases, folder-qualified links, embeds, tags, and deterministic resolution.
3. **Obsidian-like rendering/editing:** callouts, attachment embeds, source/preview mode, and a formatting toolbar.
4. **Knowledge navigation:** backlinks, unresolved-link handling, related tasks, and optional graph data.
5. **Import/export and hardening:** round-trip compatibility, migrations, performance limits, and accessibility/responsive QA.

The first two milestones are useful even without the new UI: search and navigation can consume the backend index, while old descriptions remain valid Markdown.

---

### Task 1: Add a pure description document parser and reference model

**Files:**
- Create: `lib/core/description_document.dart`
- Create: `lib/core/description_reference_parser.dart`
- Modify: `lib/core/description_markdown.dart:14-25` only to re-export the new public types if callers need one import.
- Test: `test/description_reference_parser_test.dart`

**Interfaces:**
- Produces `DescriptionDocument parseDescriptionDocument(String source)`.
- Produces `DescriptionReference` with:
  ```dart
  enum DescriptionReferenceType { wikilink, embed, tag, blockReference }

  class DescriptionReference {
    final DescriptionReferenceType type;
    final String raw;
    final String target;
    final String? alias;
    final int start;
    final int end;
  }
  ```
- Produces `DescriptionCallout` with `kind`, `title`, `bodyStart`, and `bodyEnd` offsets.
- Consumes only strings and existing parser limits; it must not import `BuildContext`, Provider, or `TaskProvider`.

- [ ] **Step 1: Write failing parser tests** for:
  - `[[Read book]]` as a Wikilink.
  - `[[Projects/Read book|open book]]` with a folder-qualified target and alias.
  - `![[photo.png]]` as an embed, not a normal link.
  - `#project/asa` as a tag, while `https://example.com/#project` is not a tag.
  - `^block-id` only when it appears as a block reference outside code.
  - `> [!note] Title` and a multiline callout body.
  - no references inside inline code, fenced code, existing Markdown link labels, or escaped syntax.
  - offsets are UTF-16 Dart string offsets and remain valid for Cyrillic and emoji.
  - malformed/unclosed syntax is returned as ordinary text, never an exception.

- [ ] **Step 2: Run the focused test before implementation**

Run:
```bash
flutter test test/description_reference_parser_test.dart
```
Expected: FAIL because the parser model/functions do not exist yet.

- [ ] **Step 3: Implement the scanner**

Use one bounded left-to-right scanner, reusing the current code/fence protections from `expandAttachmentMentions`. Track fenced code, inline code, escaped characters, Markdown link-label depth, and line boundaries. Emit references in source order and stop scanning after `kMaxTaskDescriptionLength` code points. Do not rewrite the source string in this layer.

- [ ] **Step 4: Run parser tests**

Run:
```bash
flutter test test/description_reference_parser_test.dart test/description_markdown_test.dart
```
Expected: all parser and existing Markdown tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/core/description_document.dart lib/core/description_reference_parser.dart lib/core/description_markdown.dart test/description_reference_parser_test.dart
git commit -m "feat(descriptions): parse internal document references"
```

---

### Task 2: Build a bounded description index and deterministic link resolver

**Files:**
- Create: `lib/features/tasks/services/description_index.dart`
- Create: `lib/features/tasks/services/description_link_resolver.dart`
- Modify: `lib/features/tasks/providers/task_provider.dart` around fields, loading, mutations, and filtered getters.
- Modify: `lib/features/tasks/models/task_model.dart` only if a stable folder-path helper is required; do not change serialized task fields unless tests prove it is necessary.
- Test: `test/description_index_test.dart`
- Test: `test/task_provider_search_test.dart` or the existing `test/task_provider_test.dart`

**Interfaces:**
```dart
class DescriptionSearchResult {
  final TaskItem task;
  final List<String> matchedFields;
  final int score;
}

class DescriptionLinkResolution {
  final String target;
  final TaskItem? task;
  final List<TaskItem> candidates;
  final bool isAmbiguous;
  final bool isUnresolved;
}

class DescriptionIndex {
  void rebuild(Iterable<TaskItem> tasks, Iterable<FolderItem> folders);
  void updateTask(TaskItem task, Iterable<FolderItem> folders);
  void removeTask(String taskId);
  List<DescriptionSearchResult> search(String query);
  DescriptionLinkResolution resolve(String target);
  Set<String> tagsForTask(String taskId);
  Set<String> backlinkTaskIds(String taskId);
}
```

- [ ] **Step 1: Write failing index tests** for exact-title resolution, folder-qualified resolution, aliases (`[[title|label]]`), duplicate-title ambiguity, unresolved targets, tag extraction, backlinks, and search matches in title/description/tags/folder path.

- [ ] **Step 2: Define normalization rules in tests**
  - Unicode-aware case folding with `trim()`.
  - `/`-separated folder path matching from root to leaf.
  - Exact title/path match outranks partial match.
  - Duplicate exact matches return `isAmbiguous=true` and no selected task.
  - Search result scores title > folder path > tags > description, with stable updated-at/id tie-breaking.

- [ ] **Step 3: Implement the index as an in-memory cache**

Index only active tasks and folders. Parse each description with `parseDescriptionDocument`, keep reverse edges for Wikilinks, and store normalized token sets for search. Rebuild after initial load; update incrementally after add/update/delete/import/sync. Put all indexing in the service so `TaskProvider` remains an orchestration layer.

- [ ] **Step 4: Expose provider APIs without breaking current filtering**

Add:
```dart
List<DescriptionSearchResult> searchKnowledge(String query);
DescriptionLinkResolution resolveDescriptionLink(String target);
List<TaskItem> backlinksForTask(String taskId);
Set<String> tagsForTask(String taskId);
```
Keep `filteredInProgressTasks` and `filteredCompletedTasks` behavior unchanged for an empty query. When the Home search field is non-empty, use the new ranked result IDs while preserving active/completed/folder filters.

- [ ] **Step 5: Run focused provider/index tests**

Run:
```bash
flutter test test/description_index_test.dart test/task_provider_test.dart test/task_provider_search_test.dart
```
Expected: all pass with no persistence-format changes.

- [ ] **Step 6: Commit**

```bash
git add lib/features/tasks/services/description_index.dart lib/features/tasks/services/description_link_resolver.dart lib/features/tasks/providers/task_provider.dart lib/features/tasks/models/task_model.dart test/description_index_test.dart test/task_provider_test.dart test/task_provider_search_test.dart
 git commit -m "feat(search): index task descriptions and backlinks"
```

---

### Task 3: Add safe Wikilink, tag, callout, and embed rendering

**Files:**
- Modify: `lib/core/description_markdown.dart`.
- Create: `lib/core/description_render_context.dart`.
- Create: `lib/features/tasks/widgets/description_callout.dart`.
- Modify: `lib/features/tasks/widgets/description_full_sheet.dart`.
- Modify: `lib/features/tasks/widgets/task_detail_sheet.dart`.
- Test: extend `test/description_markdown_test.dart`.
- Test: create `test/description_rendering_test.dart`.

**Interfaces:**
```dart
class DescriptionRenderContext {
  final DescriptionLinkResolution Function(String target)? resolveLink;
  final void Function(DescriptionLinkResolution resolution)? onWikilinkTap;
  final void Function(String tag)? onTagTap;
  final Future<void> Function(TaskAttachment attachment)? onAttachmentEmbedTap;
}
```

- [ ] **Step 1: Write failing widget tests** for a resolved Wikilink, ambiguous link, unresolved link, tag chip, note/warning/tip callout, and `![[attachment]]` image/file embed.

- [ ] **Step 2: Add resolver callbacks to `DescriptionBody`** without importing `TaskProvider` into the core renderer. Existing callers pass no context and retain current behavior.

- [ ] **Step 3: Render links safely**
  - Resolved link: accent style and tap callback to `showTaskDetailSheet`.
  - Ambiguous link: warning style and a chooser sheet listing candidates.
  - Unresolved link: muted dotted style and callback to search/create flow; never create a task implicitly.
  - Keep ordinary `http`/`https` link handling exactly as it is.

- [ ] **Step 4: Render embeds safely**
  - Resolve only existing stored attachments belonging to the current description.
  - Image embeds open the existing image viewer; file embeds open the existing file/text/PDF routes.
  - Missing embeds show a non-crashing placeholder with the original target.
  - External images continue to render as a text placeholder and never trigger a network request.

- [ ] **Step 5: Render callouts and tags**
  - Parse supported callout kinds (`note`, `tip`, `warning`, `important`, `quote`) into a styled bounded container.
  - Unknown callout kinds fall back to a normal blockquote.
  - Tags become accessible tappable chips and feed the index search.

- [ ] **Step 6: Run rendering tests and existing attachment-route tests**

Run:
```bash
flutter test test/description_markdown_test.dart test/description_rendering_test.dart test/task_attachment_routes_integration_test.dart test/task_detail_sheet_test.dart
```
Expected: all pass, including unsafe-link/image protections.

- [ ] **Step 7: Commit**

```bash
git add lib/core/description_markdown.dart lib/core/description_render_context.dart lib/features/tasks/widgets/description_callout.dart lib/features/tasks/widgets/description_full_sheet.dart lib/features/tasks/widgets/task_detail_sheet.dart test/description_markdown_test.dart test/description_rendering_test.dart
 git commit -m "feat(descriptions): render safe wikilinks and callouts"
```

---

### Task 4: Add an Obsidian-like source/preview editor toolbar

**Files:**
- Create: `lib/features/tasks/widgets/description_editor.dart`.
- Create: `lib/features/tasks/widgets/description_toolbar.dart`.
- Modify: `lib/features/tasks/widgets/task_editor_sheet.dart` to replace the inline description `TextFormField` with `DescriptionEditor`.
- Modify: `lib/core/app_strings.dart` for Russian and English labels.
- Test: extend `test/task_editor_sheet_test.dart`.
- Test: create `test/description_editor_test.dart`.

**Interfaces:**
```dart
class DescriptionEditor extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final List<TaskAttachment> attachments;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final int maxLength;
}
```

- [ ] **Step 1: Write failing editor tests** for source/preview toggle, bold/italic/code/list/quote/link insertion around selected text, `[[` link suggestions, `@` attachment suggestions, tags, and preservation of cursor/selection.

- [ ] **Step 2: Implement selection-safe Markdown transformations**

Use a pure helper API:
```dart
TextEditingValue wrapSelection(
  TextEditingValue value,
  String prefix,
  String suffix,
);
TextEditingValue prefixSelectedLines(TextEditingValue value, String prefix);
```
Do not mutate text on focus or on every build. Keep the raw Markdown source in the existing controller so exports remain identical.

- [ ] **Step 3: Implement toolbar and mode toggle**
  - Source mode: existing multiline editor with toolbar.
  - Preview mode: `DescriptionBody` with the same resolver context as the detail sheet.
  - Compact horizontal toolbar that scrolls on narrow screens and has semantics/tooltips.
  - `TextScaler.linear(2.0)` and 320 dp width must remain usable.

- [ ] **Step 4: Integrate attachment and Wikilink suggestions**
  - Reuse current attachment mention logic and overlay patterns.
  - Add `[[` trigger with candidate task titles/folder paths from `TaskProvider`.
  - Insert `[[target]]` or `[[target|display label]]`; never insert internal filesystem paths.

- [ ] **Step 5: Run editor tests**

Run:
```bash
flutter test test/description_editor_test.dart test/task_editor_sheet_test.dart
```
Expected: all old attachment/description tests and new toolbar tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/features/tasks/widgets/description_editor.dart lib/features/tasks/widgets/description_toolbar.dart lib/features/tasks/widgets/task_editor_sheet.dart lib/core/app_strings.dart test/description_editor_test.dart test/task_editor_sheet_test.dart
 git commit -m "feat(editor): add source and preview description modes"
```

---

### Task 5: Add backlinks, related tasks, and tag navigation

**Files:**
- Create: `lib/features/tasks/widgets/description_backlinks.dart`.
- Create: `lib/features/tasks/screens/knowledge_search_screen.dart`.
- Modify: `lib/features/tasks/widgets/task_detail_sheet.dart` to show backlinks and tags only when present.
- Modify: `lib/features/tasks/screens/home_screen.dart` to expose ranked knowledge search.
- Modify: `lib/core/app_strings.dart` for all new labels.
- Test: `test/description_backlinks_test.dart`.
- Test: extend `test/home_screen_test.dart` and `test/task_detail_sheet_test.dart`.

- [ ] **Step 1: Write failing tests** for backlink lists, tag filtering, empty states, ambiguous/unresolved links, and navigation to the selected task.

- [ ] **Step 2: Add a compact backlinks section**
  - Display source task title, folder path, and a short description preview.
  - Use the existing task detail navigation; do not duplicate task-opening logic.
  - Keep the section lazy and bounded so a task with hundreds of backlinks does not render all rows at once.

- [ ] **Step 3: Add knowledge search**
  - Reuse the Home search field and current filter menu.
  - Show match type (title, description, tag, folder) and stable ranked results.
  - Preserve existing task/folder list behavior when the query is empty.

- [ ] **Step 4: Run widget tests**

Run:
```bash
flutter test test/description_backlinks_test.dart test/home_screen_test.dart test/task_detail_sheet_test.dart
```
Expected: navigation works, no duplicate routes, and no narrow-screen overflow.

- [ ] **Step 5: Commit**

```bash
git add lib/features/tasks/widgets/description_backlinks.dart lib/features/tasks/screens/knowledge_search_screen.dart lib/features/tasks/widgets/task_detail_sheet.dart lib/features/tasks/screens/home_screen.dart lib/core/app_strings.dart test/description_backlinks_test.dart test/home_screen_test.dart test/task_detail_sheet_test.dart
 git commit -m "feat(knowledge): add backlinks and tag navigation"
```

---

### Task 6: Make import/export and persistence forward-compatible

**Files:**
- Modify: `lib/features/tasks/models/task_info_block.dart` only if optional description metadata is needed.
- Modify: `lib/core/export_import_service.dart`.
- Modify: `lib/features/tasks/providers/task_provider.dart` to rebuild the index after load/import/sync.
- Modify: `lib/core/export_import_service.dart` to include an optional document metadata section only when needed; existing task JSON remains authoritative.
- Test: extend `test/export_import_service_test.dart`.
- Test: extend `test/task_model_test.dart` and `test/task_provider_test.dart`.

- [ ] **Step 1: Write compatibility tests**
  - Old task JSON without description metadata loads as today.
  - New Wikilinks/tags/callouts round-trip byte-for-byte in `TaskInfoBlock.text`.
  - Attachments retain IDs, names, MIME types, and safe values.
  - Export/import rebuilds backlinks and tags after import.
  - Malformed optional metadata is ignored while valid descriptions remain readable.

- [ ] **Step 2: Implement optional metadata only where it has a concrete consumer**

Do not duplicate the full parsed AST in SharedPreferences. Persist source Markdown and existing attachment records; rebuild the parser/index at load. If stable aliases are introduced, add one optional field with a default empty list:
```dart
final List<String> aliases;
```
Serialize it only for description/task records that use it, and accept missing/non-list values as `const []`.

- [ ] **Step 3: Rebuild index at all mutation boundaries**

Call the index update/rebuild after `_loadFromPrefs`, `addTask`, `updateTask`, `removeTask`, `upsertTask`, import merge, sync merge, and retention purge. Do not write the parsed index to SharedPreferences.

- [ ] **Step 4: Run compatibility tests**

Run:
```bash
flutter test test/export_import_service_test.dart test/task_model_test.dart test/task_provider_test.dart
```
Expected: existing encrypted/plain export flows remain green and new references survive round-trip.

- [ ] **Step 5: Commit**

```bash
git add lib/features/tasks/models/task_info_block.dart lib/core/export_import_service.dart lib/features/tasks/providers/task_provider.dart test/export_import_service_test.dart test/task_model_test.dart test/task_provider_test.dart
 git commit -m "fix(data): preserve description references across import"
```

---

### Task 7: Performance, security, accessibility, and migration hardening

**Files:**
- Modify: `lib/core/description_reference_parser.dart` for parser limits.
- Modify: `lib/features/tasks/services/description_index.dart` for bounded caches and incremental updates.
- Modify: `lib/core/description_markdown.dart` for semantics and link safety.
- Modify: `lib/features/tasks/widgets/description_editor.dart` and `description_toolbar.dart` for adaptive layout.
- Test: create `test/description_limits_test.dart`.
- Test: create `test/description_accessibility_test.dart`.
- Test: extend `test/description_rendering_test.dart`.

- [ ] **Step 1: Add hard limits tests**
  - 10,000-code-point descriptions parse within the test timeout.
  - A large number of references is capped at a documented maximum and does not allocate unbounded widgets.
  - Search index update for a task does not rebuild unrelated tasks.
  - Repeated edit/save does not persist the parsed AST.

- [ ] **Step 2: Add security tests**
  - `javascript:`, `file:`, `data:`, malformed attachment IDs, path traversal, and remote image URLs remain inert.
  - Wikilinks cannot escape the active task/folder resolver or open a deleted task.
  - Unresolved/ambiguous links never create or mutate data implicitly.

- [ ] **Step 3: Add accessibility/adaptive tests**
  - 320 dp portrait and short landscape layouts.
  - `TextScaler.linear(2.0)` and the largest app-scale preset together.
  - Keyboard-open editor with scrollable source and preview modes.
  - Semantics labels for toolbar actions, links, attachments, tags, callouts, and backlinks.

- [ ] **Step 4: Run the complete validation set**

Run:
```bash
dart format lib/core/description_document.dart lib/core/description_reference_parser.dart lib/core/description_render_context.dart lib/features/tasks/services/description_index.dart lib/features/tasks/services/description_link_resolver.dart lib/features/tasks/widgets/description_callout.dart lib/features/tasks/widgets/description_editor.dart lib/features/tasks/widgets/description_toolbar.dart lib/features/tasks/widgets/description_backlinks.dart lib/features/tasks/screens/knowledge_search_screen.dart
dart analyze
flutter test
git diff --check
```
Expected: analyzer has no issues; the full suite passes; no Flutter overflow/rendering diagnostics are emitted.

- [ ] **Step 5: Final review and release notes**
  - Run a read-only code review focused on parser correctness, persistence compatibility, security, and UI constraints.
  - Add a concise entry to `docs/DEVELOPER.md` describing the source Markdown format, supported Obsidian-like syntax, resolution rules, and security restrictions.
  - Bump the app version only after a real release decision; feature implementation alone must not silently change the version.

- [ ] **Step 6: Commit the hardening/documentation milestone**

```bash
git add lib/core/description_document.dart lib/core/description_reference_parser.dart lib/core/description_render_context.dart lib/core/description_markdown.dart lib/features/tasks/services/description_index.dart lib/features/tasks/services/description_link_resolver.dart lib/features/tasks/widgets/description_callout.dart lib/features/tasks/widgets/description_editor.dart lib/features/tasks/widgets/description_toolbar.dart lib/features/tasks/widgets/description_backlinks.dart lib/features/tasks/screens/knowledge_search_screen.dart docs/DEVELOPER.md test
git commit -m "feat(descriptions): harden obsidian-like knowledge features"
```

---

## Acceptance criteria

The implementation is ready for release when all of the following are true:

1. Existing ASA tasks open, edit, export, import, and render exactly as before.
2. A user can write `[[Task title]]`, `[[Folder/Task title|label]]`, `![[attachment.ext]]`, `#tag`, and supported callouts in a description.
3. Resolved links open the correct task; duplicate and unresolved links are explicit and safe.
4. Attachments remain local, validated, clickable, and never expose private paths.
5. Search finds matches in titles, folder paths, descriptions, and tags with stable ranking.
6. Task details show backlinks and tags without loading an unbounded widget tree.
7. Source/preview editing works on narrow screens, large text, landscape, and with the keyboard open.
8. Export/import preserves raw Markdown and attachments and rebuilds the derived index.
9. `dart analyze` is clean and the complete Flutter suite passes without overflow diagnostics.

## Self-review

- **Spec coverage:** parser, resolver, backend index, renderer, editor, backlinks, search, persistence compatibility, security, accessibility, performance, and tests each have a dedicated task.
- **Placeholder scan:** no task relies on an unspecified future API; each introduced interface, file, command, and expected result is named explicitly.
- **Type consistency:** `DescriptionReference`, `DescriptionLinkResolution`, `DescriptionIndex`, `DescriptionRenderContext`, and `DescriptionEditor` are defined before later tasks consume them.
- **Scope control:** the plan does not add a database, network sync, plugin system, or arbitrary external image loading; those are outside the current ASA architecture and would need separate specifications.
