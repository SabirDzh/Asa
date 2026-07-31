# Full Functional Audit and Verification Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`/`- [ ]`) syntax for tracking.

**Goal:** Verify every user-facing ASA function across valid inputs, invalid inputs, cancellation, permissions, lifecycle, persistence, and platform outcomes; fix only reproducible defects; document evidence and produce a verified arm64-v8a release APK.

**Architecture:** Treat the audit as a layered verification campaign rather than a rewrite. Pure model/provider/service behavior is covered with deterministic Flutter tests; UI behavior is covered with focused widget tests and targeted manual/device scenarios; native integrations are tested on the connected Android device when available. Every defect must have a reproducer, a minimal fix, a regression test or platform evidence, and its own focused commit.

**Tech Stack:** Flutter/Dart, Provider, SharedPreferences, Flutter widget tests, Android Gradle/Kotlin, ADB, `flutter_local_notifications`, `device_calendar`, `home_widget`, `file_picker`, `image_picker`, `url_launcher`, mDNS/TCP sync.

## Global Constraints

- Preserve existing public APIs and product behavior unless a reproducible defect requires a change.
- Never claim a physical-device or native integration scenario passed without device evidence.
- A cancelled picker, denied permission, unavailable file, unsupported platform, malformed input, timeout, and failed platform call must produce a safe user-visible or documented outcome without data loss.
- User data must remain bounded, sanitized, backward-compatible, and persisted only after validated mutations.
- Do not commit APKs, keystores, `android/key.properties`, logs containing secrets, or generated build artifacts.
- Run `dart format --output=none --set-exit-if-changed` and `dart analyze` for every changed Dart batch.
- Every audit task ends with focused verification and a separate conventional commit, even when the task changes only tests/docs.
- Full `flutter test` is not considered passing if the known widget-test hang reproduces; record the exact timeout and continue with isolated evidence.

## Evidence and outcome vocabulary

Use these statuses in the final report and plan checkboxes:

- **PASS:** behavior observed and assertion/evidence completed.
- **FAIL:** reproducible defect fixed with regression coverage.
- **BLOCKED:** required external device, permission, platform, or test harness is unavailable; include the exact command and reason.
- **NOT APPLICABLE:** feature is intentionally unavailable on the tested platform; verify the fallback.

For each scenario record: setup, user action, expected result, observed result, evidence command/test/device log, and whether data changed.

---

### Task 1: Establish the audit matrix, baseline, and test harness health

**Files:**
- Create: `docs/superpowers/plans/2026-07-31-full-functional-audit.md` (this plan)
- Create: `docs/superpowers/reports/2026-07-31-full-functional-audit.md`
- Test: all existing test files and project static gates

**Interfaces:**
- Consumes: current source/test inventory, existing remediation documentation, current APK artifact.
- Produces: a living evidence report, baseline test results, device/toolchain availability, and a list of known blocked scenarios.

- [x] **Step 1: Capture repository and environment baseline**

Run:

```bash
git status --short --branch
git log --oneline -n 12
dart format --output=none --set-exit-if-changed .
dart analyze
flutter pub deps --style=compact
adb devices -l
flutter devices
```

Record the exact outputs relevant to availability, without recording secrets or personal device data beyond a stable anonymized device label.

- [x] **Step 2: Run the existing test suite in isolated groups**

Run pure/service groups separately so a hanging widget test cannot hide results:

```bash
flutter test --no-pub test/input_utils_test.dart test/task_model_test.dart test/task_provider_test.dart test/settings_provider_test.dart test/export_import_service_test.dart test/sync_service_test.dart test/notification_service_test.dart test/image_utils_test.dart test/task_attachment_service_test.dart test/logger_service_test.dart test/home_widget_service_test.dart -r compact
flutter test --no-pub test/home_screen_test.dart -r compact
perl -e 'alarm 300; exec @ARGV' -- flutter test --no-pub test/task_editor_sheet_test.dart -r compact
perl -e 'alarm 300; exec @ARGV' -- flutter test --no-pub test/task_folder_popup_menu_test.dart -r compact
```

