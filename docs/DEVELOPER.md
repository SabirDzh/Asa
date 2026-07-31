# ASA — Developer Documentation

> **Audience:** engineers joining the project, maintainers, and anyone who wants to extend the app.  
> **Last updated:** 2026-07-29  
> **Project:** [`pubspec.yaml`](../pubspec.yaml)

---

## 1. Overview

ASA is a cross-platform Flutter task manager. It supports folders, drag-and-drop reordering, time tracking, calendar integration, device-to-device sync, export/import, home screen widgets, and adaptive UI scaling. The app targets Android, iOS, Windows, macOS, and Linux from a single codebase.

Key product decisions you should know before reading the code:

* **Offline-first.** All task/folder data lives in `SharedPreferences` as JSON. Sync/export are optional add-ons.
* **Soft-delete.** Deleting a task or folder sets `isDeleted = true`; nothing is truly removed from the local list.
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
│   ├── logger_service.dart            # Buffered logging + Telegram reporter
│   ├── notification_service.dart      # Local notifications wrapper
│   ├── responsive_center.dart         # Large-screen layout wrapper
│   ├── scale_utils.dart               # Adaptive UI scale limits
│   ├── scroll_hide_mixin.dart         # Scroll-aware FAB hide/show
│   ├── sync_service.dart              # mDNS/TCP P2P sync engine
│   ├── theme.dart                     # Colors, theme data, spacing constants
│   ├── theme_switcher.dart          # Animated theme transition overlay
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
* Persist happens in `_saveToPrefs()` after every mutating operation. If you add bulk operations, consider batching or debouncing writes (currently a known improvement area).
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

* `TaskItem` — id, title, `isCompleted`, `folderId`, `dueDate`, `startTime`, `endTime`, `expectedDuration` (minutes), calendar IDs, timestamps, `isDeleted`.
* `FolderItem` — id, name, `isSystemStreak`, `parentFolderId`, `iconAsset`, timestamps, `isDeleted`.
* Both classes have `toJson()` / `fromJson()` and `copyWith(...)`.  
  `copyWith` uses `Object?` sentinel values to distinguish “no change” from `null`.

### 6.2 Persistence

* `TaskProvider._saveToPrefs()` encodes `_tasks` and `_folders` as JSON strings in `SharedPreferences`.
* Keys: `saved_tasks`, `saved_folders`.
* Settings are persisted per-field under their own keys (see `SettingsProvider`).

### 6.3 Search & filters

`TaskFilter` enum:

* `all`
* `active` — non-completed tasks
* `completed`
* `foldersOnly`

Search is lower-cased and matched against names/titles. `setSearchQuery` triggers a `notifyListeners()`, so the UI rebuilds.

---

## 7. Core Services

### 7.1 TaskProvider

[`lib/features/tasks/providers/task_provider.dart`](../lib/features/tasks/providers/task_provider.dart)

Public API you will use most often:

```dart
void addTask(String title, {String? folderId, DateTime? startTime, DateTime? endTime, int? expectedDuration});
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
void setTaskTime(String id, {DateTime? startTime, DateTime? endTime, int? expectedDuration});
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
* `getCalendars()` — writable calendars only.
* `createOrUpdateEvent(...)` — creates or updates a native calendar event.
* `deleteEvent(...)` — removes a linked event.

Calendar events are stored on the task as `calendarId` + `calendarEventId`. The streak folder (`system_streak_folder`) hides calendar actions because its contents reset daily.

### 7.4 NotificationService

[`lib/core/notification_service.dart`](../lib/core/notification_service.dart)

Thin wrapper around `flutter_local_notifications`. Currently shows a one-time test notification and supports toggling notifications on/off in settings. Future reminders would extend this service.

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

[`lib/core/sync_service.dart`](../lib/core/sync_service_service.dart)

Local-network P2P over mDNS + TCP sockets:

* Broadcasts `_asa-sync._tcp` via `bonsoir`.
* Includes a stable `deviceId` in TXT attributes to avoid self-discovery.
* Sends JSON payload length-prefixed (`[4 bytes length][payload]`).
* Receives data, validates sync secret, and merges via `ExportImportService`.

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

Checks GitHub releases for `SabirDzh/Asa`. Prompts at most once every 12 hours, or every 24 hours after the user postpones.

### 7.9 LoggerService

[`lib/core/logger_service.dart`](../lib/core/logger_service.dart)

Buffered logger. Configured at compile time with `--dart-define=TELEGRAM_BOT_TOKEN=... --dart-define=TELEGRAM_CHAT_ID=...`. If not configured, logs only go to the console and an in-memory buffer. Maximum buffer size is 500 entries.

Unhandled Flutter errors are caught by `listenToFlutterErrors()` in `main.dart`.

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

* `task_detail_sheet.dart` — read-only details + quick actions (edit, time, calendar, delete).
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
* Calendar and notification permissions are declared in `AndroidManifest.xml`.
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

### 12.3 Release APK (arm64-v8a only)

```bash
flutter build apk --target-platform android-arm64 --split-per-abi --release
```

Output: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

### 12.3 Run tests

```bash
flutter test
```

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
| Calendar action missing | Task is in `system_streak_folder` or permission denied | Check folder ID and runtime permissions |
| Theme transition lag | High `timeDilation` + image capture | Reduce animation speed in settings or optimize tree depth |

---

## 17. Useful Commands

```bash
# Analyze
flutter analyze

# Format all Dart files
dart format .

# Run tests
flutter test

# Build release APK (arm64-v8a)
flutter build apk --target-platform android-arm64 --split-per-abi --release

# Build iOS release
flutter build ios --release
```

---

## 18. Further Reading

* [Flutter Provider docs](https://pub.dev/packages/provider)
* [home_widget](https://pub.dev/packages/home_widget)
* [device_calendar](https://pub.dev/packages/device_calendar)
* [bonsoir](https://pub.dev/packages/bonsoir)
