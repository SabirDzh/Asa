# ASA — Developer Documentation

> **Audience:** engineers joining the project, maintainers, and anyone who wants to extend the app.  
> **Last updated:** 2026-08-13
> **Project:** [`pubspec.yaml`](../pubspec.yaml)

---

## 1. Overview

ASA is a cross-platform Flutter task manager. It supports folders, drag-and-drop reordering, time tracking, calendar integration, device-to-device sync, export/import, home screen widgets, and adaptive UI scaling. The app targets Android, iOS, Windows, macOS, and Linux from a single codebase.

Key product decisions you should know before reading the code:

* **Offline-first.** All task/folder data lives in `SharedPreferences` as JSON. Sync/export are optional add-ons.
* **Soft-delete.** Deleting a task or folder sets `isDeleted = true`. Soft-deleted records older than 7 days (`kDeletedItemRetention`) are permanently purged during startup and after every import/sync merge; nothing else is truly removed from the local list.
* **Daily streak folder.** A special `system_streak_folder` is recreated every day and named “День N”.
* **UI scale.** The entire interface is scaled via a custom `MediaQuery` transform, allowing users to adjust text and widget sizes.
* **Animations.** Most animations have a fixed logical duration, but they respect the user’s `animationSpeed` through Flutter’s `timeDilation`.

---

## 2. Tech Stack & Dependencies

| Layer | Tech |
|-------|------|
| Framework | Flutter 3.44+ / Dart 3.7+ |
| State management | `provider` (ChangeNotifier pattern) |
| Icons | `iconsax` + SVG assets |
| Local storage | `shared_preferences` |
| Images/avatar | `image_picker`, `flutter_image_compress`, `path_provider` |
| Notifications | `flutter_local_notifications` |
| Widgets | `home_widget` (Android) |
| Networking/sync | `bonsoir` (mDNS), `http`, `share_plus`, `file_picker` |
| Calendar | `device_calendar` |
| Device info | `device_info_plus` |
| Time zones | `timezone` |

See [`pubspec.yaml`](../pubspec.yaml) for exact versions.

---

## 3. Project Structure

```
lib/
├── main.dart                          # App entry point, providers, scaling
├── core/                              # Shared, framework-level code
│   ├── app_strings.dart               # Localization map (ru/en)
│   ├── bottom_sheet.dart              # showInputSheet + paste/clipboard helper
│   ├── calendar_service.dart          # Calendar provider wrapper
│   ├── clipboard_utils.dart           # Clipboard text reader
│   ├── device_info.dart               # Default device name helper
│   ├── export_import_service.dart     # Backup, restore, sync payload builder
│   ├── folder_icons.dart              # Built-in SVG folder icons
│   ├── home_widget_service.dart       # Widget update debouncer
│   ├── image_utils.dart               # Avatar compression helpers
│   ├── input_utils.dart               # Text formatters and sanitizers
│   ├── logger_service.dart            # Buffered logging + HTTPS diagnostic reporter
│   ├── notification_service.dart      # Local notifications wrapper
│   ├── responsive_center.dart         # Large-screen layout wrapper
│   ├── scale_utils.dart               # Adaptive UI scale limits
│   ├── scroll_hide_mixin.dart         # Scroll-aware FAB hide/show
│   ├── sync_service.dart              # mDNS/TCP P2P sync engine
│   ├── theme.dart                     # Colors, theme data, spacing constants
│   ├── theme_switcher.dart           # Animated theme transition overlay
│   └── version_service.dart           # GitHub release update checker
└── features/
    ├── settings/
    │   ├── providers/settings_provider.dart
    │   ├── screens/settings_screen.dart
    │   └── widgets/                   # Bottom sheets, avatar, rows, groups
    ├── splash/
    │   └── splash_screen.dart         # Init gate + update prompt
    └── tasks/
        ├── models/task_model.dart
        ├── providers/task_provider.dart
        ├── services/
        │   ├── description_index.dart
        │   └── description_link_resolver.dart
        ├── screens/
        │   ├── home_screen.dart
        │   └── folder_detail_screen.dart
        └── widgets/
            ├── folder_card.dart
            ├── task_card.dart
            ├── task_detail_sheet.dart
            └── task_time_sheet.dart
```

