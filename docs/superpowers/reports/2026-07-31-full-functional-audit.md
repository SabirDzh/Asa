# ASA Full Functional Audit Report

**Date:** 2026-07-31
**Branch:** `fix/review-remediation`
**APK under test:** `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
**Initial APK SHA-256:** `b89b228708e853216c11a1b331666f240a3517e4fe47d7a804894bc61fbc994a`
**Initial APK size:** 21.8 MB
**Initial APK evidence:** APK Signature Scheme v2 verified; native libraries contain only `arm64-v8a`.
**Audit baseline commit:** `b62146f`

## Result vocabulary

- **PASS:** behavior observed and assertion/evidence completed.
- **FAIL-fixed:** reproducible defect fixed with regression coverage.
- **BLOCKED:** required external device, permission, platform, or test harness is unavailable; the exact limitation is recorded.
- **NOT APPLICABLE:** feature is intentionally unavailable on the tested platform and its fallback is documented.

## Functional matrix

| Function | Valid cases | Invalid/boundary cases | Cancel/permission cases | Lifecycle/offline cases | Automated evidence | Device evidence | Result | Defect/commit |
|---|---|---|---|---|---|---|---|---|
| Task/folder CRUD, search, filters, ordering | Covered by existing provider/model tests; detailed audit is Task 2 | Covered in existing provider/model tests; detailed audit is Task 2 | Detailed audit is Task 2 | Detailed audit is Task 2 | Baseline group passed: 153 tests | Android device not connected | PARTIAL — Task 2 pending | — |
| Task editor, information blocks, attachments, time, manual timer | Pure/provider contracts and editor flows are covered; detail now renders saved blocks | Quantity/link/file/image bounds and malformed metadata are covered by model/service tests | Draft cancellation and picker UI remain harness-blocked | Timer persistence and planned-vs-actual semantics pass in provider/model tests | Task 3 gate: 72 tests passed; format/analyze/diff passed; editor/detail widget group blocked after 300s | Android device not connected | FAIL-fixed + BLOCKED UI/device evidence | `test: audit task editor and timer workflows` |
| Settings, theme, language, scale, notifications, avatar | Provider/service contracts pass; language is wired into MaterialApp locale | Image validation and settings bounds are covered by focused tests | Settings widget flow and native permission/picker paths are harness/device-blocked | Lifecycle/native behavior remains device-blocked | Task 4 gate: 44 tests passed; format/analyze/diff passed; settings widget group blocked after 300s | Android device not connected | FAIL-fixed + BLOCKED UI/device evidence | `test: audit settings and lifecycle workflows` |
| Export/import, sync, logging, calendar, external integrations | Existing service tests present; detailed audit is Task 5 | Existing service tests present; detailed audit is Task 5 | Detailed audit is Task 5 | Detailed audit is Task 5 | Baseline group passed | Android device not connected | PARTIAL — Task 5 pending | — |
| Android notifications, widgets, calendar, picker, APK install | Not run | Not run | Not run | Not run | Native device evidence pending | `adb devices -l`: no devices | BLOCKED | — |

## Automated command evidence

### Repository baseline

- Branch: `fix/review-remediation`.
- Baseline commit: `b62146f fix: clarify task timing and notification flow`.
- `dart format --output=none --set-exit-if-changed .` — **PASS**; 70 files checked, 0 changed.
- `dart analyze` — **PASS**; `No issues found!`.
- `flutter pub deps --style=compact` — **PASS**; project `asa 1.1.0+2`, Flutter 3.44.8, Dart 3.12.2.
- `adb devices -l` — **BLOCKED** for device verification; no Android devices connected.
- `flutter devices` — macOS desktop and Chrome web available; no Android device.

### Isolated test groups

- Command: `flutter test --no-pub test/input_utils_test.dart test/task_model_test.dart test/task_provider_test.dart test/settings_provider_test.dart test/export_import_service_test.dart test/sync_service_test.dart test/notification_service_test.dart test/image_utils_test.dart test/task_attachment_service_test.dart test/logger_service_test.dart test/home_widget_service_test.dart -r compact`
- Result: **PASS**, 153 tests passed, exit code 0.
- Command: `perl -e 'alarm 300; exec @ARGV' -- flutter test --no-pub test/task_editor_sheet_test.dart -r compact`
- Result: **BLOCKED**, timed out after 300 seconds, exit code 142 (`Alarm clock`).
- Command: `perl -e 'alarm 300; exec @ARGV' -- flutter test --no-pub test/task_folder_popup_menu_test.dart -r compact`
- Result: **BLOCKED**, timed out after 300 seconds, exit code 142 (`Alarm clock`).

The widget-test timeouts are not reported as passes and do not invalidate the independent 153-test result.

## Task 2: Task and folder workflow evidence

- Provider/model/input focused gate: **PASS** — 66 tests passed, exit code 0.
- `dart format --output=none --set-exit-if-changed test/task_provider_test.dart` — **PASS**.
- `dart analyze test/task_provider_test.dart lib/features/tasks/providers/task_provider.dart` — **PASS**; no issues found.
- `git diff --check` — **PASS**.
- Added deterministic regression coverage for composed task search/filter behavior, including `foldersOnly`, and invalid task/folder reorder operations preserving state.
- Existing coverage confirmed CRUD, nested-folder cycle protection, streak-folder protection, soft-delete cascades, persistence/reload, timer state, and malformed persisted records.
- No reproducible production defect was found in this task; no production source change was needed.
- HomeScreen widget test `opens create folder sheet on FAB tap` — **BLOCKED**, timed out after 300 seconds with exit code 142. This is recorded as harness evidence, not a product pass/fail.

| Function | Valid cases | Invalid/boundary cases | Cancel/permission cases | Lifecycle/offline cases | Automated evidence | Device evidence | Result | Defect/commit |
|---|---|---|---|---|---|---|---|---|
| Task/folder CRUD, search, filters, ordering | CRUD, nested folders, movement, filters/search, soft-delete, streak protection | Length limits, invalid indices, cycles, malformed persistence | UI cancel/permission cases pending widget/device audit | Persistence and coalesced writes passed in existing tests | 66 Task 2 tests passed | Android unavailable | PASS for automated core; UI/device checks pending | `test: audit task and folder workflows` |

## Task 4: Settings, theme, language, scale, notifications, avatar, and lifecycle evidence

- Settings/provider/service gate: **PASS** — 44 tests passed, exit code 0.
- Changed-file formatter check: **PASS** — `dart format --output=none --set-exit-if-changed lib/main.dart` returned exit code 0.
- Changed-file analyzer check: **PASS** — `dart analyze lib/main.dart` reported `No issues found!`.
- `git diff --check`: **PASS**.
- Theme, language provider state, custom animation-speed history, avatar-path serialization, stable sync device ID, image signatures/size limits, and notification scheduling helpers are covered by focused tests.
- Reproducible defect fixed: `SettingsProvider.languageCode` was not connected to the root `MaterialApp`; the app now supplies `locale`, supported `ru`/`en` locales, and `GlobalMaterialLocalizations.delegates`, so built-in Flutter widgets follow the selected language.
- `flutter pub get` completed successfully after adding the Flutter SDK `flutter_localizations` dependency; `pubspec.lock` was updated accordingly.
- `settings_screen_test.dart`: **BLOCKED**, timed out after 300 seconds with exit code 142. This prevents claiming full widget-level settings/language/large-text evidence.
- Android permission, exact-alarm, native picker, avatar compression, widget, and lifecycle scenarios remain **BLOCKED** until a physical Android device is connected.

| Scenario | Result | Evidence |
|---|---|---|
| Settings/provider/image/notification contracts | PASS | 44 focused tests |
| Root MaterialApp locale integration | FAIL-fixed; static validation PASS | `lib/main.dart`, analyzer, pub get |
| Settings widget interactions and large-text behavior | BLOCKED | `settings_screen_test.dart` timeout after 300s |
| Native permissions, avatar picker/compression, lifecycle | BLOCKED | No Android device |

## Task 3: Task editor, information blocks, attachments, time, and manual timer evidence

- Pure/model/provider/attachment/notification gate: **PASS** — 72 tests passed, exit code 0.
- Changed-file formatter check: **PASS** — `dart format --output=none --set-exit-if-changed` returned exit code 0.
- Changed-file analyzer check: **PASS** — `No issues found!`.
- `git diff --check`: **PASS**.
- Quantity and description information blocks round-trip through `TaskItem` JSON; malformed blocks and malformed attachments are skipped without discarding valid data.
- Attachment boundaries are covered: HTTP(S)-only links, unsafe schemes rejected, image signatures checked, byte and per-task count limits enforced, path traversal names reduced to safe basenames, missing/out-of-scope local files rejected.
- Planned duration and actual timer remain separate: a 22:01–22:02 period is one minute planned duration while an untouched manual timer remains 0:00; overnight periods are supported.
- Reproducible defect fixed: read-only task detail previously omitted saved information blocks. It now renders quantity values, description text, and safe attachment chips. Opening a chip uses the existing validated attachment service; the sheet exposes no edit, time, or delete controls.
- Regression coverage was added to `test/task_folder_popup_menu_test.dart` for quantity/description/attachment visibility and read-only restrictions.
- `task_editor_sheet.dart` widget test and `task_folder_popup_menu_test.dart` widget test: **BLOCKED**, each timed out after 300 seconds with exit code 142. Therefore end-to-end UI assertions are not claimed as passing despite static verification and the added regression test.

| Scenario | Result | Evidence |
|---|---|---|
| Editor/model/provider valid and invalid contracts | PASS | 72 focused tests |
| Attachment validation and unavailable-file safety | PASS | `test/task_attachment_service_test.dart`, model tests |
| Time period and manual timer semantics | PASS | `test/task_model_test.dart`, `test/task_provider_test.dart`, `test/notification_service_test.dart` |
| Detail information-block rendering | FAIL-fixed; UI execution BLOCKED | Source fix + regression test; widget harness timeout |
| Detail read-only restrictions | FAIL-fixed; UI execution BLOCKED | Existing menu assertions + source review; widget harness timeout |

## Android device evidence

No Android device was connected during Task 1. The following real-device scenarios remain blocked until an Android device is available:

- APK install and launch through ADB.
- Runtime notification permission and exact-alarm behavior.
- Delivery timing of scheduled notifications and `start_timer` action.
- Home-screen widget rendering and refresh.
- Calendar permission, event creation/update/deletion.
- Native image/file picker and attachment opening.
- Avatar picker/compression on Android.
- TalkBack and large-text verification.
- LAN/mDNS sync between physical devices.

## Fixed defects

- **Task 3:** `task_detail_sheet.dart` omitted persisted quantity/description blocks and attachments. The read-only detail view now renders them through safe, validated attachment actions; regression coverage was added in `test/task_folder_popup_menu_test.dart`. Task 3 audit commit: `37f3250 test: audit task editor and timer workflows`.
- **Task 4:** `SettingsProvider.languageCode` was not passed to `MaterialApp`, leaving built-in Flutter widgets without the selected app locale. Added `flutter_localizations`, supported `ru`/`en`, and standard Material localization delegates. Task 4 audit commit: `2650de9 test: audit settings and lifecycle workflows`.

## Blocked scenarios and unresolved risks

- Android real-device matrix is blocked by the absence of an ADB-connected Android device.
- `task_editor_sheet_test.dart` and `task_folder_popup_menu_test.dart` each hang after test startup in the current widget harness and require separate harness diagnosis; Task 3's new detail regression is therefore not executable evidence yet.
- Passing unit/service tests do not prove native notification delivery, calendar operations, widget rendering, picker behavior, or external URL/file opening.
- Exact-alarm denial may cause Android notification fallback to be inexact; this must be measured on-device rather than inferred from unit tests.
