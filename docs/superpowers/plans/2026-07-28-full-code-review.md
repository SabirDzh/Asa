# Full Code Review Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Line-by-line audit of every Dart file in `lib/` and `test/` — architecture, performance, security, state management, widget practices, i18n, error handling, testing coverage, and documentation.

**Architecture:** 12 lib files + 1 test file, ~4900 total lines. Flutter 3.44.8 / Dart 3.12.2, Provider + ChangeNotifier, shared_preferences persistence, no backend.

**Tech Stack:** Flutter 3.44.8, Dart 3.12.2, Provider, shared_preferences, google_fonts, uuid, image_picker, flutter_image_compress

## Global Constraints

- Flutter == 3.44.8 (timeDilation for animation speed, onReorderItem, DialogThemeData)
- Dart SDK ^3.7.2 (currently 3.12.2)
- `dart analyze lib/` must pass with zero issues
- APK must build: `JAVA_HOME=/opt/homebrew/opt/openjdk@21 flutter build apk`
- All existing tests must pass: `flutter test`

---

### Task 1: Architecture & Project Structure

**Files:**
- Review: all 12 files in `lib/`
- Review: `pubspec.yaml`
- Review: `analysis_options.yaml`

**Areas:**
- File responsibilities: does each file have one clear purpose?
- Layering: do features/settings, features/tasks cross-import correctly?
- Dependency graph: are there circular dependencies?
- Flutter conventions: is the project structured per Flutter best practices (feature-first, not layer-first)?

**Checklist:**

- [ ] **Verify layer isolation** — `features/settings/` and `features/tasks/` should NOT import each other. Both may import `core/`. Grep for cross-feature imports: `rg 'features/(settings|tasks).*' lib/features/`

- [ ] **Check `core/` for misplaced logic** — `core/theme.dart` should only hold theme data. Verify AppStrings (localization) belongs in settings_provider, not in core. Patterns: if a core file references features/, it's misplaced.

- [ ] **Verify `main.dart` responsibilities** — should only wire up providers and MaterialApp. Grep for business logic, navigation, or data access in `main.dart`.

- [ ] **Check pubspec.yaml for unused dependencies** — run `flutter pub deps -- -s compact` and verify each dependency is actually imported somewhere.

- [ ] **Audit analysis_options.yaml** — verify `flutter_lints/flutter.yaml` is active. Check if additional lint rules should be enabled (prefer_const_constructors, prefer_const_literals_to_create_immutables, avoid_print, etc.). Flutter 3.44.8 may have new lint rules.

- [ ] **Check for feature-envy / god files** — settings_screen.dart (713 lines) and folder_detail_screen.dart (547 lines) are large. Decide if _showEditSheet, _showCreateSheet, _showPopupMenu patterns should be extracted.

---

### Task 2: State Management (Provider + ChangeNotifier)

**Files:**
- Review: `lib/features/tasks/providers/task_provider.dart`
- Review: `lib/features/settings/providers/settings_provider.dart`
- Review: all Consumer / Provider.of calls in widget files

**Issues to check:**
- Over-notification: `notifyListeners()` called even when no data changed
- Unnecessary rebuilds: `Provider.of<T>(context)` vs `context.watch<T>()` vs `context.read<T>()`
- Provider.of<T>(context, listen: false) used for event handlers (correct) vs build methods (incorrect)
- Async gaps: async methods after notifyListeners() without guarding with `mounted`
- Data mutation: mutable model fields changed outside of notifyListeners()

- [ ] **Audit `notifyListeners()` calls in task_provider.dart** — every method that calls `notifyListeners()` should actually change state. Look for redundant calls.

- [ ] **Check `_saveToPrefs()` is called after every mutation in task_provider.dart** — verify async save is fire-and-forget (no await) to avoid blocking UI. Check that exceptions are caught (they are — bare `catch (_) {}`).

- [ ] **Audit `context.read<T>()` vs `context.watch<T>()` usage** — in build methods, use `watch` or `Provider.of<T>()` (listen defaults to true). In callbacks/event handlers, use `read` or `Provider.of<T>(listen: false)`. Grep for incorrect patterns: `rg 'read<.*Provider>' lib/` in build methods.

