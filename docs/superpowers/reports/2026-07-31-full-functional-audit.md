# ASA Full Functional Audit Report

**Date:** 2026-07-31
**Branch:** `fix/review-remediation`
**APK under test:** `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
**Initial APK SHA-256:** `b89b228708e853216c11a1b331666f240a3517e4fe47d7a804894bc61fbc994a`
**Initial APK size:** 21.8 MB
**Final APK SHA-256:** `4cf3908df02b8c70e9f88db13daf64828dd5d930a4f7d168d271cd2f2299d84d`
**Final APK size:** 22.6 MB
**Final APK evidence:** APK Signature Scheme v2 verified; one signer; native libraries contain only `lib/arm64-v8a/*`; includes the AES-GCM sync encryption and PBKDF2-600k key derivation.
**Audit baseline commit:** `b62146f`

## Result vocabulary

- **PASS:** behavior observed and assertion/evidence completed.
- **FAIL-fixed:** reproducible defect fixed with regression coverage.
- **BLOCKED:** required external device, permission, platform, or test harness is unavailable; the exact limitation is recorded.
- **NOT APPLICABLE:** feature is intentionally unavailable on the tested platform and its fallback is documented.

## Functional matrix

| Function | Valid cases | Invalid/boundary cases | Cancel/permission cases | Lifecycle/offline cases | Automated evidence | Device evidence | Result | Defect/commit |
|---|---|---|---|---|---|---|---|---|
| Task/folder CRUD, search, filters, ordering | Covered by provider/model tests and deterministic search/filter/reorder regressions | Invalid indices, length limits, cycles and malformed persistence covered | UI cancel/permission paths remain widget/device-blocked | Persistence and coalesced writes covered; device lifecycle remains blocked | Task 2 gate: 66 tests passed; format/analyze/diff passed | Android device not connected | PASS automated core + BLOCKED UI/device evidence | `d6b96d3 test: audit task and folder workflows` |
| Task editor, information blocks, attachments, time, manual timer | Pure/provider contracts and editor flows are covered; detail now renders saved blocks | Quantity/link/file/image bounds and malformed metadata are covered by model/service tests | Draft cancellation and picker UI remain harness-blocked | Timer persistence and planned-vs-actual semantics pass in provider/model tests | Task 3 gate: 72 tests passed; format/analyze/diff passed; editor/detail widget group blocked after 300s | Android device not connected | FAIL-fixed + BLOCKED UI/device evidence | `37f3250 test: audit task editor and timer workflows` |
| Settings, theme, language, scale, notifications, avatar | Provider/service contracts pass; language is wired into MaterialApp locale | Image validation and settings bounds are covered by focused tests | Settings widget flow and native permission/picker paths are harness/device-blocked | Lifecycle/native behavior remains device-blocked | Task 4 gate: 44 tests passed; format/analyze/diff passed; settings widget group blocked after 300s | Android device not connected | FAIL-fixed + BLOCKED UI/device evidence | `2650de9 test: audit settings and lifecycle workflows` |
| Export/import, sync, logging, calendar, external integrations | Pure export/import, HMAC, logger, and attachment contracts pass; sync payloads now AES-256-GCM encrypted | Malformed JSON/UTF-8/lists, size limits, tampering, frame bounds, unsafe links, wrong secret, and encrypted-envelope boundaries covered | Picker cancellation, share result, calendar permission and external handlers are native/device-blocked | Sync lifecycle pure tests pass; LAN and app-kill scenarios remain device-blocked | Task 5 gate: 53 tests passed; encrypted-envelope gate: 43 tests passed; format/analyze/diff passed | Android device not connected | FAIL-fixed + BLOCKED native/device evidence | `30d8d26 test: audit data and integration workflows`, `ad7fa05 fix: encrypt LAN sync payload with AES-GCM` |
| Android notifications, widgets, calendar, picker, APK install | APK artifact and native declarations verified; runtime install/launch not possible | Device negative paths not executable | Runtime permissions, exact alarms, picker/calendar/share outcomes blocked | Background/resume, widget refresh, restart persistence and LAN sync blocked | Native Gradle gate passed; APK v2 signature verified | `adb devices -l`: no devices; only macOS/Chrome in `flutter devices` | BLOCKED runtime / PASS native compile | `e47dd38 test: verify Android functional matrix` |

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
- Final combined pure/service gate: **PASS**, 155 tests passed, 0 failures, exit code 0.
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

## Task 5: Data management, export/import, sync, logging, calendar, and external integrations evidence

- Pure export/import/sync/logger/attachment gate: **PASS** — 53 tests passed, exit code 0.
- Task-family formatter check: **PASS** — `dart format --output=none --set-exit-if-changed` returned exit code 0.
- Task-family analyzer check: **PASS** — no issues found.
- `git diff --check`: **PASS**.
- Export/import evidence covers snapshots with information-block metadata, LWW newer/older merges, soft-delete propagation, reserved streak-folder rejection, malformed JSON/UTF-8/object/list validation, file-size and extension boundaries, cancellation contracts, and HMAC envelope validation.
- Sync evidence covers secret trimming, peer self-filtering, concurrent startup, loopback send/receive, oversized frame rejection, and wrong-secret rejection.
- Logger evidence covers eager redaction of message/error/stack trace, secret rotation retention, and bounded fatal-error buffering.
- Attachment evidence covers safe HTTP(S) links, bounded binary storage, image signatures, basename sanitization, missing-file handling, and path boundary rejection.
- Native share sheet, file picker delivery, calendar permission/event CRUD, and external URL/file handlers were not claimed as passing because no Android device/native integration run was available.
- Security limitation recorded: HMAC authenticates sync payloads but does not encrypt task data on the local TCP transport. This remains an unresolved confidentiality risk and is not silently presented as end-to-end secure sync.

| Scenario | Result | Evidence |
|---|---|---|
| Export/import validation and merge semantics | PASS | Focused export/import tests |
| HMAC sync envelope and bounded TCP frame handling | PASS | Focused sync tests |
| Logger redaction and bounded buffer | PASS | Focused logger tests |
| Native picker/share/calendar/external handlers | BLOCKED | No Android device/native runner |
| Sync confidentiality | UNRESOLVED RISK | Current HMAC design authenticates but does not encrypt payload |

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

## Task 7: Final independent review, release gates, and final APK evidence

- Independent review of the audit range from `b62146f` through `cc0353d` found no blocking data-loss, secret-handling, or scope-drift issue. Follow-up review of the sync-encryption change (`ad7fa05`) and the PBKDF2 cache fix confirmed no blocking issues; the cache now also invalidates when the test iteration override changes.
- `git diff --check b62146f HEAD` — **PASS**.
- `dart format --output=none --set-exit-if-changed .` — **PASS**; 71 files, 0 changes.
- `dart analyze` — **PASS**; `No issues found!`.
- Pure/service gate — **PASS**; 157 tests passed, 0 failures (includes encrypted-envelope, sync, logger, attachment, image, notification, provider, and model tests).
- Widget gate — **PASS** (previously BLOCKED by the hang); all six screen/smoke files now complete: 24 tests passed, 0 failures, in under 3 seconds.
- Android native gate — **PASS**; `processDebugResources` and `compileDebugKotlin` completed with `BUILD SUCCESSFUL` (recorded earlier).
- Final build — **PASS**: `flutter build apk --target-platform android-arm64 --split-per-abi --release` produced `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (22.6 MB).
- Final APK verification — **PASS**: v2 signature verified; SHA-256 `4cf3908df02b8c70e9f88db13daf64828dd5d930a4f7d168d271cd2f2299d84d`; ZIP inspection found only `lib/arm64-v8a/` native libraries.
- Device runtime — **PARTIAL**: install/launch/engine/render verified on `ZPS46P4TCUAMCA7D`; interactive journeys blocked by Xiaomi `INJECT_EVENTS` restriction (documented in the device section).

| Final gate | Result | Evidence |
|---|---|---|
| Independent audit review | PASS with documented risks | Review of audit range `b62146f..cc0353d` + follow-up encryption/cache reviews |
| Static checks | PASS | diff-check, format, analyzer |
| Pure/service tests | PASS | 157 tests, 0 failures |
| Widget tests | PASS | 24 tests, 0 failures (hang fixed) |
| Android native compile | PASS | Gradle resource/Kotlin gate |
| Final arm64 APK | PASS | v2 signature, SHA-256 `4cf3908d…`, arm64-only native libs |
| Device install/launch | PARTIAL | Installed/launched/rendered; journeys BLOCKED by device input-injection restriction |

## Android device evidence

Task 6 was partially executed against a real device on 2026-08-01.

- `adb devices -l` — **PASS**: `ZPS46P4TCUAMCA7D` (Xiaomi duchamp_global, model 2311DRK48G), state `device`.
- Fresh APK install — **PASS**: `adb -s ZPS46P4TCUAMCA7D install -r` returned `Success`.
- Cold start — **PASS**: `am start -n com.example.asa/.MainActivity` returned `Starting: Intent ...`; the app reached foreground focus (`mCurrentFocus=com.example.asa/com.example.asa.MainActivity`) and `pidof com.example.asa` reported a live pid.
- Flutter engine — **PASS**: logcat shows `libflutter.so` loaded and `Using the Impeller rendering backend (Vulkan)`; no `FATAL`/`E/flutter`/`AndroidRuntime` exception for `com.example.asa`.
- Package state — **PASS**: `versionName=1.1.0`, `versionCode=2002`, `minSdk=24`, `targetSdk=36`. Declared permissions: `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, three exported widget receivers, `RECEIVE_BOOT_COMPLETED`, `FOREGROUND_SERVICE`. Runtime grants observed: `INTERNET`/`VIBRATE`/`WAKE_LOCK` granted; `POST_NOTIFICATIONS` and `READ/WRITE_CALENDAR` currently `granted=false` (user consent pending); `SCHEDULE_EXACT_ALARM` `appops` at `default`.
- UI automation — **BLOCKED**: the Xiaomi build denies shell `input` event injection (`SecurityException: ... INJECT_EVENTS permission`), so automated tap/swipe journeys cannot run via ADB. The home screen rendered (screenshot captured, app package present with 20 UI nodes), but full journey automation requires the device's "USB debugging (Security settings)" option to be enabled.
- The `FATAL EXCEPTION: main` line in logcat belongs to `com.android.shell` (pid 31540) from the diagnostic `svc power stayon true` command (`WRITE_SETTINGS` denied), not to `com.example.asa`.
- The final APK was rebuilt after the sync-encryption and PBKDF2 changes; its current verified SHA-256 is `4cf3908df02b8c70e9f88db13daf64828dd5d930a4f7d168d271cd2f2299d84d`, size 22.6 MB.

Still blocked (require interactive consent or the Xiaomi security-settings mode):

- Runtime notification permission grant and delivery timing of scheduled notifications and `start_timer` action.
- Home-screen widget rendering and refresh.
- Calendar permission and event create/update/delete.
- Native image/file picker, avatar picker, and attachment opening.
- TalkBack and large-text verification.
- LAN/mDNS sync between physical devices.

## Fixed defects

- **Task 3:** `task_detail_sheet.dart` omitted persisted quantity/description blocks and attachments. The read-only detail view now renders them through safe, validated attachment actions; regression coverage was added in `test/task_folder_popup_menu_test.dart`. Task 3 audit commit: `37f3250 test: audit task editor and timer workflows`.
- **Task 4:** `SettingsProvider.languageCode` was not passed to `MaterialApp`, leaving built-in Flutter widgets without the selected app locale. Added `flutter_localizations`, supported `ru`/`en`, and standard Material localization delegates. Task 4 audit commit: `2650de9 test: audit settings and lifecycle workflows`.
- **Task 5:** Sync payload confidentiality. Sync is now AES-256-GCM encrypted with a PBKDF2-HMAC-SHA256 (600k) derived key, cached per secret and invalidated when the test iteration override changes; wrong-secret maps to `error_invalid_secret`, legacy HMAC envelopes still import. Commit: `ad7fa05 fix: encrypt LAN sync payload with AES-GCM`.
- **Task 6:** Widget-test hang. The `home_widget` platform channel was not mocked in screen tests, so `resetForTests()` awaited an in-flight platform call forever. A channel mock now installs in every screen test; the ListTile ink regression surfaced after the hang was fixed was corrected with a transparent `Material` wrapper. Commits: `98f98a6`, `91e0879`.

## Resolved risks and blocked scenarios

Resolved since the original report:

- **Sync confidentiality** — RESOLVED: LAN sync payloads with a shared secret are now encrypted with AES-256-GCM (key derived via PBKDF2-HMAC-SHA256 at the OWASP-recommended 600,000 iterations, cached per secret). Wrong-secret import maps to `error_invalid_secret`; legacy HMAC envelopes remain accepted for backward compatibility. Commit: `ad7fa05 fix: encrypt LAN sync payload with AES-GCM`.
- **Widget-test hang** — RESOLVED: the hang was caused by unmocked `home_widget` platform calls leaving `_updateInFlight` pending forever while `resetForTests()` awaited it. Screen tests now install a `home_widget` channel mock (`test/home_widget_channel_mock.dart`), and all five previously hanging screen-test files plus the smoke test complete: final widget gate **24 tests passed**. Commits: `98f98a6 test: mock home widget channel in screen tests`, `91e0879 fix: surface task editor chooser tile ink effects` (ListTile ink regression surfaced once the hang was fixed), plus `f959f22` (resetForTests awaiting in-flight updates) from earlier work.
- **Real-device runtime** — PARTIAL: the APK installs, launches, renders (Impeller/Vulkan), and stays alive on the connected Xiaomi device with no application crash. Interactive journeys remain **BLOCKED** by the Xiaomi `INJECT_EVENTS` restriction on ADB input injection; enabling "USB debugging (Security settings)" on the device would unblock them.

Still blocked:

- Notification permission grant, exact-alarm behavior, delivery timing, and `start_timer` action on-device (permission currently `granted=false`; `SCHEDULE_EXACT_ALARM` at `default`).
- Home-screen widget rendering/refresh, calendar events, picker/share, avatar, TalkBack/large-text, and LAN sync between physical devices.
- Exact-alarm denial may cause Android notification fallback to be inexact; this must be measured on-device with the security-settings mode enabled.
