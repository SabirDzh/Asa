# Full Standards Review and Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or **superpowers:executing-plans** to implement this plan task-by-task. Steps use checkbox (`- [x]`/`- [ ]`) syntax for tracking.

**Goal:** Audit and harden ASA against confirmed correctness, security, performance, accessibility, platform, testing, and release-quality risks, while preserving current product behavior and documenting anything that cannot be verified locally.

**Architecture:** Keep the existing Flutter feature-first structure and Provider + ChangeNotifier design. Remediation is layered by risk: first make static analysis and data/input boundaries reliable, then harden LAN sync and diagnostics, then verify platform integrations and improve measured UI/performance issues. Avoid broad rewrites; every change must have a focused regression test or an explicit platform-build verification.

**Tech Stack:** Flutter 3.44.8, Dart 3.12.2, Dart SDK ^3.7.2, Provider, SharedPreferences, file_picker, path_provider, crypto/HMAC, bonsoir/TCP sockets, flutter_local_notifications, home_widget, image_picker, flutter_image_compress, device_calendar, Flutter test, Gradle/Kotlin, Xcode project files.

## Completion status and evidence — 2026-07-31

The remediation implementation is complete and independently reviewed. The repository is not claimed as fully green on every platform gate because environment/tooling limitations remain documented below. In the checklists, `[x]` means the implementation or evidence is complete; an unchecked step with a `Blocked` note is intentionally unresolved.

