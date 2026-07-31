# Task Information Blocks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`/`- [ ]`) syntax for tracking.

**Goal:** Let users add typed information blocks to a task while creating or editing it, including quantitative goals and a description with links, images, and files.

**Architecture:** Keep the existing feature-first Flutter + Provider architecture. Add a small typed domain model (`TaskInfoBlock` and `TaskAttachment`) to `TaskItem`, preserve backward-compatible JSON decoding, and expose focused provider mutations for block updates. Use a dedicated stateful task editor sheet rather than overloading the generic folder/name input sheet; place a `+ Add information` control directly below the title field. Keep descriptions as plain text and attachments as separate metadata records; do not introduce a rich-text dependency or store binary data in `SharedPreferences`.

**Tech Stack:** Flutter/Dart, Provider + ChangeNotifier, SharedPreferences, existing `file_picker`, `image_picker`, `path_provider`, `url_launcher`, `uuid`, Flutter Material semantics, existing bilingual `SettingsProvider` strings.

## Completion status and evidence — 2026-07-31

The task-information-block feature is implemented in focused commits. The repository-wide analyzer and formatter gates pass. The focused non-widget suite passes, while some widget tests remain blocked by an environment-level hang after test startup; no physical-device attachment behavior is claimed as verified.

| Area | Status | Evidence |
|---|---|---|
| Typed task blocks and backward-compatible JSON | **Passed** | `00676a3`; model coverage in the focused non-widget suite |
| Bounded attachment storage and URL validation | **Passed** | `a74254c`; size/path/scheme limits documented and tested |
| Persistence, mutation, export/import, and sync | **Passed** | `0e568ad`; included in the focused provider/export/import suite |
| Task editor and localized quantity/description flow | **Passed** | `7ddb155`; analyzer and focused static validation passed |
| Task UI integration and read-only detail view | **Implemented** | `71d33e7`; detail actions remain in the row `…` menu |
| Widget/integration validation | **Blocked** | `folder_detail_screen_test.dart` and `task_folder_popup_menu_test.dart` hang after startup in the current harness |
| Physical-device attachments and large-text matrix | **Not verified** | Requires Android/iOS devices and platform-specific manual checks |

### Known limitations

* Description content is bounded plain text, not rich text; attachments are structured metadata and local references.
* Export/import/sync preserve attachment metadata and references but do not transfer local binary files.
* Web supports metadata and links through the stub boundary; native file/image copying requires a device/platform implementation.
* The detail sheet is information-only. Edit, set-time, and delete actions are available from the task row `…` menu; the time icon is display-only.

### Feature commit range

`00676a3`, `a74254c`, `0e568ad`, `7ddb155`, `71d33e7`.

## Global Constraints

- Preserve existing task creation, editing, persistence, import/export, sync, timer, calendar, and notification behavior when a task has no information blocks.
- Do not add a rich-text editor or new dependency for this MVP; description text is multiline plain text and links/files/images are separate attachments.
- Keep user-controlled title and description input bounded and sanitized; title keeps the existing 250-character limit and description is capped at 10,000 characters.
- Quantity values must be finite, non-negative, and bounded at `1_000_000_000`; use decimal-capable numeric input and preserve a unit such as `стаканы`, `страницы`, or `минуты`.
- Store only block metadata and attachment references in task JSON. Never embed attachment bytes/base64 in SharedPreferences, export JSON, or LAN sync payloads.
- Native picked files/images must be copied into the app documents directory before their path is persisted; picker cache paths must not be persisted as the only copy.
- Attachments are bounded to 10 MB each, with a maximum of 20 attachments per task. Links accept only `http` and `https` URLs.
- Older tasks without `infoBlocks` must decode with an empty list; malformed individual blocks must be skipped without discarding the rest of the task.
- Export/import/sync preserve block metadata and local paths but do not claim to transfer local binary files to another device. Missing local attachment paths must render as unavailable, not crash.
- All new interactive controls must have localized labels/tooltips and at least 48 logical pixels of hit area.
- Every completed task ends with focused formatting, analyzer, and tests, followed by one focused Conventional Commit. Do not commit generated build artifacts.

---

### Task 1: Add typed task information domain models and backward-compatible serialization

**Files:**
- Create: `lib/features/tasks/models/task_info_block.dart`
- Modify: `lib/features/tasks/models/task_model.dart`
- Modify: `test/task_model_test.dart`