---

## 4. Architecture & State Management

### 4.1 Pattern

The app uses **Provider + ChangeNotifier**.

* Two top-level providers are registered in `main.dart`:
  * `SettingsProvider` — theme, language, animation speed, app scale, sync, avatar, widget settings.
  * `TaskProvider` — tasks, folders, streak state, search/filter.
* Both providers expose a `ready` future. `SplashScreen` waits on them before showing the main UI.
* UI widgets subscribe with `context.watch<T>()` or `context.select<T, V>()` for fine-grained rebuilds.

### 4.2 Provider lifecycle

```dart
// main.dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => SettingsProvider()),
    ChangeNotifierProvider(create: (_) => TaskProvider()),
  ],
  child: const AsaApp(),
)
```

Both providers start async init in their constructors:

* `SettingsProvider` loads preferences and sets `timeDilation`.
* `TaskProvider` loads persisted JSON and recalculates the streak.

`SplashScreen` uses `Future.wait([settings.ready, tasks.ready])` and only then replaces itself with `HomeScreen`.

### 4.3 Important rules

* Do **not** call `notifyListeners()` from inside a constructor before the provider is attached to a widget tree. `SettingsProvider` defers its first notification with `Future.microtask`.
* Persist happens in `_saveToPrefs()` after every mutating operation. Persistence writes are serialized and coalesced; preserve that ordering when adding bulk operations.
* `TaskItem` and `FolderItem` support `copyWith`. Use it instead of mutating fields in place.

---

## 5. Navigation & Routing

* The app uses a **bottom-navigation + PageView** on `HomeScreen`:
  * Page 0: tasks list (`HomeScreen` body)
  * Page 1: settings (`SettingsScreen`)
* Folder detail is pushed via `Navigator.push(FolderDetailScreen(...))`.
* Breadcrumbs in `FolderDetailScreen` use `Navigator.pop(...)` in a loop. Prefer `popUntil` if you refactor this area.
* Most short-lived flows (create/edit task, filters, settings options) use `showModalBottomSheet` or `showDialog`.

---

## 6. Data Layer

### 6.1 Models

[`lib/features/tasks/models/task_model.dart`](../lib/features/tasks/models/task_model.dart)

* `TaskItem` — id, title, `isCompleted`, `folderId`, `dueDate`, `startTime`, `endTime`, `expectedDuration` (minutes), calendar IDs, timestamps, `isDeleted`, and typed `infoBlocks`.
* `TaskInfoBlock` supports quantity goals and plain-text descriptions. Description blocks may reference bounded links, images, and files through `TaskAttachment`; binary bytes are never embedded in task JSON.
* `FolderItem` — id, name, `isSystemStreak`, `parentFolderId`, `iconAsset`, timestamps, `isDeleted`.
* Both classes have `toJson()` / `fromJson()` and `copyWith(...)`.  
  `copyWith` uses `Object?` sentinel values to distinguish “no change” from `null`.

### 6.2 Persistence

* `TaskProvider._saveToPrefs()` encodes `_tasks` and `_folders` as JSON strings in `SharedPreferences` and serializes/coalesces writes so stale asynchronous writes cannot overwrite newer state.
* Keys: `saved_tasks`, `saved_folders`.
* **Retention cleanup.** `TaskProvider` permanently purges soft-deleted tasks and folders whose `updatedAt` is older than `kDeletedItemRetention` (7 days). The purge runs at startup (`initData`) and inside `persist()` after import/sync merges, and deletes the attachment files of purged tasks. Legacy records without a persisted `updatedAt` are kept so old data is never accidentally purged; the system streak folder is exempt.
* Settings are persisted per-field under their own keys (see `SettingsProvider`).
* **Security limitation:** `SharedPreferences` is not encrypted storage. The optional `syncSecret` currently survives restarts in plaintext application preferences. Treat it as a local convenience secret, not a high-value credential; migrate sensitive keys to platform secure storage (for example, `flutter_secure_storage`) before relying on it for stronger at-rest protection.