Expected: non-widget groups report exact pass counts; any timeout is recorded as **BLOCKED**, not passed.

- [x] **Step 3: Create the report skeleton and matrix columns**

Create `docs/superpowers/reports/2026-07-31-full-functional-audit.md` with this exact structure before filling results:

```markdown
# ASA Full Functional Audit Report

**Date:** 2026-07-31
**Branch:** `fix/review-remediation`
**APK under test:** `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
**Audit baseline commit:** record `git rev-parse HEAD` here before the first audit commit.

## Result vocabulary
PASS / FAIL-fixed / BLOCKED / NOT APPLICABLE

## Functional matrix
| Function | Valid cases | Invalid/boundary cases | Cancel/permission cases | Lifecycle/offline cases | Automated evidence | Device evidence | Result | Defect/commit |
|---|---|---|---|---|---|---|---|---|

## Automated command evidence

## Android device evidence

## Fixed defects

## Blocked scenarios and unresolved risks
```

Every later task appends observations to this report instead of replacing prior evidence.

- [x] **Step 4: Commit the audit baseline**

Before committing, write the current `git rev-parse HEAD` value into the report's `Audit baseline commit` line. Then run:

```bash
git add docs/superpowers/plans/2026-07-31-full-functional-audit.md docs/superpowers/reports/2026-07-31-full-functional-audit.md
git commit -m "test: establish functional audit baseline"
```


---

### Task 2: Audit task, folder, search, filter, ordering, streak, and navigation behavior

**Files:**
- Inspect/modify only if a defect is reproduced: `lib/features/tasks/providers/task_provider.dart`, `lib/features/tasks/models/task_model.dart`, `lib/features/tasks/screens/home_screen.dart`, `lib/features/tasks/screens/folder_detail_screen.dart`, `lib/features/tasks/widgets/task_card.dart`, `lib/features/tasks/widgets/folder_card.dart`
- Test: `test/task_provider_test.dart`, `test/task_model_test.dart`, `test/home_screen_test.dart`, `test/folder_detail_screen_test.dart`, `test/task_folder_popup_menu_test.dart`
- Report: `docs/superpowers/reports/2026-07-31-full-functional-audit.md`

**Interfaces:**
- Consumes: `TaskProvider` CRUD/filter/reorder/timer APIs and existing screen navigation.
- Produces: regression tests/evidence for every task/folder state transition and safe UI behavior.

- [x] **Step 1: Verify valid task/folder flows**

Exercise and assert:

- create a root task, a folder task, a root folder, and nested folders;
- edit title/icon and confirm persistence after provider reload;
- complete and uncomplete a task; confirm completed/active lists and timer stop semantics;
- soft-delete task/folder and confirm hidden state, descendant cascade, and calendar cleanup call path;
- move task/folder, reorder first/middle/last items, and verify invalid indices do not mutate state;
- search title/folder with empty, case-different, whitespace, partial, and no-match queries;
- apply every `TaskFilter` and confirm folder/task visibility;
- open home, folder detail, breadcrumb/back, empty folder, and streak folder states;
- verify drag disabled/enabled paths and long-title overflow behavior.

- [x] **Step 2: Verify invalid and boundary inputs**

Assert with tests after arranging a provider with one root folder, one child folder, and one task in the root folder:

```dart
final provider = TaskProvider();
await provider.ready;
provider.addFolder('Root');
final rootId = provider.folders.lastWhere((folder) => folder.name == 'Root').id;
provider.addFolder('Child', parentFolderId: rootId);
final childId = provider.folders.lastWhere((folder) => folder.name == 'Child').id;
provider.addTask('Task', folderId: rootId);
final tasksBeforeInvalidReorder = List.of(provider.tasks);

expect(() => provider.addTask('x' * 251), throwsA(isA<Exception>()));
expect(() => provider.addFolder('x' * 251), throwsA(isA<Exception>()));
provider.reorderRootFolders(-1, 0);
provider.reorderRootFolders(0, 999);
provider.reorderFolderTasks(rootId, -1, 0);
provider.reorderFolderTasks(rootId, 0, 999);
expect(provider.tasks, equals(tasksBeforeInvalidReorder));
provider.moveFolderToFolder(rootId, rootId);
provider.moveFolderToFolder(rootId, childId);
expect(provider.folders.firstWhere((folder) => folder.id == rootId).parentFolderId,
    isNull);