- [ ] **Check SettingsProvider._loadSettings()** — it's async, called in constructor. Verify that `timeDilation` is set after `SharedPreferences` loads (line 137), ensuring animation speed applies on cold start.

- [ ] **Check Provider disposal** — verify no providers hold resources (streams, timers) that need cleanup. ChangeNotifier doesn't require dispose unless there are subscriptions.

---

### Task 3: Performance

**Files:**
- Review: all widget files (folder_detail_screen, home_screen, folder_card, task_card, settings_screen, theme_switcher)
- Review: `lib/core/input_utils.dart`

**Performance anti-patterns to find:**
- Unnecessary rebuilds from Provider in large lists
- RepaintBoundary placement
- const constructors on widgets (reduces rebuild cost)
- ListView vs Column for dynamic content
- Image decoding size
- AnimationController lifecycle
- `AnimatedBuilder` vs `AnimatedWidget` usage
- Over-use of Opacity widget (causes save-layer) vs `withOpacity` on Color

- [ ] **Check `Consumer<TaskProvider>` in folder_detail_screen.dart** — it rebuilds the entire list on any task change. Verify this doesn't cause jank with many tasks (>100).

- [ ] **Inspect `ReorderableListView` usage** — in folder_detail_screen.dart, all children are rebuilt on change. Check if `key`s are stable (they use `ValueKey(sf.id)` and `ValueKey(t.id)` — good).

- [ ] **Audit `const` constructors** — run `dart analyze` with `--fatal-infos` for missing const constructors. Every widget with `super.key` should be `const`-constructable if its fields are final.

- [ ] **Check Opacity vs `withOpacity`** — `Opacity` widget creates a save layer. Grep for `Opacity(` in widget files. If used for simple color opacity, replace with `Color.withValues(alpha: ...)`.

- [ ] **Inspect `theme_switcher.dart`** — `RawImage` with full-screen bitmap: verify resolution (pixelRatio from View.of(context) is correct). Check that the overlay image doesn't cause OOM on low-end devices.

- [ ] **Check `ScrollController` disposal** — in folder_detail_screen.dart, `_breadcrumbScroll` is disposed in `dispose()`. Verify no other controllers leak.

- [ ] **Audit `AnimatedBuilder` vs `ListenableBuilder`** — Flutter 3.44.8 may have newer APIs. `AnimatedBuilder` is fine but check for unnecessary rebuilds.

- [ ] **Check `Image.file` in settings_screen.dart** — displayed avatar Image is not cached. Verify it doesn't re-decode on every build (wrap in `RepaintBoundary` or add cacheWidth/cacheHeight).

---

### Task 4: Security

**Files:**
- Review: all files
- Review: `pubspec.yaml`

**Flutter-specific security considerations:**
- No backend, so no network injection vectors
- SharedPreferences stores plaintext data (task names, settings)
- Image picker reads from gallery (local only)
- No WebView, no JavaScript evaluation

- [ ] **Check SharedPreferences for sensitive data** — task names and folder names are stored as plain JSON. Verify no sensitive data (passwords, tokens) is stored.

- [ ] **Verify image path handling** — `settings_screen.dart` constructs file paths with `getApplicationDocumentsDirectory()`. Verify path traversal is impossible (it uses `'$dir/avatar_$timestamp.webp'` — safe).

- [ ] **Check input sanitization** — `lib/core/input_utils.dart` strips control characters via `sanitizeText()`. Verify it's applied to all TextField onSubmitted/onChanged callbacks. Check that unfiltered paths exist (none should after our edits).

- [ ] **Audit `Exception` message exposure** — SnackBars display `e.toString().replaceAll('Exception: ', '')`. Verify no sensitive info is leaked in exceptions (task_provider.dart throws `Exception('Название длиннее 250 символов')` — safe).

- [ ] **Check `image_picker` usage** — it accesses device gallery. Verify that `Info.plist` (iOS) has `NSPhotoLibraryUsageDescription`. Check `AndroidManifest.xml` for required permissions.

---