### 6.3 Task information blocks and attachments

To add information to a task, create a task or open its row `…` menu and choose `Редактировать`; this opens the task editor. Tap `Добавить информацию`, then choose `Количество` or `Описание`. A description supports plain text plus `Добавить ссылку`, `Добавить изображение`, and `Добавить файл`.

The task editor keeps a local draft until the user saves. It supports two block types:

* **Quantity:** current value, target value, unit, and optional label. Values are finite, non-negative, capped at `1_000_000_000`, and reaching the target never auto-completes the task.
* **Description:** bounded plain text (10,000 characters) plus structured attachments. Links accept only `http`/`https`; files and images are copied to the app documents attachment directory on native platforms before their reference is persisted.

Attachment limits are 10 MB per file and 20 attachments per task. Export/import/sync preserve metadata and local references only; binary files are not transferred between devices. The web/stub implementation supports metadata and links but does not persist local binary attachments. Missing local files render as unavailable and must not crash the UI.

The task detail sheet is intentionally read-only. Editing (including descriptions, quantities, and attachments) and deleting are available from the task row `…` menu; setting time is available both from that menu and by tapping the SVG time icon in the row. The same SVG icon is used for the animation-speed setting.

### 6.4 Search & filters

`TaskFilter` enum:

* `all`
* `active` — non-completed tasks
* `completed`
* `foldersOnly`

Search is lower-cased and matched against names/titles. `setSearchQuery` triggers a `notifyListeners()`, so the UI rebuilds.

---

### 6.5 Obsidian-like descriptions

Description source text remains the durable source of truth. The parser and index are derived in-memory state and are rebuilt after startup, import, sync, and task/folder mutations; do not persist the parsed AST.

Supported source syntax:

* `[[Task title]]` — resolves by exact title.
* `[[Folder/Task title|display label]]` — resolves by root-to-leaf folder path and renders the alias.
* `![[attachment-name.ext]]` — embeds only an attachment belonging to the same description.
* `#tag` and `#nested/tag` — indexed as canonical lower-case tags and exposed through tag navigation.
* `> [!note]`, `tip`, `warning`, `important`, and `quote` — rendered as bounded callouts.
* `^block-id` — parsed as metadata for future block navigation; it is not implicitly clickable.

Resolution rules are deterministic: exact title/path matches win, duplicate titles return an explicit ambiguous result, deleted tasks are excluded, and unresolved links never create or mutate tasks. Search ranks title, folder path, tags, and description in that order and returns at most `kMaxDescriptionSearchResults` results.

Security and limits:

* Descriptions are capped at `kMaxTaskDescriptionLength` (10,000 characters); the parser scans at most 256 references.
* Only `http`/`https` external links are interactive. `javascript:`, `file:`, `data:`, malformed internal schemes, and remote Markdown images remain inert.
* Local embeds must resolve to validated, owned task attachments; missing files render a placeholder and must not crash the UI.
* The editor keeps raw Markdown in `TaskInfoBlock.text`; toolbar and preview transformations never rewrite persisted source.
* UI consumers must keep result lists bounded, preserve semantics/tooltips, and test 320 dp layouts with large text.

The main implementation files are `lib/core/description_document.dart`, `lib/core/description_reference_parser.dart`, `lib/features/tasks/services/description_index.dart`, `lib/features/tasks/screens/knowledge_search_screen.dart`, and `lib/features/tasks/widgets/description_backlinks.dart`.

## 7. Core Services

### 7.1 TaskProvider

[`lib/features/tasks/providers/task_provider.dart`](../lib/features/tasks/providers/task_provider.dart)

Public API you will use most often:

```dart
void addTask(String title, {String? folderId, DateTime? startTime, DateTime? endTime});
void addFolder(String name, {String? parentFolderId, String? iconAsset});
void updateTask(String id, String newTitle);
void updateFolder(String id, String newName, {String? iconAsset});
void removeTask(String id);
void removeFolder(String id);
void toggleTask(String id);
void moveTaskToFolder(String taskId, String? targetFolderId);
void moveFolderToFolder(String folderId, String? targetParentFolderId);
void reorderRootFolders(int oldIndex, int newIndex);
void reorderSubfolders(String parentFolderId, int oldIndex, int newIndex);
void reorderFolderTasks(String folderId, int oldIndex, int newIndex);
void setTaskTime(String id, {DateTime? startTime, DateTime? endTime});
Future<void> linkTaskToCalendar(String id, String calendarId, DateTime date);
Future<void> unlinkTaskFromCalendar(String id);
```

### 7.2 SettingsProvider

[`lib/features/settings/providers/settings_provider.dart`](../lib/features/settings/providers/settings_provider.dart)

Holds all user preferences and exposes `tr(key)` for localized strings. Custom animation speeds/scales are stored as short histories (max 3 entries each) in `_addToCustomHistory`.

### 7.3 CalendarService

[`lib/core/calendar_service.dart`](../lib/core/calendar_service.dart)

Wraps `device_calendar`:

* `requestPermission()` — asks for calendar access.
* `openAppSettings()` — opens app settings after calendar access is denied.
* `getCalendars()` — writable calendars only.
* `createOrUpdateEvent(...)` — creates or updates a native calendar event.
* `deleteEvent(...)` — removes a linked event.

Calendar events are stored on the task as `calendarId` + `calendarEventId`. The streak folder (`system_streak_folder`) hides calendar actions because its contents reset daily.

### 7.4 NotificationService

[`lib/core/notification_service.dart`](../lib/core/notification_service.dart)

Thin wrapper around `flutter_local_notifications`. It schedules daily task-start reminders only for active tasks with a non-zero period, cancels reminders when the period is incomplete or the task is completed/deleted, and exposes a notification action that persists a request to start the task timer. Permission and platform guards are handled by the service; testable ID/payload helpers are covered by `test/notification_service_test.dart`.

### 7.5 HomeWidgetService

[`lib/core/home_widget_service.dart`](../lib/core/home_widget_service.dart)

Debounced updater for Android home screen widgets. Stores:

* `active_tasks`
* `streak`
* `last_folder`
* `widget_enabled`
* `widget_mode`

Call `HomeWidgetService.updateData(provider)` after task changes; call `updateSettings(...)` from settings.

### 7.6 ExportImportService

[`lib/core/export_import_service.dart`](../lib/core/export_import_service.dart)

Portable backup/sync format (`AsaDataSnapshot`):

```json
{
  "version": "1.1.0",
  "exportedAt": 1234567890,
  "tasks": [...],
  "folders": [...]
}
```

Methods:

* `buildSnapshot(provider)`
* `exportAndShare(provider)` — share sheet
* `exportToFile(provider)` — returns file
* `pickImportFile()` — file picker
* `previewImport(...)` — validation + preview
* `importFromBytes(...)` / `importFromSnapshot(...)` — LWW merge
* `buildSyncPayload(...)` — wraps snapshot for P2P sync

Validation checks: extension, size (<10 MB), UTF-8, JSON shape, required keys, sync secret.

### 7.7 SyncService

[`lib/core/sync_service.dart`](../lib/core/sync_service.dart)

Local-network P2P over mDNS + TCP sockets:

* Broadcasts `_asa-sync._tcp` via `bonsoir`.
* Includes a stable `deviceId` in TXT attributes to avoid self-discovery.
* Sends JSON payload length-prefixed (`[4 bytes length][payload]`).
* Receives data, validates sync secret, and merges via `ExportImportService`.
* Incoming TCP frames are length-prefixed, bounded to 10 MB, timeout-protected, and closed after one frame. When a secret is configured, the payload must pass HMAC validation; malformed or unauthenticated frames are rejected.
* On Android, sync requests local-network access only when enabled: `NEARBY_WIFI_DEVICES` on Android 13+ and `ACCESS_FINE_LOCATION` through Android 12. A denial leaves sync disabled; this permission is intentionally not part of the mandatory startup setup.