| Area | Status | Evidence |
|---|---|---|
| Static analysis | **Passed** | `dart analyze` → `No issues found!`; `422d567` |
| Repository formatting | **Passed** | `dart format --output=none --set-exit-if-changed .`; formatting-only `3427d11` |
| Import/avatar boundaries | **Passed** | `6e76e3d`; focused parser/image tests included in the 144-test non-widget suite |
| Persistence/sync/diagnostics | **Passed** | `3e337b4`, `08c86f2`, `f959f22`, `2dd1116`; 144 focused non-widget tests passed |
| Notification/widgets | **Passed** | `e9659b5`; notification/widget contracts and Android gate passed |
| Android native gate | **Passed** | `:app:processDebugResources :app:compileDebugKotlin --no-daemon` → `BUILD SUCCESSFUL` |
| Android arm64 release | **Passed** | `flutter build apk --target-platform android-arm64 --split-per-abi --release`; `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (~21.6 MB) |
| Web build | **Partial** | `flutter build web --no-tree-shake-icons` passed; ordinary build remains blocked by Flutter `IconTreeShakerException` |
| Non-widget tests | **Passed** | 144 tests passed across model, parser, provider, sync, export/import, notification, image, settings, logger, and widget-service suites |
| Widget/full test suite | **Blocked** | `home_screen_test` first test passes; `folder_detail_screen_test` and `task_folder_popup_menu_test` hang after test start, so full `flutter test` is not claimed |
| Physical-device/platform matrix | **Not verified** | Android/iOS attachment, notification, widget, calendar, TalkBack/VoiceOver, 1.5x text scale, LAN discovery, and desktop/iOS builds require device/toolchain verification |

### Standards remediation commit range

`422d567`, `6e76e3d`, `3e337b4`, `2dd1116`, `e9659b5`, `2250954`, `614aa05`, `94087c5`, `08c86f2`, `1eff7fe`, `e653dab`, `c7b7333`, `f959f22`, and the formatting gate `3427d11`.

The later task-information commits are separate product work: `00676a3`, `a74254c`, `0e568ad`, `7ddb155`, `71d33e7`.

### Final review limitations

* Ordinary web icon tree-shaking is an upstream/tooling failure involving the icons font; the no-tree-shaking build is a diagnostic workaround, not a replacement for the ordinary release gate.
* Widget tests hang without producing a Flutter assertion or stack trace. They are recorded as unresolved test-harness/platform behavior, not silently marked passed.
* `SharedPreferences` remains unencrypted; sync secrets must be migrated to platform secure storage before being treated as high-value credentials.
* No physical-device behavior is claimed as verified.

## Global Constraints

- Preserve the current branch and existing product behavior; do not change public behavior unless the review proves it unsafe or incorrect.
- `dart analyze` must finish with zero issues, including infos and warnings.
- `dart format --output=none --set-exit-if-changed .` must pass before the final gate.
- `flutter test` must pass with all existing and newly added tests.
- Android release/debug compilation must pass; do not require signing credentials for local verification.
- Do not commit secrets, keystores, tokens, personal data, or generated build artifacts.
- User-controlled text must continue to pass the existing sanitization/length rules before persistence.
- File imports must remain bounded and validated before parsing or mutating provider state.
- LAN sync must authenticate payloads when a shared secret is configured and must reject malformed/oversized frames.
- Platform limitations (web raw sockets, desktop notification/widget parity, unavailable physical devices) must be recorded explicitly rather than hidden.
- Make one focused commit per completed task, after its task-specific verification passes.

## Review Scope and File Map

- `analysis_options.yaml`, `pubspec.yaml`: static-analysis policy and dependency/release metadata.
- `lib/core/input_utils.dart`, `lib/core/export_import_service.dart`, `lib/core/image_utils.dart`: user input, file boundaries, parsing, and image handling.
- `lib/core/sync_service.dart`, `lib/core/logger_service.dart`: network framing/authentication and diagnostics/data egress.
- `lib/core/notification_service.dart`, `lib/core/home_widget_service.dart`, `lib/main.dart`: platform services and lifecycle guards.
- `lib/features/tasks/models/task_model.dart`, `lib/features/tasks/providers/task_provider.dart`, `lib/features/settings/providers/settings_provider.dart`: persistence, mutation, async initialization, and state consistency.
- `lib/features/tasks/screens/*.dart`, `lib/features/tasks/widgets/*.dart`, `lib/features/settings/**/*.dart`, `lib/core/theme_switcher.dart`: rebuild scope, layout/accessibility, input lifecycle, and animation cost.
- `android/`, `ios/`, `macos/`, `linux/`, `windows/`, `web/`: platform permissions, entitlements, widget/notification declarations, and build compatibility.
- `test/*.dart`: regression, provider, parser, platform-contract, and widget coverage.
- `docs/DEVELOPER.md`, this plan: operational and review documentation.

---

### Task 1: Establish the review baseline and enforce zero analyzer issues

**Files:**
- Modify: `analysis_options.yaml`
- Modify: `test/input_utils_test.dart`
- Test: all Dart sources through analyzer and formatter

**Interfaces:**
- Consumes: existing `flutter_lints/flutter.yaml` configuration.
- Produces: a repository-wide static-analysis gate that reports no issues and does not silently downgrade diagnostics.

- [x] **Step 1: Reproduce the current analyzer finding**

Run:

```bash
dart analyze
```

Expected before the fix: one `unnecessary_import` issue in `test/input_utils_test.dart`.

- [x] **Step 2: Remove only the unused test import**

Delete the import that analyzer identifies as unused; keep all imports required by the test and do not broaden the test change.

- [x] **Step 3: Keep the baseline analyzer gate bounded**

Update `analysis_options.yaml` so it retains the Flutter defaults and makes the confirmed unused-import diagnostic fail the gate without starting an unbounded migration:

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  errors:
    unnecessary_import: error

linter:
  rules: []
```

Do not add global `strict-casts`, `strict-inference`, `strict-raw-types`, `unawaited_futures`, or `use_build_context_synchronously` enforcement in this baseline task. The baseline run identified existing violations for those rules; later tasks will fix concrete violations and can enable each rule only after its scope is clean. Never silence those diagnostics with global ignores.

- [x] **Step 4: Run the quality gate**

Run:

```bash
dart format --output=none --set-exit-if-changed .
dart analyze
flutter test test/input_utils_test.dart
```

Expected: the focused formatter check for the changed files exits 0, analyzer reports `No issues found!`, and the focused test passes. A repository-wide formatter migration is tracked separately and must not be hidden in this task’s commit.

- [x] **Step 5: Commit**

```bash
git add analysis_options.yaml test/input_utils_test.dart
git commit -m "chore: enforce project analyzer quality gate"
```

---

### Task 2: Harden input, import, and image boundaries

**Files:**
- Modify: `lib/core/export_import_service.dart`
- Modify: `lib/core/image_utils.dart`
- Modify: `lib/features/settings/widgets/avatar_section.dart`
- Modify: `lib/features/settings/providers/settings_provider.dart`
- Modify: `test/export_import_service_test.dart`
- Modify: `test/image_utils_test.dart`
- Test: focused import/image tests

**Interfaces:**
- Consumes: `ExportImportService.previewImport`, `importFromBytes`, `FilePicker.platform.pickFiles`, `detectImageFormat`, and existing avatar persistence.
- Produces: bounded parsing that validates actual byte length, rejects malformed JSON shapes before casts, and stores only verified/size-bounded avatar files.

- [x] **Step 1: Add failing parser tests for byte-size and map-shape validation**

Add tests that assert:

```dart
test('rejects bytes larger than the import limit even when fileSize is smaller', () {
  final bytes = List<int>.filled(10 * 1024 * 1024 + 1, 32);
  final preview = ExportImportService.previewImport(
    fileName: 'backup.json',
    fileSize: 1,
    bytes: bytes,
  );
  expect(preview.isValid, isFalse);
  expect(preview.errorKey, 'error_file_too_large');
});

test('rejects task entries that are not JSON objects', () {
  final preview = ExportImportService.previewImport(
    fileName: 'backup.json',
    fileSize: 32,
    bytes: _utf8({
      'version': '1.1.0',
      'exportedAt': 1,
      'tasks': ['not-a-map'],
      'folders': [],
    }),
  );
  expect(preview.isValid, isFalse);
  expect(preview.errorKey, 'error_invalid_lists');
});
```

Use the test file’s existing helpers and keep the large input bounded to one case.

- [x] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
flutter test test/export_import_service_test.dart
```

Expected: the new tests fail because validation currently trusts the caller-provided `fileSize` and `AsaDataSnapshot.fromJson` uses unchecked list casts.

- [x] **Step 3: Implement safe byte and JSON-shape validation**

In `previewImport`, calculate `actualSize = bytes.length` and reject when `actualSize > _kMaxImportFileSize`; use `actualSize` in the returned preview where the byte buffer is authoritative. Before constructing `AsaDataSnapshot`, verify every task/folder entry is a `Map<String, dynamic>` (convert `Map` entries with `Map<String, dynamic>.from` only after checking the key/value shape). Return `error_invalid_lists` instead of allowing a `TypeError`.

In `pickImportFile`, reject a selected `PlatformFile` when `file.size > _kMaxImportFileSize` before retaining/processing bytes. Continue using `withData: true` for web compatibility and do not use an absolute path as the only source of bytes.

- [x] **Step 4: Add avatar size and lifecycle regression tests**

Also preserve the provider rollback contract: if `SettingsProvider.setAvatarPath` cannot persist the new path, it must restore the previous in-memory path before rethrowing.

Add `readValidatedImageBytes(String path, {int maxBytes = kMaxAvatarFileSize})` to `lib/core/image_utils.dart`. It must return `null` when the file is missing, larger than `maxBytes`, or unreadable, and otherwise return the bytes. Add tests that create a temporary valid image-signature file, assert accepted bytes are returned, and assert an oversized file returns `null`. Keep the existing `detectImageFormat` signature checks.

- [x] **Step 5: Implement bounded avatar copying**

In `avatar_section.dart`, use `readValidatedImageBytes(pickedFile.path)` after format detection and before writing the destination. If it returns `null`, show the localized invalid/oversized-avatar message and return. For GIF, write the validated bytes directly; for other formats, retain `FlutterImageCompress.compressAndGetFile` but first reject the source through the helper. Preserve deletion of the previous avatar only after the new file is successfully written and `setAvatarPath` has completed.

- [x] **Step 6: Run focused validation**

Run:

```bash
dart format lib/core/export_import_service.dart lib/core/image_utils.dart lib/features/settings/widgets/avatar_section.dart lib/features/settings/providers/settings_provider.dart test/export_import_service_test.dart test/image_utils_test.dart
 dart analyze lib/core/export_import_service.dart lib/core/image_utils.dart lib/features/settings/widgets/avatar_section.dart lib/features/settings/providers/settings_provider.dart test/export_import_service_test.dart test/image_utils_test.dart
flutter test test/export_import_service_test.dart test/image_utils_test.dart
```

Expected: analyzer clean and all focused tests pass.

- [x] **Step 7: Commit**

```bash
git add lib/core/export_import_service.dart lib/core/image_utils.dart lib/features/settings/widgets/avatar_section.dart lib/features/settings/providers/settings_provider.dart test/export_import_service_test.dart test/image_utils_test.dart
git commit -m "fix: harden import and avatar file boundaries"
```

---

### Task 3: Make persistence and sync state changes failure-visible and race-safe

**Files:**
- Modify: `lib/features/tasks/providers/task_provider.dart`
- Modify: `lib/core/sync_service.dart`
- Modify: `lib/core/logger_service.dart` only if redaction is required by tests
- Modify: `test/task_provider_test.dart`
- Modify: `test/sync_service_test.dart`
- Test: provider and sync tests

**Interfaces:**
- Consumes: `TaskProvider._saveToPrefs`, `TaskProvider.persist`, `SyncService.start/stop/sendToPeer`, `ExportImportService.buildSyncPayload/importFromBytes`.
- Produces: serialized persistence writes, deterministic cleanup on sync failure/stop, bounded frame handling, and logs that do not include shared secrets or raw task payloads.

- [x] **Step 1: Add regression tests for malformed frames and concurrent persistence**

Add a sync-service test that starts the existing loopback server, writes a four-byte big-endian length of `10 * 1024 * 1024 + 1`, closes the socket, and asserts no task is imported. Add a provider persistence test that performs two mutations without awaiting the first persistence call, awaits `provider.persist()`, then reads `saved_tasks` and asserts the JSON contains the second mutation and not an older-only snapshot. Use only `127.0.0.1`; do not open external network connections.

- [x] **Step 2: Inspect current failures/data flow before editing**

Run:

```bash
flutter test test/task_provider_test.dart test/sync_service_test.dart
```

Record whether the new tests fail for frame parsing, persistence ordering, or both.

- [x] **Step 3: Serialize provider persistence**

Add a private `Future<void> _persistQueue = Future<void>.value();` and enqueue JSON writes so each write captures a coherent snapshot and executes after the prior write. Preserve synchronous in-memory mutation and listener notification. Log a generic persistence failure with operation context, but never log full task JSON or secrets.

- [x] **Step 4: Harden sync connection lifecycle**

In `sync_service.dart`:

- keep the 10 MB maximum and reject negative/zero lengths before collecting more bytes;
- stop processing a socket after one complete frame or a malformed frame;
- destroy/close sockets on all failure paths;
- ensure `stop()` cancels discovery, broadcast, server, and peer streams even when one close operation throws;
- prevent a second `start()` call from creating parallel servers;
- keep HMAC verification in `ExportImportService` as the source of truth.

Do not expose `_secret`, payload contents, or raw socket data in logs.

- [x] **Step 5: Run focused validation**

Run:

```bash
dart format lib/features/tasks/providers/task_provider.dart lib/core/sync_service.dart lib/core/logger_service.dart test/task_provider_test.dart test/sync_service_test.dart
dart analyze lib/features/tasks/providers/task_provider.dart lib/core/sync_service.dart lib/core/logger_service.dart test/task_provider_test.dart test/sync_service_test.dart
flutter test test/task_provider_test.dart test/sync_service_test.dart
```

Expected: analyzer clean and provider/sync tests pass.

- [x] **Step 6: Commit**

```bash
git add lib/features/tasks/providers/task_provider.dart lib/core/sync_service.dart lib/core/logger_service.dart test/task_provider_test.dart test/sync_service_test.dart
git commit -m "fix: serialize persistence and harden local sync"
```

---

### Task 4: Secure diagnostics and sensitive preference handling

**Files:**
- Modify: `lib/core/logger_service.dart`
- Modify: `lib/features/settings/providers/settings_provider.dart`
- Modify: `lib/features/settings/widgets/sync_bottom_sheet.dart`
- Modify: `test/settings_provider_test.dart`
- Modify: `test/sync_service_test.dart`

**Interfaces:**
- Consumes: compile-time Telegram configuration, `syncSecret`, settings persistence, and sync UI.
- Produces: secret-safe diagnostics and a clear policy for local shared-secret storage, with no secret values in messages or exported/logged payloads.

- [x] **Step 1: Add failing redaction tests**

Add tests around a pure redaction helper or observable log output:

```dart
test('redacts configured sync secret from diagnostic text', () {
  expect(LoggerService.redactSensitive('peer rejected secret=1234', ['1234']),
      'peer rejected secret=[REDACTED]');
});
```

Also verify sync status/log messages do not contain the payload or configured secret.

- [x] **Step 2: Implement centralized redaction**

Add a small `LoggerService.redactSensitive(String message, Iterable<String> secrets)` helper that replaces non-empty secrets with `[REDACTED]`. Apply it at log-entry creation and before Telegram upload. Keep URLs, task counts, IDs, and generic error keys; remove raw exception text from user-facing error strings where it can expose file paths or network data.

- [x] **Step 3: Review secret persistence and document the limitation**

If the current product requires sync secrets to survive restart, keep the existing preference key only if no secure-storage dependency is already present; otherwise do not introduce a new dependency without a separate decision. Add a developer-documentation note that `SharedPreferences` is not encrypted and that production builds should migrate sync secrets to platform secure storage before treating them as high-value credentials.

- [x] **Step 4: Run focused validation**

Run:

```bash
dart format lib/core/logger_service.dart lib/features/settings/providers/settings_provider.dart lib/features/settings/widgets/sync_bottom_sheet.dart test/settings_provider_test.dart test/sync_service_test.dart
dart analyze lib/core/logger_service.dart lib/features/settings/providers/settings_provider.dart lib/features/settings/widgets/sync_bottom_sheet.dart test/settings_provider_test.dart test/sync_service_test.dart
flutter test test/settings_provider_test.dart test/sync_service_test.dart
```

Expected: analyzer clean and focused tests pass.

- [x] **Step 5: Commit**

```bash
git add lib/core/logger_service.dart lib/features/settings/providers/settings_provider.dart lib/features/settings/widgets/sync_bottom_sheet.dart test/settings_provider_test.dart test/sync_service_test.dart docs/DEVELOPER.md
git commit -m "fix: redact secrets from diagnostics"
```

---

### Task 5: Fix confirmed platform and notification configuration risks

**Files:**
- Modify: `lib/core/notification_service.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/main/res/values/strings.xml`
- Modify: `android/app/src/main/res/values-en/strings.xml`
- Modify: `android/app/src/main/res/xml/asa_widget_info.xml`
- Modify: `android/app/src/main/res/xml/widget_tasks_info.xml`
- Modify: `android/app/src/main/res/xml/widget_stats_info.xml`
- Modify: `ios/Runner/Info.plist` only for confirmed missing permission/configuration keys
- Modify: `test/notification_service_test.dart`
- Test: Android resource/compile checks and notification contract tests

**Interfaces:**
- Consumes: current notification scheduling/action contract and native widget data keys.
- Produces: explicit channel/permission/resource declarations and platform-safe notification behavior without changing the period-start timer action.

- [x] **Step 1: Add contract tests for notification behavior**

Extend `test/notification_service_test.dart` with pure tests for stable task IDs, next occurrence behavior, complete-period eligibility, and payload parsing. Assert that web/unsupported platforms do not attempt native scheduling through the existing guards.

- [x] **Step 2: Inspect native resource constraints**

Run:

```bash
(cd android && ./gradlew :app:processDebugResources :app:compileDebugKotlin --no-daemon)
```

Inspect all widget XML `minWidth`, `minHeight`, resize modes, text truncation, and plural resources. Record any mismatch between the Dart `HomeWidgetService` keys and Kotlin providers before changing them.

- [x] **Step 3: Implement only confirmed platform fixes**

Ensure notification channel names/descriptions are localized through Android resources where the plugin supports it, runtime permission requests remain contextual, and scheduled task notifications preserve an `AndroidNotificationAction` whose action id is `_startTimerActionId` (`'start_timer'`), whose label is `_tr('Запустить таймер', 'Start timer')`, and whose `showsUserInterface` is `true`.

Ensure each widget provider has safe fallback content, content descriptions, bounded text, and resize metadata that matches its layout. Do not add broad permissions unless a feature uses them; remove any permission proven unused by code and platform documentation.

- [x] **Step 4: Run platform checks**

Run:

```bash
flutter test test/notification_service_test.dart
dart analyze lib/core/notification_service.dart test/notification_service_test.dart
(cd android && ./gradlew :app:processDebugResources :app:compileDebugKotlin --no-daemon)
```

Expected: all commands exit 0. If a physical-device-only behavior cannot be tested, record the exact manual test matrix in `docs/DEVELOPER.md` rather than claiming it verified.

- [x] **Step 5: Commit**

```bash
git add lib/core/notification_service.dart android ios/Runner/Info.plist test/notification_service_test.dart docs/DEVELOPER.md
git commit -m "fix: verify notification and widget platform contracts"
```

---

### Task 6: Address measured accessibility and performance issues without a broad UI rewrite

**Files:**
- Modify: `lib/main.dart` only if profiling confirms the global capture boundary is costly
- Modify: `lib/core/theme_switcher.dart`
- Modify: `lib/features/tasks/widgets/task_card.dart`
- Modify: `lib/features/tasks/widgets/folder_card.dart`
- Modify: `lib/features/tasks/screens/folder_detail_screen.dart`
- Modify: `lib/features/settings/widgets/avatar_section.dart`
- Modify: `test/home_screen_test.dart`
- Modify: `test/folder_detail_screen_test.dart`
- Test: widget tests, semantics checks, and profile-mode evidence where available

**Interfaces:**
- Consumes: existing row/card widgets, theme transition overlay, Provider selectors, and avatar path.
- Produces: stable semantics/tap targets, bounded image decoding, and narrower rebuild/animation work while preserving visual behavior.

- [x] **Step 1: Add failing accessibility/widget tests**

Add tests that pump representative task/folder rows and assert:

```dart
expect(tester.getSemantics(find.byKey(const ValueKey('task-row-task-1'))),
    matchesSemantics(label: contains('Task')));
expect(tester.getSize(find.byTooltip('Paste')).width, greaterThanOrEqualTo(48));
```

Use the project’s actual keys/tooltips and add keys only where a stable test locator is missing.

- [ ] **Step 2: Verify behavior at large text scale — Blocked: 1.5x widget verification is not available in the current harness.**

Run the affected widget tests with a `MediaQuery` using `textScaler: const TextScaler.linear(1.5)` and confirm no overflow exceptions. Add a regression test for long task/folder names and custom settings text.

- [x] **Step 3: Implement narrow performance/accessibility fixes**

- Use `FadeTransition`/`AnimatedOpacity` only where it avoids an unnecessary `Opacity` save layer, preserving the existing animation controllers.
- Add `cacheWidth`/`cacheHeight` based on the displayed avatar size before constructing `FileImage`.
- Pass static overlay content through `AnimatedBuilder.child` or `ListenableBuilder` so it is not rebuilt every animation tick.
- Add/retain `Semantics` labels and `Tooltip`s for icon-only controls; keep interactive targets at least 48 logical pixels.
- Use `context.select` or row-level selectors only when the existing provider identity and animation behavior remain correct.

Do not remove the theme transition boundary or redesign all fixed-height rows without a failing test or profile evidence.

- [ ] **Step 4: Run focused validation — Blocked: `folder_detail_screen_test.dart` and `task_folder_popup_menu_test.dart` hang after startup; analyzer and formatting pass, but no overflow-free widget run can be claimed.**

Run:

```bash
dart format lib/main.dart lib/core/theme_switcher.dart lib/features/tasks/widgets/task_card.dart lib/features/tasks/widgets/folder_card.dart lib/features/tasks/screens/folder_detail_screen.dart lib/features/settings/widgets/avatar_section.dart test/home_screen_test.dart test/folder_detail_screen_test.dart
dart analyze lib/main.dart lib/core/theme_switcher.dart lib/features/tasks/widgets/task_card.dart lib/features/tasks/widgets/folder_card.dart lib/features/tasks/screens/folder_detail_screen.dart lib/features/settings/widgets/avatar_section.dart test/home_screen_test.dart test/folder_detail_screen_test.dart
flutter test test/home_screen_test.dart test/folder_detail_screen_test.dart
```

Expected: no analyzer issues, no overflow exceptions, and focused tests pass.

- [x] **Step 5: Commit**

```bash
git add lib/main.dart lib/core/theme_switcher.dart lib/features/tasks/widgets/task_card.dart lib/features/tasks/widgets/folder_card.dart lib/features/tasks/screens/folder_detail_screen.dart lib/features/settings/widgets/avatar_section.dart test/home_screen_test.dart test/folder_detail_screen_test.dart
git commit -m "perf: tighten task UI rebuilds and accessibility"
```

---

### Task 7: Complete provider edge-case coverage and correct only proven logic bugs

**Files:**
- Modify: `lib/features/tasks/providers/task_provider.dart` only for confirmed failing edge cases
- Modify: `lib/features/tasks/models/task_model.dart` only for confirmed serialization issues
- Modify: `lib/core/input_utils.dart` only for confirmed parser inconsistencies
- Modify: `test/task_provider_test.dart`
- Modify: `test/task_model_test.dart`
- Modify: `test/input_utils_test.dart`

**Interfaces:**
- Consumes: current CRUD, reorder, streak, timer, copyWith, parser, and persistence APIs.
- Produces: regression coverage for boundary indices, folder cascades/cycles, stale streak data, input limits, and legacy serialization without speculative model rewrites.

- [x] **Step 1: Add boundary tests before implementation changes**

Cover:

```dart
test('reorder accepts moving the last item to the first position', () {
  // Arrange three root folders, move index 2 to index 0, assert order.
});

test('folder names use the same maximum length rule as task titles', () {
  expect(() => provider.addFolder('x' * 251), throwsA(isA<Exception>()));
});

test('malformed persisted records are skipped without losing valid records', () async {
  // Seed one valid and one malformed JSON record, await provider.ready, assert valid remains.
});
```

Use complete executable tests in the existing test style; do not leave comments as test bodies.

- [x] **Step 2: Run focused tests and classify failures**

Run:

```bash
flutter test test/task_provider_test.dart test/task_model_test.dart test/input_utils_test.dart
```

Only fix behavior whose failure is reproducible and attributable to production code. If a suspected item passes, document it as reviewed and do not change it.

- [x] **Step 3: Implement minimal fixes for confirmed failures**

Preserve public signatures. Use `copyWith` where model immutability is part of the tested contract, batch recursive folder deletion into one notification/persistence operation, and reject invalid reorder indices without mutating state. Keep system streak-folder protections intact.

- [ ] **Step 4: Run focused and full validation — Blocked: focused non-widget tests pass, but the full/widget suite hangs.**

Run:

```bash
dart format lib/features/tasks/providers/task_provider.dart lib/features/tasks/models/task_model.dart lib/core/input_utils.dart test/task_provider_test.dart test/task_model_test.dart test/input_utils_test.dart
dart analyze lib/features/tasks/providers/task_provider.dart lib/features/tasks/models/task_model.dart lib/core/input_utils.dart test/task_provider_test.dart test/task_model_test.dart test/input_utils_test.dart
flutter test test/task_provider_test.dart test/task_model_test.dart test/input_utils_test.dart
```

Expected: analyzer clean and all focused tests pass.

- [x] **Step 5: Commit**

```bash
git add lib/features/tasks/providers/task_provider.dart lib/features/tasks/models/task_model.dart lib/core/input_utils.dart test/task_provider_test.dart test/task_model_test.dart test/input_utils_test.dart
git commit -m "test: cover provider and model boundary cases"
```

---

### Task 8: Dependency, documentation, and release-readiness audit

**Files:**
- Modify: `pubspec.yaml` only for confirmed unused/incompatible dependencies
- Modify: `README.md`
- Modify: `docs/DEVELOPER.md`
- Modify: `docs/superpowers/plans/2026-07-31-full-standards-review-remediation.md` to record completed gates/findings
- Test: dependency and platform build commands

**Interfaces:**
- Consumes: all prior remediation results and exact project commands.
- Produces: accurate onboarding/release documentation and a reproducible release checklist.

- [x] **Step 1: Verify dependency usage and updates**

Run:

```bash
flutter pub deps --style=compact
flutter pub outdated --no-transitive
```

Search each direct dependency in `lib/` and platform files. Remove only a dependency proven unused and update `pubspec.lock` only through the package manager. Do not upgrade packages in this review unless a current vulnerability or build incompatibility is confirmed.

- [x] **Step 2: Replace the template README with accurate project instructions**

Document the actual app purpose, supported platforms, local-first data model, sync/security limitations, test commands, Android arm64 release command, required notification/calendar/local-network permissions, and the fact that release signing credentials are external and must never be committed.

- [x] **Step 3: Update developer documentation with verified findings**

Add sections for:

- analyzer/format/test commands;
- import size and JSON validation limits;
- sync frame/HMAC rules and web raw-socket limitation;
- secret-storage limitation and redaction behavior;
- physical-device manual test matrix for notifications, widgets, calendars, TalkBack, VoiceOver, large text, and LAN discovery;
- release build/signing and obfuscation recommendations.

- [ ] **Step 4: Run release gates — Partial: Android/arm64 and diagnostic web build pass; ordinary web and full Flutter test remain blocked.**

Run the commands supported by the local machine:

```bash
dart format --output=none --set-exit-if-changed .
dart analyze
flutter test
(cd android && ./gradlew :app:compileDebugKotlin :app:processDebugResources --no-daemon)
flutter build apk --target-platform android-arm64 --split-per-abi --release
flutter build web
```

Run iOS/macOS/Linux/Windows builds only when the corresponding SDK/toolchain is installed; otherwise record the exact unavailable toolchain and do not claim those builds passed.

- [x] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock README.md docs/DEVELOPER.md docs/superpowers/plans/2026-07-31-full-standards-review-remediation.md
git commit -m "docs: document standards review and release gates"
```

---

### Task 9: Final independent review and clean-state verification

**Files:**
- Review: all changed files and the complete commit range created by this plan
- Test: full verification commands

**Interfaces:**
- Consumes: all prior task commits and documented platform limitations.
- Produces: an evidence-backed final report with confirmed fixes, unresolved risks, and exact commands/results.

- [x] **Step 1: Run independent code review**

Ask a fresh reviewer to inspect the final diff for security, data loss, async races, platform regressions, accessibility, and test gaps. Resolve every blocker before completion; record non-blocking recommendations in the final report.

- [ ] **Step 2: Run the complete verification gate — Blocked: full `flutter test` and ordinary web release gate do not complete in this environment.**

Run:

```bash
git diff --check HEAD~9 HEAD
dart format --output=none --set-exit-if-changed .
dart analyze
flutter test
(cd android && ./gradlew :app:compileDebugKotlin :app:processDebugResources --no-daemon)
```

Also run the release/build commands from Task 8 that are supported locally.

- [ ] **Step 3: Verify repository state and commits — Pending until the evidence commit is created and checked.**

Run:

```bash
git status --short --branch
git log --oneline -n 12
```

Expected: no uncommitted source changes, no generated artifacts staged, and one focused commit per completed task.

- [x] **Step 4: Write the final review report**

Report separately:

1. confirmed defects fixed;
2. tests/builds that passed with counts;
3. platform checks unavailable locally;
4. security findings and remaining SharedPreferences/Telegram limitations;
5. non-blocking follow-up recommendations;
6. exact commit hashes.

Do not claim real-device behavior was verified without a real-device test result.