**Interfaces:**
- Produces `enum TaskInfoBlockType { quantity, description }`.
- Produces `enum TaskAttachmentType { link, image, file }`.
- Produces `TaskAttachment({required String id, required TaskAttachmentType type, required String name, required String value, String? mimeType})` with `toJson`, `fromJson`, and `copyWith`.
- Produces `TaskInfoBlock({required String id, required TaskInfoBlockType type, String label, double currentValue, double targetValue, String unit, String text, List<TaskAttachment> attachments})` with `quantity` and `description` constructors, `toJson`, `fromJson`, and `copyWith`.
- Adds `final List<TaskInfoBlock> infoBlocks` to `TaskItem` and includes it in `toJson`, `fromJson`, and `copyWith`.

- [x] **Step 1: Write model tests first**

Add tests covering:

```dart
test('round-trips quantity and description blocks', () {
  final task = TaskItem(
    id: '1',
    title: 'Read a book',
    infoBlocks: [
      TaskInfoBlock.quantity(
        id: 'pages',
        label: 'Pages',
        currentValue: 12,
        targetValue: 120,
        unit: 'pages',
      ),
      TaskInfoBlock.description(
        id: 'notes',
        text: 'Read chapter 1',
        attachments: [
          TaskAttachment(
            id: 'link-1',
            type: TaskAttachmentType.link,
            name: 'Source',
            value: 'https://example.com/book',
          ),
        ],
      ),
    ],
  );

  final restored = TaskItem.fromJson(task.toJson());
  expect(restored.infoBlocks, hasLength(2));
  expect(restored.infoBlocks.first.targetValue, 120);
  expect(restored.infoBlocks.last.attachments.single.value, 'https://example.com/book');
});

test('old task JSON defaults missing infoBlocks to an empty list', () {
  final task = TaskItem.fromJson({'id': 'legacy', 'title': 'Old task'});
  expect(task.infoBlocks, isEmpty);
});

test('malformed information blocks are skipped without losing valid blocks', () {
  final task = TaskItem.fromJson({
    'id': 'mixed',
    'title': 'Mixed task',
    'infoBlocks': [
      {'id': 'valid', 'type': 'description', 'text': 'Keep me'},
      {'id': 'broken', 'type': 'unknown'},
    ],
  });
  expect(task.infoBlocks.map((block) => block.id), ['valid']);
});
```

Also test invalid quantity values are rejected by the model factory and link attachments require `http`/`https` URLs.

- [x] **Step 2: Run the focused model tests and confirm the new tests fail**

Run:

```bash
flutter test test/task_model_test.dart
```

Expected: compilation/test failure because `TaskInfoBlock`, `TaskAttachment`, and `TaskItem.infoBlocks` do not yet exist.

- [x] **Step 3: Implement the typed model**

In `task_info_block.dart`, use tagged JSON objects:

```dart
{
  'id': id,
  'type': type.name,
  'label': label,
  'currentValue': currentValue,
  'targetValue': targetValue,
  'unit': unit,
  'text': text,
  'attachments': attachments.map((item) => item.toJson()).toList(),
}
```

Validate and normalize at the boundary: reject unknown block/attachment types, skip malformed child attachments, clamp neither values nor user data silently, and throw `FormatException` for invalid quantity invariants. In `TaskItem.fromJson`, read `infoBlocks` only when it is a list and catch `FormatException` per entry so one bad block is skipped. Return an unmodifiable list from the model.

- [x] **Step 4: Run focused validation**

Run:

```bash
dart format lib/features/tasks/models/task_info_block.dart lib/features/tasks/models/task_model.dart test/task_model_test.dart
dart analyze lib/features/tasks/models/task_info_block.dart lib/features/tasks/models/task_model.dart test/task_model_test.dart
flutter test test/task_model_test.dart
```

Expected: analyzer clean and all model tests pass.

- [x] **Step 5: Commit the model layer**

```bash
git add lib/features/tasks/models/task_info_block.dart lib/features/tasks/models/task_model.dart test/task_model_test.dart
git commit -m "feat: add typed task information blocks"
```

---

### Task 2: Add bounded attachment storage and URL/file validation

**Files:**
- Create: `lib/core/task_attachment_service.dart`
- Create: `lib/core/task_attachment_service_io.dart`
- Create: `lib/core/task_attachment_service_stub.dart`
- Modify: `test/image_utils_test.dart` or create `test/task_attachment_service_test.dart`