Lifecycle in `SplashScreen`:

```dart
if (settings.syncEnabled) {
  SyncService.instance.setProvider(tasks);
  SyncService.instance.setDeviceName(settings.syncDeviceName);
  SyncService.instance.setSecret(settings.syncSecret);
  await SyncService.instance.start();
}
```

### 7.8 VersionService

[`lib/core/version_service.dart`](../lib/core/version_service.dart)

Checks GitHub releases for `SabirDzh/Asa`. Prompts at most once every 12 hours, or every 24 hours after the user postpones. The update dialog (`lib/core/update_dialog.dart`) can download the release APK in-app and open the system package installer via `open_filex` on Android (`UpdateChecker.downloadUpdate` / `installUpdate`). Release history is available through `fetchReleaseHistory()` (GitHub `/releases` list with a `SharedPreferences` cache fallback). The displayed app version comes from `VersionService.currentVersion`, which reads the compile-time `--dart-define=APP_VERSION` (defaulting to the `pubspec.yaml` version) so it never drifts.

### 7.9 LoggerService

[`lib/core/logger_service.dart`](../lib/core/logger_service.dart)

Buffered logger with a maximum of 500 entries. The app captures Flutter errors locally and sends diagnostics only after the user taps the report action and confirms the disclosure dialog. Release scripts read only the public HTTPS route from the ignored owner-only `config/private.env` file and automatically pass it to Flutter; no manual `--dart-define=DIAGNOSTICS_ENDPOINT` argument is required. Direct Flutter commands intentionally leave diagnostics disabled. Never put Neon, admin, session, Telegram credentials, or bearer tokens in the Flutter config or build defines.

Before buffering and before submission, registered sync secrets plus common tokens, passwords, email addresses, IP addresses, query-string URLs, and local paths are redacted. Reports include bounded technical logs and safe device metadata only; tasks, descriptions, attachments, backups, clipboard contents, and sync secrets are excluded by contract. A successful response is required before the local buffer is cleared.

The Vercel implementation and deployment instructions live in [`diagnostics-dashboard/`](../diagnostics-dashboard). It uses Neon Postgres, signed httpOnly admin sessions, same-origin checks, bounded payload validation, hashed rate-limit identifiers, login throttling, report deletion, and retention cleanup.

Unhandled Flutter errors are captured by `listenToFlutterErrors()` in `main.dart` and remain local until the user explicitly submits a report.

### 7.10 ThemeSwitcher & theme switching

[`lib/core/theme_switcher.dart`](../lib/core/theme_switcher.dart)

Captures the current screen as an image, inserts an `OverlayEntry`, and cross-fades while the underlying `MaterialApp` rebuilds with the new `ThemeMode`. The overlay uses the same `RepaintBoundary` key located in `_ScaledApp`.

---

## 8. UI/UX Layer

### 8.1 Row / card design system

All list items are designed as “pill” rows:

* `AppTheme.rowHeight = 56`
* `AppTheme.rowPadH = 20`, `rowPadV = 15`
* `AppTheme.pillRadius = 28`
* `AppTheme.rowGap = 10`

`TaskRow` and `FolderRow` both use these constants. Avoid hardcoding sizes; import `AppTheme`.

### 8.2 showInputSheet

[`lib/core/bottom_sheet.dart`](../lib/core/bottom_sheet.dart)

Central helper for creating tasks/folders. Features:

* Leading icon + text field
* Optional paste-from-clipboard button
* Optional folder icon picker (SVG grid)
* Padding auto-adjusts for keyboard (`viewInsets.bottom`)

### 8.3 Task detail & time sheets

* `task_detail_sheet.dart` — read-only task information; it does not mutate tasks.
* `task_card.dart` — task-row `…` menu for editing, setting time, calendar actions, and deletion; tapping the timer icon also opens the time editor.
* `task_time_sheet.dart` — set duration and/or time period using wheel pickers.

### 8.4 Settings UI

`SettingsScreen` uses:

* `SettingGroup` — section with a title.
* `SettingRow` — a tappable row with leading icon, label, and trailing widget (chevron, switch).
* `AvatarSection` — user avatar display/change.

Bottom sheets for theme, language, animation speed, app scale, widget mode, sync, and data management live under `lib/features/settings/widgets/`.

---

## 9. Theming, Scaling & Animations

### 9.1 Theme

[`lib/core/theme.dart`](../lib/core/theme.dart)

* `AppColors` — primary green, light/dark surfaces, backgrounds, text colors.
* `AppTheme` — spacing constants and `ThemeData` builders.
* `ThemeMode` is controlled by `SettingsProvider` and applied in `AsaApp`.

### 9.2 Scaling

[`lib/core/scale_utils.dart`](../lib/core/scale_utils.dart)

* `effectiveAppScale(context, scale)` clamps the user’s scale to an adaptive range based on the shortest screen side.
* `_ScaledApp` wraps the child in a `MediaQuery` with virtual size `screen / scale`, then scales back with `Transform.scale`. This produces a true uniform scale including text.

### 9.3 Animations

* `animationSpeed` is stored as a multiplier and applied through `timeDilation` (global).
* Theme transition has a fixed 500 ms logical duration that `timeDilation` stretches or compresses.
* Checkbox and task entrance/exit animations live in `task_card.dart`.
* FAB hide/show uses `ScrollHideMixin`.

---

## 10. Localization

[`lib/core/app_strings.dart`](../lib/core/app_strings.dart)

* Currently Russian (`ru`) and English (`en`).
* Add new strings to both maps.
* Use `settings.tr(key)` in widgets.

---

## 11. Platform-Specific Notes

### 11.1 Android

* The `home_widget` plugin requires a native `AppWidgetProvider` and XML layouts in `android/app/src/main/`.
* Three Android widgets share `AsaWidgetBaseProvider`: compact, tasks/folder, and stats variants. Each layout uses the same `widget_root`, `widget_streak`, and `widget_active_tasks` IDs.
* The Flutter/native widget data contract is:
  * `streak` — non-negative streak day count.
  * `active_tasks` — non-negative active task count.
  * `last_folder` — optional last viewed folder name; native rendering truncates it safely.
  * `widget_enabled` — visibility state.
  * `widget_mode` — `activeTasks`, `lastFolder`, or legacy `streak`.
* `AsaWidgetBaseProvider` uses Android plurals, safe preference reads, bounded text, and a root TalkBack description. Missing or malformed values fall back to a useful active-task/streak state rather than crashing the launcher.
* Widget metadata declares resize bounds and target cell sizes. Layouts use `match_parent`, one-line ellipsized text, and a minimum resize height that keeps the content readable on compact launchers.
* `HomeWidgetService` debounces writes and coalesces the three provider updates. It publishes the initial state even when values match native defaults and requests a refresh when the app resumes, because launchers may clear native widget state while the process is backgrounded.
* ABI split is configured in `android/app/build.gradle.kts` for `arm64-v8a` release builds.
* Calendar, notification, and local-network discovery permissions are declared in `AndroidManifest.xml`. Local-network permission is requested on demand when sync is enabled.
* App name and launcher icon are managed in the usual Android resources.

### 11.2 iOS/macOS

* `home_widget` and local notifications need appropriate entitlements.
* `device_calendar` uses EventKit on iOS.
* macOS uses the same Flutter framework but may lack notification/calendar parity; test before shipping.

### 11.3 Windows/Linux

* Sync over mDNS works on these platforms.
* Home screen widgets are not supported on desktop.

---

## 12. Build & Run

### 12.1 Local development

```bash
flutter pub get
flutter run
```

### 12.2 Android release signing

Release builds never use the debug signing key. For a distributable APK, provide
signing values through either the ignored `android/key.properties` file or CI
environment variables:

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=...
keyAlias=...
keyPassword=...
```

Equivalent CI variables are `ANDROID_KEYSTORE_PATH`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`.
Do not commit `key.properties`, keystores, or passwords. The repository keeps
those paths ignored in `android/.gitignore`. Without credentials, Gradle emits
an explicit warning and produces an unsigned release artifact that is suitable
only for local inspection, not distribution.