### Task 5: Dart & Flutter Best Practices

**Files:**
- Review: all 12 files

**Key checks:**
- Null safety: all variables properly null-checked
- Immutability: prefer final fields
- Collection usage: `[]` vs `List()` vs `[] as List`
- Async: proper Future handling, no unawaited futures
- Error handling: try/catch coverage
- Avoid `!` (bang operator) where pattern matching or `?.` works

- [ ] **Audit null safety** — grep for `!` null assertions in `lib/`. Each should be justified: `context.read<T>()!` is unnecessary (Provider always returns non-null). Check `rg '!\b' lib/`.

- [ ] **Check `final` vs `var`** — fields that are never reassigned should be `final`. Grep for mutable fields in model classes (`task_provider.dart` has `_tasks` and `_folders` as `final List` — good, only contents mutate).

- [ ] **Verify `copyWith` is used consistently** — `task_model.dart` defines `TaskItem.copyWith()` but the provider mutates `_tasks[index].isCompleted = !_tasks[index].isCompleted` directly instead of using `copyWith`. Check if this causes issues with immutability assumptions.

- [ ] **Check `toString()` on exceptions in SnackBars** — every `onSubmitted` handler calls `e.toString().replaceAll('Exception: ', '')`. Verify this is consistent across all 5 TextField handlers.

- [ ] **Audit `Future.delayed` / timer usage** — check task_provider.dart for any timers that need cleanup. The daily streak check uses SharedPreferences (no timers).

- [ ] **Check `mounted` checks** — after `await` in async methods, verify `if (!context.mounted) return`. The `_showPopupMenu` methods in task_card.dart and folder_card.dart check `iconContext.mounted` — verify it's sufficient.

- [ ] **Verify `Values` extension usage** — Flutter 3.44.8 replaces `withOpacity()` with `withValues(alpha: ...)`. Verify no deprecated `withOpacity()` calls remain.

---

### Task 6: Widget Tree & UI Best Practices

**Files:**
- Review: all widget files

**Flutter widget anti-patterns:**
- Nesting: excessive nesting hurts readability and perf
- SizedBox vs Padding vs Container patterns
- GestureDetector vs InkWell (material ripple)
- ListView.builder vs Column for long lists
- Overflow handling

- [ ] **Audit widget nesting depth** — folder_detail_screen.dart:363-543 has the _FolderFloatingMenu with 5 levels of Positioned/Stack/IgnorePointer/etc. Check if it can be flattened.

- [ ] **Check GestureDetector vs InkWell** — all tappable rows use `GestureDetector`, not `InkWell`, so there's no ripple effect. Verify this is intentional (matches Figma design).

- [ ] **Verify `SafeArea` usage** — home_screen.dart uses `SafeArea(bottom: false)` for the main body. The bottom nav bar is rendered separately. Verify content doesn't overlap with system UI on notched devices.

- [ ] **Check `MediaQuery` calls** — repeated `MediaQuery.of(context)` calls in build methods. Consider caching or using `LayoutBuilder`.

- [ ] **Verify `textScaleFactor` handling** — check that UI doesn't break with large system font sizes. The app uses fixed heights (`AppTheme.rowHeight = 56`), which may overflow with large text.

- [ ] **Check `Theme.of(context)` calls** — verify they're consistent. `context.isDarkMode` pattern might be cleaner than repeating `Theme.of(context).brightness == Brightness.dark`.

- [ ] **Verify `RepaintBoundary` strategy** — main.dart wraps the entire app in RepaintBoundary for the theme switcher. Check that this doesn't cause unnecessary repaints of the whole app on every frame.

---

### Task 7: Error Handling & Edge Cases

**Files:**
- Review: `lib/features/tasks/providers/task_provider.dart`
- Review: all `onSubmitted` handlers

- [ ] **Verify all async init errors are caught** — `_loadFromPrefs()` has `catch (_) {}` (silent). When shared_preferences fails, the app starts with empty data. Check if this is acceptable or if a retry/user notification is needed.