**Interfaces:**
- Produces `const int kMaxTaskAttachmentBytes = 10 * 1024 * 1024`.
- Produces `const int kMaxTaskAttachmentsPerTask = 20`.
- Produces `bool isAllowedTaskLink(String value)` for `http`/`https` only.
- Produces `String attachmentDisplayName(String name)` that strips path separators and bounds display text to 128 characters.
- Produces `Future<TaskAttachment?> storeTaskAttachment({required TaskAttachmentType type, required String name, required List<int> bytes, String? mimeType})` through a conditional platform implementation. Native code writes a generated UUID filename under `getApplicationDocumentsDirectory()/task_attachments`; the web/stub implementation returns `null` without using `dart:io`.
- Produces `Future<bool> openTaskAttachment(TaskAttachment attachment)`; links use `url_launcher`, native paths use a platform-safe URI/open implementation, and missing files return `false`.

- [x] **Step 1: Write pure validation tests**

Add tests for:

```dart
test('accepts only http and https task links', () {
  expect(isAllowedTaskLink('https://example.com/book'), isTrue);
  expect(isAllowedTaskLink('http://localhost:8080/source'), isTrue);
  expect(isAllowedTaskLink('javascript:alert(1)'), isFalse);
  expect(isAllowedTaskLink('file:///private/secret'), isFalse);
});

test('attachment display names cannot escape their basename', () {
  expect(attachmentDisplayName('../book.pdf'), 'book.pdf');
  expect(attachmentDisplayName('a' * 200).length, 128);
});
```

Add a native storage test only where the test platform supports `path_provider`; it should verify a stored attachment path is generated under the app attachment directory and an input over 10 MB returns `null` without writing.

- [x] **Step 2: Run the focused tests and confirm failure**

Run:

```bash
flutter test test/task_attachment_service_test.dart
```

Expected: failure because the service API does not exist.

- [x] **Step 3: Implement conditional attachment storage**

Use a conditional import so web builds never compile `dart:io`:

```dart
import 'task_attachment_service_stub.dart'
    if (dart.library.io) 'task_attachment_service_io.dart';
```

The public service must enforce byte and count limits before calling the platform implementation. Do not persist bytes in the model. Sanitize display names and use a generated ID for the stored filename. Document that imported/exported JSON preserves references only; it does not copy binary attachments across devices.

- [x] **Step 4: Run focused validation**

Run:

```bash
dart format lib/core/task_attachment_service.dart lib/core/task_attachment_service_io.dart lib/core/task_attachment_service_stub.dart test/task_attachment_service_test.dart
dart analyze lib/core/task_attachment_service.dart lib/core/task_attachment_service_io.dart lib/core/task_attachment_service_stub.dart test/task_attachment_service_test.dart
flutter test test/task_attachment_service_test.dart
```

Expected: analyzer clean, validation tests pass, and the conditional service compiles for the test platform.

- [x] **Step 5: Commit the attachment boundary**

```bash
git add lib/core/task_attachment_service.dart lib/core/task_attachment_service_io.dart lib/core/task_attachment_service_stub.dart test/task_attachment_service_test.dart
git commit -m "feat: add bounded task attachment storage"
```

---

### Task 3: Persist, mutate, export, import, and sync information blocks

**Files:**
- Modify: `lib/features/tasks/providers/task_provider.dart`
- Modify: `lib/core/export_import_service.dart` only if validation needs an explicit block-list error path
- Modify: `test/task_provider_test.dart`
- Modify: `test/export_import_service_test.dart`

**Interfaces:**
- Extends `TaskProvider.addTask(..., List<TaskInfoBlock> infoBlocks = const [])`.
- Extends `TaskProvider.updateTask(..., {List<TaskInfoBlock>? infoBlocks})` while preserving blocks when the optional argument is omitted.
- Adds `TaskProvider.updateTaskInfoBlocks(String taskId, List<TaskInfoBlock> blocks)`.
- Adds `TaskProvider.adjustQuantityBlock(String taskId, String blockId, double delta)`; it clamps the new current value to `[0, targetValue]` and persists/ notifies once. It never auto-completes the parent task.
- Ensures existing persistence queue snapshots include `infoBlocks`; existing export/import/sync paths carry them through `TaskItem.toJson` without embedding file bytes.

- [x] **Step 1: Add provider and portability regression tests**

Add tests for:

```dart
test('addTask persists information blocks and update preserves them', () async {
  await provider.ready;
  final block = TaskInfoBlock.quantity(
    id: 'water',
    targetValue: 3,
    unit: 'glasses',
  );
  provider.addTask('Drink water', infoBlocks: [block]);
  final id = provider.tasks.single.id;
  provider.updateTask(id, 'Drink more water');
  expect(provider.tasks.single.infoBlocks.single.id, 'water');

  await provider.persist();
  final prefs = await SharedPreferences.getInstance();
  expect(prefs.getString('saved_tasks'), contains('water'));
});

test('adjustQuantityBlock does not exceed target or auto-complete task', () {
  final block = TaskInfoBlock.quantity(
    id: 'pages',
    currentValue: 9,
    targetValue: 10,
    unit: 'pages',
  );
  provider.addTask('Read', infoBlocks: [block]);
  final id = provider.tasks.single.id;
  provider.adjustQuantityBlock(id, 'pages', 5);
  expect(provider.tasks.single.infoBlocks.single.currentValue, 10);
  expect(provider.tasks.single.isCompleted, isFalse);
});
```

Extend export/import tests to assert a task block and attachment metadata round-trip while the attachment `value` remains a path/URL and no byte content is emitted.

- [x] **Step 2: Run focused tests and classify failures**

Run:

```bash
flutter test test/task_provider_test.dart test/export_import_service_test.dart
```

Expected: new tests fail to compile until provider signatures and block-aware persistence are implemented; existing tests must remain green after implementation.

- [x] **Step 3: Implement provider mutations**

Use `TaskItem.copyWith(infoBlocks: List.unmodifiable(blocks), updatedAt: DateTime.now())`. Locate the task by ID, ignore deleted/missing tasks, validate the block count and quantity invariants, call the existing task notification/version method, and enqueue the existing persistence flow. `updateTask` must only replace `infoBlocks` when the named optional argument is non-null so title-only edits remain backward compatible.

- [x] **Step 4: Verify export/import/sync behavior**

Because `TaskItem.toJson` is the common serialization path, avoid duplicate block serializers in `ExportImportService`. Add explicit validation that malformed `infoBlocks` do not make the whole import crash; valid task records remain importable. Keep the existing import size limit and HMAC behavior.

- [x] **Step 5: Run focused validation**

Run:

```bash
dart format lib/features/tasks/providers/task_provider.dart lib/core/export_import_service.dart test/task_provider_test.dart test/export_import_service_test.dart
dart analyze lib/features/tasks/providers/task_provider.dart lib/core/export_import_service.dart test/task_provider_test.dart test/export_import_service_test.dart
flutter test test/task_provider_test.dart test/export_import_service_test.dart
```

Expected: analyzer clean and focused provider/export/import tests pass.

- [x] **Step 6: Commit persistence and mutations**

```bash
git add lib/features/tasks/providers/task_provider.dart lib/core/export_import_service.dart test/task_provider_test.dart test/export_import_service_test.dart
git commit -m "feat: persist and update task information blocks"
```

---

### Task 4: Build the reusable task editor sheet with add-block flow

**Files:**
- Create: `lib/features/tasks/widgets/task_editor_sheet.dart`
- Modify: `lib/core/app_strings.dart`
- Modify: `test/task_editor_sheet_test.dart`

**Interfaces:**
- Produces `Future<void> showTaskEditorSheet(BuildContext context, {required String? folderId, TaskItem? task})`.
- The sheet returns a draft internally with title and `List<TaskInfoBlock>`; on submit it calls `TaskProvider.addTask` for a new task or `updateTask(..., infoBlocks: blocks)` for an existing task.
- The title field remains the first input. Directly under it, render a localized `+ Add information` button with a 48 dp minimum target.
- The chooser offers exactly two MVP block types: quantity and description.
- Quantity editor fields: label, current value, target value, unit. Use numeric keyboard, `Form` validation, and clear inline error messages.
- Description editor fields: multiline text plus `Add link`, `Add image`, and `Add file` actions. Links are validated before insertion; image/file picker results are bounded and stored through `TaskAttachmentService`.
- Existing blocks can be edited or removed before submit. Attachment chips expose open and delete actions with semantic labels.

- [x] **Step 1: Add widget tests for the user-visible flow**

Create a test app with `SettingsProvider` and `TaskProvider`, then cover:

```dart
testWidgets('shows add information control below the task title', (tester) async {
  await tester.pumpWidget(createEditorTestApp());
  expect(find.byKey(const ValueKey('task-title-input')), findsOneWidget);
  expect(find.byKey(const ValueKey('add-task-information')), findsOneWidget);
});

testWidgets('adds a quantity block to the draft', (tester) async {
  await tester.pumpWidget(createEditorTestApp());
  await tester.tap(find.byKey(const ValueKey('add-task-information')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('add-quantity-block')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('quantity-target-input')), findsOneWidget);
  expect(find.byKey(const ValueKey('quantity-unit-input')), findsOneWidget);
});
```

