# Secure Task Attachment Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Delete local image and document bytes from the app-owned `task_attachments` directory when tasks or folders are cleared, while leaving URL attachments and external paths untouched.

**Architecture:** Add a platform-conditional deletion API beside the existing attachment read/open APIs. The IO implementation will resolve a path through the existing canonical `task_attachments` boundary and delete only the resolved file; missing files and unsupported platforms are safe no-ops. `TaskProvider` will collect attachment paths before soft-deleting records, await deletion, then persist the updated task/folder state. A full reset will additionally sweep regular files left orphaned in the app-owned attachment directory, while refusing symlink targets outside that directory. The settings sheet will await the asynchronous clear operations before closing the confirmation dialog.

**Tech Stack:** Flutter/Dart, `path_provider`, `dart:io` conditional imports, `SharedPreferences`, Flutter tests.

## Global Constraints

- Only files inside the application documents directory's `task_attachments` directory may be deleted.
- HTTP/HTTPS link attachments never trigger filesystem deletion.
- Missing files, malformed legacy attachment paths, orphan files, and unsupported platforms must not fail a reset operation.
- Existing soft-delete and calendar cleanup behavior must remain intact.
- Preserve unrelated working-tree changes; do not commit automatically.

---

### Task 1: Add secure attachment deletion API

**Files:**
- Modify: `lib/core/task_attachment_service.dart`
- Modify: `lib/core/task_attachment_service_io.dart`
- Modify: `lib/core/task_attachment_service_stub.dart`
- Test: `test/task_attachment_service_test.dart`

**Interfaces:**
- Produce `Future<bool> deleteStoredTaskAttachment(String path)`.
- The function returns `true` only when an existing app-owned file was deleted and `false` for missing, unsafe, malformed, or unsupported paths.

- [ ] **Step 1: Write the failing service test**

Add a test helper that creates a valid PDF through `storeTaskAttachment`, then verifies `deleteStoredTaskAttachment` removes it and that deleting the same path again is safe. Keep the existing external-path rejection test.

- [x] **Step 2: Run the focused attachment tests and verify the new test fails**

Run:

```bash
flutter test --no-pub test/task_attachment_service_test.dart
```

Expected: failure because `deleteStoredTaskAttachment` is not yet defined.

- [x] **Step 3: Implement the platform API**

In the common service, expose `deleteStoredTaskAttachment(String path)` and `deleteAllStoredTaskAttachments()`. In the IO implementation, reuse `_resolveStoredTaskAttachmentFile(path)`, return `false` when it returns `null`, delete the canonical resolved file with `await file.delete()`, return `true`, and catch `Object` to return `false`. The sweep API must recursively inspect the app-owned directory, delete only regular files that pass the same resolver, skip symlinks/directories and external targets, and return the number deleted. In the stub, return `false` and `0` respectively.

- [x] **Step 4: Run the focused attachment tests**

Run:

```bash
flutter test --no-pub test/task_attachment_service_test.dart
```

Expected: all attachment service tests pass.

### Task 2: Clean attachments during provider clear operations

**Files:**
- Modify: `lib/features/tasks/providers/task_provider.dart`
- Test: `test/task_provider_test.dart`

**Interfaces:**
- Change `clearAllTasks`, `clearAllFolders`, and `clearAllData` to `Future<void>`.
- Add a private helper that extracts only non-link attachment values from a task collection and awaits `deleteStoredTaskAttachment` for each path.

- [x] **Step 1: Write failing provider tests**

Add an async test that creates a valid stored PDF attachment, adds a task containing it, awaits `provider.clearAllData()`, and expects `readStoredTaskAttachmentBytes(path)` to return `null`. Add coverage that a link attachment remains valid, an orphan file is removed by `clearAllData`, an outside-target symlink is not followed, and clearing an already-missing local path completes without throwing. Add equivalent cleanup assertions for `clearAllTasks` and `clearAllFolders` using one stored attachment each.

- [x] **Step 2: Run the provider tests and verify the new tests fail**

Run:

```bash
flutter test --no-pub test/task_provider_test.dart
```

Expected: failure because current clear methods do not delete stored files and are synchronous.

- [x] **Step 3: Implement minimal provider cleanup**

Import `task_attachment_service.dart`. Before mutating task/folder records, snapshot the relevant tasks and collect their non-link attachment values. Await deletion with `Future.wait`, then apply the existing soft-delete/calendar logic and call the existing persistence scheduling. `clearAllTasks` uses all tasks; `clearAllFolders` uses all tasks with a folder; `clearAllData` also calls `deleteAllStoredTaskAttachments()` so unreferenced orphan files are removed. Do not delete any link value or any path outside the app-owned directory.

- [x] **Step 4: Update provider call sites and tests for async methods**

Await the three clear methods in `test/task_provider_test.dart`. Update the data-management confirmation callback to accept and await `Future<void>` so the UI does not report completion before file cleanup finishes.

- [x] **Step 5: Run provider and attachment tests**

Run:

```bash
flutter test --no-pub test/task_provider_test.dart test/task_attachment_service_test.dart
```

Expected: all tests pass.

### Task 3: Validate, review, and preserve the working tree

**Files:**
- Inspect: `lib/core/task_attachment_service.dart`
- Inspect: `lib/core/task_attachment_service_io.dart`
- Inspect: `lib/features/tasks/providers/task_provider.dart`
- Inspect: `lib/features/settings/widgets/data_management_bottom_sheet.dart`
- Inspect: `test/task_attachment_service_test.dart`
- Inspect: `test/task_provider_test.dart`

- [x] **Step 1: Format and analyze**

Run:

```bash
dart format lib/core/task_attachment_service.dart lib/core/task_attachment_service_io.dart lib/core/task_attachment_service_stub.dart lib/features/tasks/providers/task_provider.dart lib/features/settings/widgets/data_management_bottom_sheet.dart test/task_attachment_service_test.dart test/task_provider_test.dart
flutter analyze
```

Expected: formatter makes no further changes and analyzer reports no errors.

- [x] **Step 2: Run the complete relevant test set**

Run:

```bash
flutter test --no-pub test/task_provider_test.dart test/task_attachment_service_test.dart test/task_attachment_routes_integration_test.dart
```

Expected: all selected tests pass.

- [x] **Step 3: Run security and diff checks**

Run:

```bash
git diff --check
git status --short
git diff --stat
```

Confirm only the planned files plus the pre-existing attachment-mention changes are present; no secret or generated APK is added. Completed: `dart analyze` and `git diff --check` pass; 79 focused attachment/provider tests pass. The broader route integration set has 8 unrelated pre-existing `timeDilation` isolation failures.

- [x] **Step 4: Review the implementation**

Confirm the IO delete path uses the existing canonical/symlink-aware boundary resolver, links are excluded, missing files are harmless, and persistence/calendar behavior remains unchanged. Resolve any actionable review issue before reporting completion.