### 12.3 Diagnostics build configuration

Create the local owner-only config once:

```bash
cp config/private.env.example config/private.env
# Set the deployed public endpoint, then verify it is not group/world-readable:
chmod 600 config/private.env
```

The file may contain only `DIAGNOSTICS_ENDPOINT=https://.../api/reports`. It is ignored by Git and is not sourced as shell code; the loader reads that one key, validates HTTPS/no embedded credentials, and rejects missing or weak permissions. This endpoint is public client configuration, not a server secret. Keep Neon, admin passwords, `SESSION_SECRET`, `RATE_LIMIT_SALT`, and bearer tokens exclusively in Vercel environment variables.

### 12.4 Release APK (arm64-v8a only)

```bash
./scripts/build.sh --split
# or, for the release flow:
./scripts/release.sh <version> <build> --no-push
```

Both scripts automatically load and validate `config/private.env`; no manual `--dart-define=DIAGNOSTICS_ENDPOINT` is needed. To intentionally build without diagnostics locally, use `./scripts/build.sh --without-diagnostics`. Direct `flutter build` commands keep diagnostics disabled.

Output: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

### 12.5 Release automation

`./scripts/release.sh <version> <build> [--no-push] [--dry-run]` performs the full
release flow:

1. Bumps `pubspec.yaml` to `<version>+<build>` and updates the `APP_VERSION`
   default in `lib/core/version_service.dart`.
2. Commits the bump, builds the arm64 APK with
   `--dart-define=APP_VERSION=<version>`, and copies the artifact to
   `Asa-<version>+<build>-arm64-v8a.apk`.
3. Tags `v<version>+<build>`, pushes (unless `--no-push`), and creates the GitHub
   release with the APK asset — via the `gh` CLI when available, otherwise via the
   GitHub REST API with `GITHUB_TOKEN`.

In-app updates download the release's arm64 APK and open the system package
installer (`open_filex`).

### 12.6 Run tests

```bash
flutter test
```

The full suite currently passes (`flutter test`, 495 tests), including the widget tests that previously hung after test startup in `folder_detail_screen_test.dart` and `task_folder_popup_menu_test.dart`.

On Android, the app requests notification access at startup when notifications are enabled and synchronizes reminders only after the task provider has loaded. Exact-alarm access is requested from the explicit notification setting; if it is unavailable, scheduling falls back to an inexact alarm. If the start time has already passed today, a daily reminder is scheduled for the next day. A scheduled period such as 22:01–22:02 is the planned one-minute window; the manual elapsed timer is shown as actual time and remains 0:00 until the user starts it.

The repository-wide formatter and analyzer gates pass:

```bash
dart format --output=none --set-exit-if-changed .
dart analyze
```

The ordinary web build currently hits Flutter's icon tree-shaking `IconTreeShakerException`; `flutter build web --no-tree-shake-icons` succeeds as a diagnostic workaround, but this does not close the ordinary web release gate.

---

## 13. Testing

Unit tests are in the [`test/`](../test) directory:

* `task_provider_test.dart`
* `task_model_test.dart`
* `settings_provider_test.dart`
* `settings_screen_test.dart`
* `home_screen_test.dart`
* `folder_detail_screen_test.dart`
* `input_utils_test.dart`
* `image_utils_test.dart`
* `widget_test.dart`

When adding new providers or services, add matching tests and prefer injecting dependencies (e.g., `SettingsProvider` accepts a `deviceNameProvider`).

---

## 14. Conventions & Best Practices

* **Use `AppTheme` and `AppColors` constants**; do not hardcode sizes or colors.
* **Prefer `copyWith` over mutation** for models.
* **Keep provider methods synchronous when possible** and persist afterward.
* **Wrap text input with `textInputFormatter()` / `sanitizeText()`**.
* **Use `context.select` for narrow rebuilds**, but avoid it with frequently-rebuilt lists (identity issue).
* **Add localized strings to `AppStrings`** for both languages.
* **Log errors via `LoggerService`** instead of swallowing exceptions.
* **Do not mutate `_tasks` / `_folders` directly outside `TaskProvider`**. Use exposed methods.