- [ ] **Check empty states** — home_screen.dart shows `nothing_found` / `empty_list` text. folder_detail_screen.dart shows `no_tasks_in_folder`. Verify ALL empty states are handled: search returns nothing, folder has no tasks, filter shows nothing.

- [ ] **Verify streak logic edge cases** — task_provider.dart:196-217. Check: leap year dates, timezone changes, first-ever launch (no `lastLoginDate`), date string parsing failures (caught). Check `daysDiff` logic: `daysDiff == 2` has empty body (falls through to `daysDiff == 3` case). Verify this is intentional.

- [ ] **Check reorder boundary conditions** — `reorderRootFolders` and `reorderFolderTasks` both check `oldIndex >= 0 && oldIndex < list.length`. Verify that when dragging an item to position 0 or to the end, the newIndex is valid.

- [ ] **Verify folder deletion cascades** — `removeFolder(id)` recursively deletes child folders and their tasks. Check: system streak folders are protected (`isSystemStreak` check). Verify infinite recursion is impossible (parentId chains can't form cycles — but there's no cycle detection).

- [ ] **Test avatar file lifecycle** — when changing avatar, the old file is deleted (try/catch with `_`). When clearing app data, avatar file is NOT deleted. Verify this is intentional.

---

### Task 8: Internationalization & Localization

**Files:**
- Review: `lib/features/settings/providers/settings_provider.dart:6-102`

- [ ] **Verify all user-facing strings use `settings.tr()`** — grep for hardcoded Russian/English strings in widget files that bypass `tr()`. Lines with `settings.tr('...')` are correct. Lines with raw strings like `'Редактировать задачу'` are bugs.

- [ ] **Check i18n key coverage** — every key in `ru` map must have a matching key in `en` map. List any missing translations.

- [ ] **Verify `languageCode` persistence** — `setLanguage()` saves to SharedPreferences. Verify it loads on app restart (it does — `_loadSettings()` reads `languageCode`).

- [ ] **Check RTL support** — if Arabic/Hebrew is ever needed, verify `Directionality` handling. Currently only RU/EN (both LTR) — acceptable.

---

### Task 9: Testing Coverage

**Files:**
- Review: `test/widget_test.dart`
- Review: all lib files for testability

- [ ] **Audit current test** — only 1 smoke test (renders app). Verify it actually exercises meaningful logic.

- [ ] **Check testability of providers** — TaskProvider and SettingsProvider both call async init in constructors. In tests, this means SharedPreferences must be initialized. Verify `SharedPreferences.getInstance()` is mocked or `SharedPreferences.setMockInitialValues({})` is called.

- [ ] **Identify critical untested paths**:
  - `toggleTask()` + exit animation (timing-sensitive)
  - Streak logic: `checkDailyStreak()` with varying `daysDiff`
  - Reorder logic: `reorderRootFolders`, `reorderFolderTasks` with edge indices
  - Input sanitization: `sanitizeText()`, `numericInputFormatter()`, `parseAndClampSpeed()`
  - Folder CRUD: `addFolder`, `updateFolder`, `removeFolder` with child cascading

- [ ] **Verify unit tests exist for `input_utils.dart`** — `numericInputFormatter`, `sanitizeText`, `parseAndClampSpeed` are pure functions and should have unit tests.

---

### Task 10: Documentation & Comments

**Files:**
- Review: all 12 files

- [ ] **Audit doc comments** — check that public APIs have doc comments. The project currently has minimal documentation. Identify which public functions/classes need docs.

- [ ] **Remove stale comments** — grep for commented-out code blocks. The template-generated comments in pubspec.yaml and test/widget_test.dart are noise.

- [ ] **Check TODO/FIXME markers** — `rg 'TODO|FIXME|HACK|XXX' lib/`. Any unresolved items need either resolution or a ticket reference.

- [ ] **Verify README.md** — if it exists, check it's accurate. If not, the plan should note that documentation is missing.

- [ ] **Check `analysis_options.yaml` comments** — the template comments are boilerplate. Consider cleaning up.

---

### Task 11: Build & Deploy Verification

**Files:**
- Review: `android/` and `ios/` native configurations
- Review: `pubspec.yaml`