```

Also cover empty/whitespace title behavior, reserved streak-folder insertion, malformed persisted records, duplicate IDs, folder cycles, and task references to deleted folders.

- [x] **Step 3: Verify persistence and reload outcomes**

After each mutation call `await provider.flushPersistence()`, construct a new provider with the same mock preferences, await `ready`, and compare visible data, soft-delete flags, order, timer fields, info blocks, and folder hierarchy.

- [x] **Step 4: Fix only reproducible defects and add regressions**

For each failure, add the smallest failing test first, implement the smallest fix, and rerun the affected file. Do not redesign navigation or models for a test that already passes.

- [ ] **Step 5: Review, validate, and commit**

Run the exact task-family gate:

```bash
dart format --output=none --set-exit-if-changed lib/features/tasks/providers/task_provider.dart lib/features/tasks/models/task_model.dart lib/features/tasks/screens/home_screen.dart lib/features/tasks/screens/folder_detail_screen.dart lib/features/tasks/widgets/task_card.dart lib/features/tasks/widgets/folder_card.dart test/task_provider_test.dart test/task_model_test.dart test/input_utils_test.dart test/home_screen_test.dart test/folder_detail_screen_test.dart test/task_folder_popup_menu_test.dart
dart analyze lib/features/tasks/providers/task_provider.dart lib/features/tasks/models/task_model.dart lib/features/tasks/screens/home_screen.dart lib/features/tasks/screens/folder_detail_screen.dart lib/features/tasks/widgets/task_card.dart lib/features/tasks/widgets/folder_card.dart test/task_provider_test.dart test/task_model_test.dart test/input_utils_test.dart test/home_screen_test.dart test/folder_detail_screen_test.dart test/task_folder_popup_menu_test.dart
flutter test --no-pub test/task_provider_test.dart test/task_model_test.dart test/input_utils_test.dart -r compact
git diff --check
git add docs/superpowers/reports/2026-07-31-full-functional-audit.md lib/features/tasks/providers/task_provider.dart lib/features/tasks/models/task_model.dart lib/features/tasks/screens/home_screen.dart lib/features/tasks/screens/folder_detail_screen.dart lib/features/tasks/widgets/task_card.dart lib/features/tasks/widgets/folder_card.dart test/task_provider_test.dart test/task_model_test.dart test/input_utils_test.dart test/home_screen_test.dart test/folder_detail_screen_test.dart test/task_folder_popup_menu_test.dart
git commit -m "test: audit task and folder workflows"
```

If no production defect exists, the report and focused regression tests still form the task deliverable; do not create an empty commit.

- [x] **Step 5: Review, validate, and commit**

---

### Task 3: Audit task editor, information blocks, attachments, detail view, time period, and manual timer

**Files:**
- Inspect/modify only if reproduced: `lib/features/tasks/widgets/task_editor_sheet.dart`, `lib/features/tasks/widgets/task_detail_sheet.dart`, `lib/features/tasks/widgets/task_time_sheet.dart`, `lib/features/tasks/providers/task_provider.dart`, `lib/core/task_attachment_service.dart`
- Test: `test/task_editor_sheet_test.dart`, `test/task_folder_popup_menu_test.dart`, `test/task_provider_test.dart`, `test/task_model_test.dart`, `test/task_attachment_service_test.dart`
- Report: `docs/superpowers/reports/2026-07-31-full-functional-audit.md`

**Interfaces:**
- Consumes: `showTaskEditorSheet`, `showTaskDetailSheet`, `showTaskTimeSheet`, `TaskInfoBlock`, `TaskAttachment`, and timer provider methods.
- Produces: evidence that drafts, validation, typed blocks, attachments, time windows, and timer actions behave safely.

- [ ] **Step 1: Verify editor happy paths and draft cancellation**

Check new and existing task flows:

- title only save;
- empty title, whitespace title, 250-character title, 251-character title;
- add/remove multiple quantity and description blocks;
- quantity current `0`, target `1`, decimal values, unit/label, current equal target;
- description text with multiline content and maximum length;
- valid `http`/`https` links;
- cancel editor after unsaved changes and confirm no mutation;
- edit existing task and confirm blocks replace atomically on save;
- detail sheet displays information only and has no edit/time/delete controls.

- [ ] **Step 2: Verify invalid block and attachment paths**

Cover negative/invalid quantities, `NaN`/infinity text, current greater than target, empty required fields, unsafe schemes (`javascript:`, `file:`, `data:`), malformed attachment metadata, unsupported image signatures, oversized files, 20-attachment boundary, 21st attachment, picker cancellation, picker exception, missing local attachment, and failed external link launch.

Expected behavior: save is rejected without partial mutation; invalid link shows localized error; unavailable picker/file shows safe feedback; missing attachment does not crash detail UI.

- [ ] **Step 3: Verify time and timer semantics**

Test:

- no time, start only, end only;
- 22:01–22:02 → planned duration `0:01`, actual manual timer `0:00` before starting;
- equal start/end → non-schedulable duration;
- daytime and overnight periods;
- clear start/end and edit one side;
- start timer, second start ignored, stop, repeated stop ignored, reset, elapsed persistence;
- complete a running task and confirm timer stops and elapsed time is retained;
- notification action start for an existing, deleted, completed, and missing task ID.

- [ ] **Step 4: Fix reproducible failures and add regression tests**

Preserve the separation between planned period and actual elapsed timer. Any fix must assert both values and avoid auto-starting the manual timer unless explicitly requested by product behavior.

- [ ] **Step 5: Review, validate, and commit**

Run the exact editor-family gate:

```bash
dart format --output=none --set-exit-if-changed lib/features/tasks/widgets/task_editor_sheet.dart lib/features/tasks/widgets/task_detail_sheet.dart lib/features/tasks/widgets/task_time_sheet.dart lib/features/tasks/providers/task_provider.dart lib/core/task_attachment_service.dart test/task_editor_sheet_test.dart test/task_folder_popup_menu_test.dart test/task_provider_test.dart test/task_model_test.dart test/task_attachment_service_test.dart
dart analyze lib/features/tasks/widgets/task_editor_sheet.dart lib/features/tasks/widgets/task_detail_sheet.dart lib/features/tasks/widgets/task_time_sheet.dart lib/features/tasks/providers/task_provider.dart lib/core/task_attachment_service.dart test/task_editor_sheet_test.dart test/task_folder_popup_menu_test.dart test/task_provider_test.dart test/task_model_test.dart test/task_attachment_service_test.dart
flutter test --no-pub test/task_model_test.dart test/task_provider_test.dart test/task_attachment_service_test.dart -r compact
git diff --check
git add docs/superpowers/reports/2026-07-31-full-functional-audit.md lib/features/tasks/widgets/task_editor_sheet.dart lib/features/tasks/widgets/task_detail_sheet.dart lib/features/tasks/widgets/task_time_sheet.dart lib/features/tasks/providers/task_provider.dart lib/core/task_attachment_service.dart test/task_editor_sheet_test.dart test/task_folder_popup_menu_test.dart test/task_provider_test.dart test/task_model_test.dart test/task_attachment_service_test.dart
git commit -m "test: audit task editor and timer workflows"
```

Record widget-test hangs separately if they reproduce; never report a timeout as a pass.

---

### Task 4: Audit settings, theme, language, scale, animation, avatar, notifications, and lifecycle

**Files:**
- Inspect/modify only if reproduced: `lib/features/settings/providers/settings_provider.dart`, `lib/features/settings/screens/settings_screen.dart`, `lib/features/settings/widgets/setting_row.dart`, `lib/features/settings/widgets/avatar_section.dart`, `lib/features/settings/widgets/language_bottom_sheet.dart`, `lib/features/settings/widgets/animation_speed_bottom_sheet.dart`, `lib/features/settings/widgets/app_scale_bottom_sheet.dart`, `lib/features/settings/widgets/theme_mode_bottom_sheet.dart`, `lib/features/settings/widgets/widget_mode_bottom_sheet.dart`, `lib/features/settings/widgets/sync_bottom_sheet.dart`, `lib/features/settings/widgets/about_bottom_sheet.dart`, `lib/features/settings/widgets/data_management_bottom_sheet.dart`, `lib/core/notification_service.dart`, `lib/main.dart`, `lib/core/theme_switcher.dart`, `lib/core/image_utils.dart`, `lib/core/version_service.dart`, `lib/core/bottom_sheet.dart`, `lib/core/input_utils.dart`, `lib/core/clipboard_utils.dart`
- Test: `test/settings_provider_test.dart`, `test/settings_screen_test.dart`, `test/notification_service_test.dart`, `test/image_utils_test.dart`, `test/home_screen_test.dart`, `test/input_utils_test.dart`
- Report: `docs/superpowers/reports/2026-07-31-full-functional-audit.md`

**Interfaces:**
- Consumes: settings persistence, startup providers, notification permission APIs, theme transition, and avatar storage.
- Produces: evidence for settings state changes, denied/cancelled operations, persistence, and lifecycle recovery.

- [ ] **Step 1: Verify settings and shared UI happy paths**

Check light/dark/system theme and animated transition, Russian/English language, built-in/custom animation speed, built-in/custom app scale, widget enabled/disabled and both widget modes, notification enabled/disabled, sync enabled/disabled, device name, sync secret set/clear/rotate, avatar add/replace/remove, about/data-management sheets, app version prompt dismiss/open/update actions, generic task/folder input sheet, clipboard paste, icon picker selection, and app restart persistence.

- [ ] **Step 2: Verify invalid and interrupted settings paths**

Cover unsupported language code, out-of-range/NaN custom values, duplicate/LRU custom values, clearing a device name, empty secret, denied notification permission, exact-alarm refusal, picker cancellation, invalid/oversized avatar, missing previous avatar, failed avatar persistence rollback, and changing settings while a sheet is closing.

- [ ] **Step 3: Verify lifecycle and accessibility outcomes**

Run app background/resume/paused transitions; confirm task persistence flush, pending notification action consumption, widget refresh throttling, no stale context use, no duplicate sync startup, and no data loss. Pump representative screens with large text (`TextScaler.linear(1.5)`) and verify no overflow where the test harness permits.

- [ ] **Step 4: Fix regressions only when evidence shows a defect**

Add focused tests for every fix. Do not treat a platform permission denial as a test failure when the app correctly disables the feature and explains the limitation.

- [ ] **Step 5: Review, validate, and commit**

Run the exact settings-family gate:

```bash
dart format --output=none --set-exit-if-changed lib/features/settings/providers/settings_provider.dart lib/features/settings/screens/settings_screen.dart lib/features/settings/widgets/setting_row.dart lib/features/settings/widgets/avatar_section.dart lib/features/settings/widgets/language_bottom_sheet.dart lib/features/settings/widgets/animation_speed_bottom_sheet.dart lib/features/settings/widgets/app_scale_bottom_sheet.dart lib/features/settings/widgets/theme_mode_bottom_sheet.dart lib/features/settings/widgets/widget_mode_bottom_sheet.dart lib/features/settings/widgets/sync_bottom_sheet.dart lib/features/settings/widgets/about_bottom_sheet.dart lib/features/settings/widgets/data_management_bottom_sheet.dart lib/core/notification_service.dart lib/main.dart lib/core/theme_switcher.dart lib/core/image_utils.dart lib/core/version_service.dart lib/core/bottom_sheet.dart lib/core/input_utils.dart lib/core/clipboard_utils.dart test/settings_provider_test.dart test/settings_screen_test.dart test/notification_service_test.dart test/image_utils_test.dart test/home_screen_test.dart test/input_utils_test.dart
dart analyze lib/features/settings/providers/settings_provider.dart lib/features/settings/screens/settings_screen.dart lib/features/settings/widgets/setting_row.dart lib/features/settings/widgets/avatar_section.dart lib/features/settings/widgets/language_bottom_sheet.dart lib/features/settings/widgets/animation_speed_bottom_sheet.dart lib/features/settings/widgets/app_scale_bottom_sheet.dart lib/features/settings/widgets/theme_mode_bottom_sheet.dart lib/features/settings/widgets/widget_mode_bottom_sheet.dart lib/features/settings/widgets/sync_bottom_sheet.dart lib/features/settings/widgets/about_bottom_sheet.dart lib/features/settings/widgets/data_management_bottom_sheet.dart lib/core/notification_service.dart lib/main.dart lib/core/theme_switcher.dart lib/core/image_utils.dart lib/core/version_service.dart lib/core/bottom_sheet.dart lib/core/input_utils.dart lib/core/clipboard_utils.dart test/settings_provider_test.dart test/settings_screen_test.dart test/notification_service_test.dart test/image_utils_test.dart test/home_screen_test.dart test/input_utils_test.dart
flutter test --no-pub test/settings_provider_test.dart test/notification_service_test.dart test/image_utils_test.dart test/input_utils_test.dart -r compact
git diff --check
git add docs/superpowers/reports/2026-07-31-full-functional-audit.md lib/features/settings/providers/settings_provider.dart lib/features/settings/screens/settings_screen.dart lib/features/settings/widgets/setting_row.dart lib/features/settings/widgets/avatar_section.dart lib/features/settings/widgets/language_bottom_sheet.dart lib/features/settings/widgets/animation_speed_bottom_sheet.dart lib/features/settings/widgets/app_scale_bottom_sheet.dart lib/features/settings/widgets/theme_mode_bottom_sheet.dart lib/features/settings/widgets/widget_mode_bottom_sheet.dart lib/features/settings/widgets/sync_bottom_sheet.dart lib/features/settings/widgets/about_bottom_sheet.dart lib/features/settings/widgets/data_management_bottom_sheet.dart lib/core/notification_service.dart lib/main.dart lib/core/theme_switcher.dart lib/core/image_utils.dart lib/core/version_service.dart lib/core/bottom_sheet.dart lib/core/input_utils.dart lib/core/clipboard_utils.dart test/settings_provider_test.dart test/settings_screen_test.dart test/notification_service_test.dart test/image_utils_test.dart test/home_screen_test.dart test/input_utils_test.dart
git commit -m "test: audit settings and lifecycle workflows"
```

---

### Task 5: Audit data management, export/import, sync, logging, calendar, and external integrations

**Files:**
- Inspect/modify only if reproduced: `lib/core/export_import_service.dart`, `lib/core/sync_service.dart`, `lib/core/logger_service.dart`, `lib/core/calendar_service.dart`, `lib/core/task_attachment_service.dart`, settings integration widgets
- Test: `test/export_import_service_test.dart`, `test/sync_service_test.dart`, `test/logger_service_test.dart`, `test/task_attachment_service_test.dart`, `test/settings_screen_test.dart`
- Report: `docs/superpowers/reports/2026-07-31-full-functional-audit.md`

**Interfaces:**
- Consumes: export/import preview/merge, HMAC envelope, mDNS/TCP lifecycle, logger redaction, calendar wrapper, attachment open/store boundaries.
- Produces: evidence for successful, cancelled, malformed, unauthorized, offline, unavailable, and partial-failure outcomes.

- [ ] **Step 1: Verify export and import flows**

Check export to file, export/share result, empty data, tasks/folders/info blocks/attachment metadata round-trip, preview counts/version/date, confirm import, cancel import, duplicate newer/older records, soft-delete propagation, malformed JSON, invalid UTF-8, wrong extension, missing keys, non-list/object lists, actual size over 10 MB, and import failure without partial corruption.

- [ ] **Step 2: Verify sync flows**

Check no-secret plain payload, correct HMAC payload, wrong secret, missing secret, tampered payload, oversized/zero/negative/incomplete frames, peer connect failure, peer disconnect, concurrent start, stop during start, device self-filtering, empty/changed device name, and persistence after merge. Use loopback only in automated tests; use a second real device only if available.

- [ ] **Step 3: Verify logging and external integrations**

Confirm sync secrets, tokens, paths, raw payloads, and stack traces are redacted; logger buffer bounds hold; Telegram unavailable/disabled returns a safe result. For calendar, test permission granted/denied, no writable calendars, create/update/delete, overnight period, missing event, and native API failure. For links/files/images, test valid open and unavailable external handler/file.

- [ ] **Step 4: Fix reproducible integration/data defects**

Use dependency injection or pure helpers for deterministic tests. Do not fake successful native permission or share/calendar delivery; mark unavailable native outcomes **BLOCKED** with the exact platform limitation.

- [ ] **Step 5: Review, validate, and commit**

Run the exact data/integration gate:

```bash
dart format --output=none --set-exit-if-changed lib/core/export_import_service.dart lib/core/sync_service.dart lib/core/logger_service.dart lib/core/calendar_service.dart lib/core/task_attachment_service.dart lib/features/settings/widgets/data_management_bottom_sheet.dart lib/features/settings/widgets/import_preview_bottom_sheet.dart test/export_import_service_test.dart test/sync_service_test.dart test/logger_service_test.dart test/task_attachment_service_test.dart
dart analyze lib/core/export_import_service.dart lib/core/sync_service.dart lib/core/logger_service.dart lib/core/calendar_service.dart lib/core/task_attachment_service.dart lib/features/settings/widgets/data_management_bottom_sheet.dart lib/features/settings/widgets/import_preview_bottom_sheet.dart test/export_import_service_test.dart test/sync_service_test.dart test/logger_service_test.dart test/task_attachment_service_test.dart
flutter test --no-pub test/export_import_service_test.dart test/sync_service_test.dart test/logger_service_test.dart test/task_attachment_service_test.dart -r compact
git diff --check
git add docs/superpowers/reports/2026-07-31-full-functional-audit.md lib/core/export_import_service.dart lib/core/sync_service.dart lib/core/logger_service.dart lib/core/calendar_service.dart lib/core/task_attachment_service.dart lib/features/settings/widgets/data_management_bottom_sheet.dart lib/features/settings/widgets/import_preview_bottom_sheet.dart test/export_import_service_test.dart test/sync_service_test.dart test/logger_service_test.dart test/task_attachment_service_test.dart
git commit -m "test: audit data and integration workflows"
```

---

### Task 6: Execute Android arm64 real-device functional matrix

**Files:**
- Modify only if a device reproducer identifies a defect.
- Test/docs: `docs/superpowers/reports/2026-07-31-full-functional-audit.md`, focused regression tests, Android manifests/resources only for confirmed native defects.

**Interfaces:**
- Consumes: the signed arm64 APK, ADB, Android permissions, native widget/notification/calendar/file picker behavior.
- Produces: device evidence or explicit blocked outcomes for every Android-only function.

- [ ] **Step 1: Install and launch the APK**

Run:

```bash
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
adb shell am force-stop com.example.asa
adb shell monkey -p com.example.asa 1
adb logcat -c
```

Record install/launch success, startup time, crashes, and relevant filtered logcat output without secrets.

- [ ] **Step 2: Execute the user journey matrix**

On a clean test dataset verify: create/edit/delete/restore-visible behavior, folders/nesting/drag, search/filter, information blocks, image/file/link attachments, time period and manual timer, detail read-only restrictions, theme/language/scale, avatar, export/import, notification permission and a reminder scheduled 2–3 minutes ahead, notification `start_timer` action, app background/resume, widget enabled/disabled and both widget modes, calendar permission/event create/update/delete, sync toggle/name/secret, and app restart persistence.

For each journey run the corresponding negative path: cancel dialog/picker, deny permission, offline/no-handler, invalid input, missing file, duplicate action, app killed during pending persistence, and repeated taps.

- [ ] **Step 3: Verify notification timing honestly**

Use a future start time at least two minutes ahead. Capture whether the notification arrives, delivery delay, Android exact-alarm setting state, channel state, and whether the action starts the correct task timer. A notification that is delayed because exact alarms are denied is **PARTIAL/BLOCKED**, not a silent pass.

- [ ] **Step 4: Fix device-only defects with a regression test where possible**

After each fix rebuild/debug-install only as needed, rerun the failing journey, run analyzer/native compile, and preserve the device evidence.

- [ ] **Step 5: Review and commit**

```bash
git diff --check
# run the focused tests for any changed Dart files
(cd android && ./gradlew :app:processDebugResources :app:compileDebugKotlin --no-daemon)
git add docs/superpowers/reports/2026-07-31-full-functional-audit.md
# If a device defect was fixed, also stage only its exact source/test files here.
git commit -m "test: verify Android functional matrix"
```

If no device is connected, commit the completed blocked matrix/report only after documenting `adb devices -l` and the unavailable scenarios.

---

### Task 7: Final independent review, release gates, report completion, and final APK

**Files:**
- Modify: `docs/superpowers/reports/2026-07-31-full-functional-audit.md`
- Modify: this plan to mark completed/blocked steps and list commits
- No source changes unless final review finds a reproducible defect.

**Interfaces:**
- Consumes: all task commits, test outputs, device logs, and the initial APK evidence.
- Produces: final evidence-based report and the final signed arm64-v8a release APK.

- [ ] **Step 1: Run independent code review**

Review the complete audit commit range for data loss, unsafe error handling, stale tests, unverified claims, accidental secrets, and scope drift. Resolve blockers before continuing.

- [ ] **Step 2: Run final static and automated gates**

Run:

```bash
baseline=$(sed -n 's/^\*\*Audit baseline commit:\*\* `\([^`]*\)`.*/\1/p' docs/superpowers/reports/2026-07-31-full-functional-audit.md)
git diff --check "$baseline" HEAD
dart format --output=none --set-exit-if-changed .
dart analyze
flutter test --no-pub test/input_utils_test.dart test/task_model_test.dart test/task_provider_test.dart test/settings_provider_test.dart test/export_import_service_test.dart test/sync_service_test.dart test/notification_service_test.dart test/image_utils_test.dart test/task_attachment_service_test.dart test/logger_service_test.dart test/home_widget_service_test.dart -r compact
perl -e 'alarm 300; exec @ARGV' -- flutter test --no-pub test/home_screen_test.dart test/settings_screen_test.dart test/task_editor_sheet_test.dart test/task_folder_popup_menu_test.dart test/folder_detail_screen_test.dart -r compact
(cd android && ./gradlew :app:processDebugResources :app:compileDebugKotlin --no-daemon)
```

Do not report a timeout as a pass; include exact blocked files and durations.

- [ ] **Step 3: Update plan/report evidence**

For every task and matrix row, set `[x]` only when its stated evidence exists. Add final sections: passed checks/counts, failed-and-fixed defects with commit hashes, blocked device/harness checks, unresolved risks, and reproducible manual steps.

- [ ] **Step 4: Build final arm64-v8a release APK**

Run:

```bash
flutter build apk --target-platform android-arm64 --split-per-abi --release
apk='build/app/outputs/flutter-apk/app-arm64-v8a-release.apk'
/Users/sabir/Library/Android/sdk/build-tools/37.0.0/apksigner verify --verbose "$apk"
ls -lh "$apk"
shasum -a 256 "$apk"
unzip -l "$apk" | grep -E 'lib/[^/]+/.*\.so$'
```

Expected: one signed APK containing only `lib/arm64-v8a` native libraries; record exact size and SHA-256. Do not commit the APK.

- [ ] **Step 5: Commit the final evidence**

```bash
git add docs/superpowers/plans/2026-07-31-full-functional-audit.md docs/superpowers/reports/2026-07-31-full-functional-audit.md
git commit -m "docs: record full functional audit results"
```

- [ ] **Step 6: Verify clean repository state**

Run:

```bash
git status --short --branch
git log --oneline -n 10
```

Expected: no uncommitted tracked changes; ignored APK/signing files remain untracked/ignored and no secrets are staged.