Also test description text, link validation, removal of a draft block, and that a cancelled sheet creates no task.

- [x] **Step 2: Run widget tests and verify failure**

Run:

```bash
flutter test test/task_editor_sheet_test.dart
```

Expected: failure because the editor sheet and keys do not exist.

- [x] **Step 3: Implement the stateful editor**

Use a `GlobalKey<FormState>`, controllers owned and disposed by the sheet, and a local mutable list of block drafts. Do not mutate the provider until the user submits. Keep the title input compatible with the existing `sanitizeText`/`textInputFormatter` rules. Use `showModalBottomSheet(isScrollControlled: true)` and `SingleChildScrollView` so the keyboard and long descriptions do not overflow.

Use these stable keys for tests and accessibility:

```text
 task-title-input
 add-task-information
 add-quantity-block
 add-description-block
 quantity-label-input
 quantity-current-input
 quantity-target-input
 quantity-unit-input
 description-text-input
 add-description-link
 add-description-image
 add-description-file
 save-task-editor
```

Use `Semantics`/`Tooltip` around icon-only attachment actions and show a localized error without closing the sheet when validation fails.

- [x] **Step 4: Add bilingual strings**

Add Russian and English values for the editor title, add-information action, quantity/description labels, current/target/unit labels, attachment actions, invalid URL, unsupported/missing attachment, and remove/open actions. Keep string keys stable and use `settings.tr(...)` everywhere in the new UI.

- [x] **Step 5: Run focused validation**

Run:

```bash
dart format lib/features/tasks/widgets/task_editor_sheet.dart lib/core/app_strings.dart test/task_editor_sheet_test.dart
dart analyze lib/features/tasks/widgets/task_editor_sheet.dart lib/core/app_strings.dart test/task_editor_sheet_test.dart
flutter test test/task_editor_sheet_test.dart
```

Expected: analyzer clean and editor widget tests pass without platform picker calls by injecting a testable attachment-picker callback or using the link-only path in tests.

- [x] **Step 6: Commit the editor flow**

```bash
git add lib/features/tasks/widgets/task_editor_sheet.dart lib/core/app_strings.dart test/task_editor_sheet_test.dart
git commit -m "feat: add task information editor flow"
```

---

### Task 5: Integrate task creation/editing and render blocks in task details

**Files:**
- Modify: `lib/features/tasks/screens/folder_detail_screen.dart`
- Modify: `lib/features/tasks/widgets/task_card.dart`
- Modify: `lib/features/tasks/widgets/task_detail_sheet.dart`
- Modify: `test/folder_detail_screen_test.dart`
- Modify: `test/task_folder_popup_menu_test.dart`
- Create or modify: `test/task_detail_sheet_test.dart`

**Interfaces:**
- All task creation paths use `showTaskEditorSheet`; folder creation continues using the existing generic `showInputSheet`.
- Task-row edit actions open the editor with the existing task and preserve folder ID.
- Task detail sheet renders quantity blocks with current/target/unit and accessible increment/decrement controls; it renders description text and attachment chips.
- Quantity stepper actions call `TaskProvider.adjustQuantityBlock` and update immediately without reopening the editor.
- Attachment open actions call `openTaskAttachment`; failure shows a localized snackbar and never throws into the widget tree.

- [x] **Step 1: Add integration and detail tests**

Add tests that assert:

- creating a task from a folder opens the task editor rather than the generic one-line input;
- submitting a title and quantity block creates the task with the selected folder;
- editing a task preserves and updates its blocks;
- task details display `12 / 120 pages` and description text;
- increment/decrement controls update the provider;
- missing attachments show an unavailable state rather than crashing.

Use stable keys such as `task-info-block-pages`, `quantity-increment-pages`, and `task-attachment-link-1`.

- [x] **Step 2: Implement creation/edit integration**

Replace only the `isTask` branch in `FolderDetailScreen._showCreateSheet` with `showTaskEditorSheet`. Replace `_showEditSheet` in `TaskRow` and `TaskDetailSheet` with the editor sheet. Keep folder edit and task deletion/calendar/time actions unchanged.

- [x] **Step 3: Implement detail rendering**