- [ ] **Build release APK** — `JAVA_HOME=/opt/homebrew/opt/openjdk@21 flutter build apk`. Verify `51.8 MB` size is expected (it includes all native libs for multiple ABIs).

- [ ] **Check Android `minSdkVersion`** — verify it's compatible with all dependencies (image_picker v1.2.3 requires minSdk 21, flutter_image_compress may require higher).

- [ ] **Verify iOS build** — `flutter build ios --no-codesign` (if on macOS). Check `Podfile` `platform :ios` version.

- [ ] **Run `dart analyze` with all infos** — `dart analyze lib/`. Verify zero issues.

- [ ] **Run full test suite** — `flutter test`. Verify all pass.

---

### Task 12: Summary & Remediation Plan

**All 11 review tasks completed by subagents.** Compiled findings below.

---

## Consolidated Findings

### P0 — Blocks Build (0)

None.

### P1 — Runtime Crash / Data Loss

| # | File:Line | Issue | Severity |
|---|-----------|-------|----------|
| 1 | `settings_provider.dart:131` | `_loadSettings()` has no try-catch at all. `SharedPreferences.getInstance()` crash = widget tree crash. | **P1** |
| 2 | `settings_screen.dart:600-604` | `ThemeSwitcher.switchTheme` called with potentially stale context after `showDialog`. | **P1** |
| 3 | `folder_card.dart:165` / `task_card.dart:165` | `findRenderObject()` as `RenderBox` can return null even when mounted — null crash. | **P1** |

### P2 — Visual / UX Bugs

| # | File:Line | Issue | Severity |
|---|-----------|-------|----------|
| 4 | `settings_screen.dart:276,291,303,317` | 4 hardcoded Russian strings in custom speed sheet (not i18n). | **P2** |
| 5 | `folder_card.dart:298,306` | 2 hardcoded Russian snackbar strings (not i18n). | **P2** |
| 6 | `home_screen.dart:128,138,186` + all rows | GestureDetector without InkWell (no ripple) on 16 primary interactive elements — no tap feedback. | **P2** |
| 7 | All files, 38 refs | Fixed `rowHeight: 56` overflows at textScaleFactor ≥1.5 — inaccessible for visually impaired users. | **P2** |
| 8 | `task_provider.dart:92-93` | Empty `if (daysDiff == 2) {}` body with no comment — streak silently stays frozen for 1-day skip. | **P2** |
| 9 | `settings_screen.dart:122-127` | `_getAnimationSpeedLabel` hardcoded to 0.5/1.0/2.0 — custom speed shows raw float with trailing zeros. | **P2** |

### P3 — Performance

| # | File:Line | Issue | Severity |
|---|-----------|-------|----------|
| 10 | `main.dart:41` | Whole-app `RepaintBoundary` always-on — forces full app into offscreen render target 100% of time. | **P3** |
| 11 | `folder_detail_screen.dart:268` | Single `Consumer<TaskProvider>` rebuilds entire list on any task change — O(n) per toggle with 100+ tasks. | **P3** |
| 12 | `settings_screen.dart:507-508` | Avatar `FileImage` decoded at full camera resolution for 100×100 circle. Missing `cacheWidth: 200`. | **P3** |
| 13 | `theme_switcher.dart:90-103` | `AnimatedBuilder` doesn't pass `child:` parameter — `RawImage` rebuilt every frame. | **P3** |
| 14 | `task_card.dart:318,334` | `Opacity` widget in exit/entrance animation triggers save-layer. Use `FadeTransition`. | **P3** |
| 15 | `folder_detail_screen.dart:229` | `GestureDetector(behavior: HitTestBehavior.translucent)` intercepts keyboard dismissal taps. | **P3** |
| 16 | `theme_switcher.dart:95` | Full-screen `RawImage` at devicePixelRatio (~43 MB on 3x iPhone). OOM risk on 2 GB RAM devices. | **P3** |
| 17 | `folder_card.dart:324`, `task_card.dart:352` | Repeated `MediaQuery.of(context)` in every build — cache once. | **P3** |

### P4 — Code Quality / Architecture