---

## 15. Extending the App

### 15.1 Adding a new setting

1. Add a private field + getter in `SettingsProvider`.
2. Add a setter that persists to `SharedPreferences` and calls `notifyListeners()`.
3. Add UI in `SettingsScreen` (and a bottom sheet if needed).
4. Add localized labels in `AppStrings`.

### 15.2 Adding a new task field

1. Add the field to `TaskItem`, `toJson()`, `fromJson()`, and `copyWith()`.
2. Add provider methods to read/update it if necessary.
3. Update `TaskCard`, `TaskDetailSheet`, and `TaskTimeSheet` as needed.

### 15.3 Adding a new native integration

1. Add the Dart wrapper in `lib/core/xxx_service.dart`.
2. Request permissions through the wrapper and surface toggles in settings.
3. Add platform configuration (manifest/entitlements) and test on real devices.

---

## 16. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Update dialog never shows | `VersionService` rate-limited or GitHub API failed | Check network; review `SharedPreferences` key `update_last_prompted_at` |
| Widget not updating | `HomeWidgetService` debounce or native provider issue | Verify `HomeWidget.saveWidgetData` keys and Android XML |
| Sync sees own device | `deviceId` mismatch or missing TXT record | Ensure `SettingsProvider.ensureSyncDeviceId()` is called before `start()` |
| Calendar action missing | Task is in `system_streak_folder` or permission denied | Check folder ID and runtime permissions; after denial use the explicit **Open settings** action |
| Sync finds no devices | Local-network permission was denied or not requested | Enable sync again and grant Nearby Wi-Fi/Location access; verify both devices are on the same LAN |
| Theme transition lag | High `timeDilation` + image capture | Reduce animation speed in settings or optimize tree depth |

---

## 17. Useful Commands

```bash
# Analyze
flutter analyze

# Check formatting without changing files
dart format --output=none --set-exit-if-changed .

# Check patch whitespace
 git diff --check

# Run tests
flutter test

# Verify Android resources and native widget providers
(cd android && ./gradlew :app:processDebugResources :app:compileDebugKotlin --no-daemon)

# Build debug APK
flutter build apk --debug

# Build release APK (arm64-v8a; signing is required for distribution)
flutter build apk --target-platform android-arm64 --split-per-abi --release

# Build iOS release (requires macOS/Xcode signing setup)
flutter build ios --release
```

---

## 18. Verification and manual platform matrix

The following checks were completed during the standards remediation:

* `dart analyze` — passed with no issues.
* `flutter test` — passed (495 tests).
* Repository-wide `dart format --output=none --set-exit-if-changed .` — passed after the formatting-only commit `3427d11`.
* Android `:app:processDebugResources` and `:app:compileDebugKotlin` — passed.
* Android arm64 release — passed; output is `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (approximately 21.6 MB, ignored build output).
* `flutter pub deps --style=compact` and `flutter pub outdated --no-transitive` — passed; outdated major dependencies were not upgraded during remediation.
* `flutter build web --no-tree-shake-icons` — passed. Ordinary `flutter build web` remains blocked by Flutter icon tree-shaking.

Physical-device verification is still required before release: Android/iOS attachment picking and opening, notification action `start_timer`, home widgets, calendar permissions/events, TalkBack/VoiceOver labels, 1.5x text scale, keyboard/large-description behavior, and LAN discovery/HMAC exchange. iOS/macOS/Linux/Windows release builds were not claimed because their platform toolchains/devices were not part of this verification run.

## 19. Further Reading

* [Flutter Provider docs](https://pub.dev/packages/provider)
* [home_widget](https://pub.dev/packages/home_widget)
* [device_calendar](https://pub.dev/packages/device_calendar)
* [bonsoir](https://pub.dev/packages/bonsoir)