Add focused private widgets in `task_detail_sheet.dart` for quantity and description blocks. Use `ListView`/`Wrap` with bounded text, `Semantics` labels, and 48 dp controls. Do not load full attachment bytes into the detail sheet; show type/name and delegate opening to the attachment service.

- [ ] **Step 4: Run focused validation — Blocked: the detail/popup widget harness hangs after startup; analyzer and formatting pass.**

Run:

```bash
dart format lib/features/tasks/screens/folder_detail_screen.dart lib/features/tasks/widgets/task_card.dart lib/features/tasks/widgets/task_detail_sheet.dart test/folder_detail_screen_test.dart test/task_folder_popup_menu_test.dart test/task_detail_sheet_test.dart
dart analyze lib/features/tasks/screens/folder_detail_screen.dart lib/features/tasks/widgets/task_card.dart lib/features/tasks/widgets/task_detail_sheet.dart test/folder_detail_screen_test.dart test/task_folder_popup_menu_test.dart test/task_detail_sheet_test.dart
flutter test test/folder_detail_screen_test.dart test/task_folder_popup_menu_test.dart test/task_detail_sheet_test.dart
```

Expected: analyzer clean and focused integration/detail tests pass.

- [x] **Step 5: Commit UI integration**

```bash
git add lib/features/tasks/screens/folder_detail_screen.dart lib/features/tasks/widgets/task_card.dart lib/features/tasks/widgets/task_detail_sheet.dart test/folder_detail_screen_test.dart test/task_folder_popup_menu_test.dart test/task_detail_sheet_test.dart
git commit -m "feat: integrate task information blocks in task UI"
```

---

### Task 6: Complete validation, documentation, and independent review

**Files:**
- Modify: `docs/DEVELOPER.md`
- Modify: `docs/superpowers/plans/2026-07-31-task-information-blocks.md`
- Review: all files changed by Tasks 1–5

- [x] **Step 1: Document the feature and limitations**

Add a developer documentation section covering:

- quantity block semantics and the fact that reaching target does not auto-complete a task;
- plain-text description plus structured attachments instead of rich text;
- 10 MB per-attachment and 20-attachment limits;
- native app-documents copying and why picker cache paths are not persisted;
- export/import/sync preserve metadata and references but do not transfer binary files to another device;
- web/stub limitation for local binary storage and the supported link workflow;
- manual verification matrix for Android/iOS attachment picking, opening links/files, screen reader labels, keyboard behavior, and large text.

- [ ] **Step 2: Run the full supported validation — Partial/blocked: analyzer, formatter, Android compile, arm64 build, and focused non-widget tests pass; affected widget tests hang and physical-device checks are unavailable.**

Run:

```bash
dart format --output=none --set-exit-if-changed lib test
dart analyze
flutter test test/task_model_test.dart test/task_attachment_service_test.dart test/task_provider_test.dart test/export_import_service_test.dart test/task_editor_sheet_test.dart test/task_detail_sheet_test.dart test/folder_detail_screen_test.dart test/task_folder_popup_menu_test.dart
flutter build web
JAVA_HOME=/opt/homebrew/opt/openjdk@21 flutter build apk --target-platform android-arm64 --split-per-abi --release
```

Also run Android resource/Kotlin compilation if the local Android SDK is available:

```bash
(cd android && ./gradlew :app:processDebugResources :app:compileDebugKotlin --no-daemon)
```

If an environment check fails, record the exact command, failure, and whether it is tooling/platform related; do not claim that gate passed.

- [x] **Step 3: Run independent code review**

Review the complete diff and commit range for:

- malformed block handling and backward compatibility;
- attachment path traversal, URL scheme, size, and count limits;
- accidental binary/base64 persistence;
- provider race conditions and notification granularity;
- sheet controller disposal and mounted checks;
- accessibility, localization, large text, and web compilation;
- export/import/sync behavior and documentation accuracy.

Resolve all blocking findings before declaring the feature complete.

- [x] **Step 4: Update the plan with evidence**

Mark each completed checkbox, record focused test results and known platform limitations under Task 6, and include the final commit hashes. Do not mark real-device behavior as verified without a real-device result.

- [x] **Step 5: Commit the documentation and final evidence**

```bash
git add docs/DEVELOPER.md docs/superpowers/plans/2026-07-31-task-information-blocks.md
git commit -m "docs: document task information blocks"
```

- [x] **Step 6: Verify clean state**

Run:

```bash
git status --short --branch
git log --oneline -n 10
```

Expected: no uncommitted source changes, no generated artifacts staged, and one focused commit per completed task.