| # | File:Line | Issue | Severity |
|---|-----------|-------|----------|
| 18 | Global | Bi-directional cross-feature import: tasks ↔ settings. AppStrings (localization) should be in `core/`. | **P4** |
| 19 | `settings_provider.dart:5-108` | `AppStrings` in `features/settings/providers/` forces every feature to depend on settings. | **P4** |
| 20 | `settings_screen.dart` (713 lines) | God file: 6 bottom sheets + dialog + avatar + build. Extract each sheet to separate widget. | **P4** |
| 21 | `folder_detail_screen.dart` (547 lines) | God file: embedded `_FolderFloatingMenu` (177 lines) + breadcrumbs + create sheet. | **P4** |
| 22 | Global, ~10 sites | Duplicated bottom sheet template (handle + gap + input row) — extract to shared widget. | **P4** |
| 23 | `task_provider.dart` | Direct mutation: `_tasks[index].isCompleted = ...` instead of `copyWith()`. `copyWith` is dead code. | **P4** |
| 24 | `task_provider.dart:282-292` | `removeFolder()` calls `notifyListeners()` per recursive child _and_ for parent — O(n) rebuilds. | **P4** |
| 25 | `folder_detail_screen.dart:58` | `_buildBreadcrumbs` uses `listen: false` — breadcrumbs don't update on folder rename. | **P4** |
| 26 | `input_utils.dart:24-30` | `parseAndClampSpeed()` is defined but never called — dead code. Speed sheet duplicates logic inline. | **P4** |
| 27 | `pubspec.yaml:36` | `cupertino_icons` imported 0 times — unused dependency. | **P4** |
| 28 | `theme_switcher.dart:90` / `folder_detail_screen.dart:302` / `home_screen.dart:302` | `AnimatedBuilder` deprecated since Flutter 3.22 — use `ListenableBuilder`. | **P4** |
| 29 | `task_provider.dart:108-121` | Streak folders accumulate indefinitely (new `"День N"` on each login, old ones never removed). | **P4** |
| 30 | `task_provider.dart:255-267` | `addFolder` missing 250-char length cap (unlike `addTask`). | **P4** |
| 31 | `settings_screen.dart:401` | `TextStyle(color: AppColors.textSecondaryLight)` hardcoded to light mode — low contrast in dark theme. | **P4** |
| 32 | Global, all 12 files | Missing file-level /// doc comments. | **P4** |
| 33 | `pubspec.yaml`, `analysis_options.yaml` | ~20 lines of stale Flutter template comments. | **P4** |
| 34 | `test/widget_test.dart` | Zero-assertion smoke test. Name copy-pasted from counter template. | **P4** |
| 35 | Global | **0 tests** for: input_utils (4 pure functions), task_model (3 serialization functions), TaskProvider (20 methods), SettingsProvider (6 methods), all 6+ widgets, all 3 screens. | **P4** |

### P5 — Info / Optional

| # | File:Line | Issue | Severity |
|---|-----------|-------|----------|
| 36 | `settings_screen.dart:205`, `folder_detail_screen.dart:122`, 3 more | 5x `TextEditingController` created in bottom-sheet methods without explicit `dispose()`. GC eligible, but against best practice. | **P5** |
| 37 | `task_provider.dart:44-52` | `_saveToPrefs()` silently catches all errors — data loss invisible to user. | **P5** |
| 38 | Global, ~8 sites | Repeated `isDark ? A : B` color pattern. Use `Theme.of(context).colorScheme` instead. | **P5** |
| 39 | `input_utils.dart:6-22` | `numericInputFormatter` tested? No. Pure function, should have unit tests. | **P5** |
| 40 | `lib/core/theme.dart:5` | Misleading doc comment: "3 semantic colors" but file defines 13+ constants. | **P5** |

---

**Total: 40 findings (0 P0, 3 P1, 6 P2, 8 P3, 18 P4, 5 P5).**

## Remediation

Proceed with inline fixes in prioritized order, or dispatch subagents per priority tier. Recommend starting with P1 (crash fixes) → P2 (UX/i18n) → P3 (performance) → P4 (quality).
