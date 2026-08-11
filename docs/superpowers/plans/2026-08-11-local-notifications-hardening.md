# Local Notifications Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make scheduled local notifications reliable across stale task dates, background action callbacks, and Android device reboot/package replacement.

**Architecture:** Keep the existing `NotificationService` API and task synchronization flow. Correct daily scheduling by projecting the stored time-of-day onto the current local date, refresh shared-preferences state before consuming background actions, and declare the notification plugin's Android receivers so the OS can deliver scheduled alarms after reboot.

**Tech Stack:** Flutter/Dart, `flutter_local_notifications` 17.2.x, timezone, SharedPreferences, Android Manifest.

## Global Constraints

- Do not replace the existing notification plugin or persistence architecture.
- Preserve the existing exact-alarm fallback to inexact alarms.
- Preserve custom `BootReceiver` behavior for app-level boot bookkeeping.
- Add regression coverage for every corrected Dart behavior.

---

### Task 1: Correct scheduled reminder date projection

**Files:**
- Modify: `lib/core/notification_service.dart`
- Test: `test/notification_service_test.dart`

Project a stored task time onto today before deciding whether it has passed; only move it to tomorrow when today's occurrence is not future.

### Task 2: Refresh background action state

**Files:**
- Modify: `lib/core/notification_service.dart`
- Test: `test/notification_service_test.dart`

Reload the shared-preferences cache before reading a timer action written by the notification background isolate, then consume it exactly once.

### Task 3: Register Android notification receivers

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`

Declare the plugin's scheduled notification, boot-reschedule, and action receivers with `exported="false"`, preserving the existing boot permission and custom receiver.

### Task 4: Verify the notification path

Run:
- `flutter test test/notification_service_test.dart`
- `flutter test`
- `dart analyze`
- `(cd android && ./gradlew :app:processDebugResources :app:compileDebugKotlin --no-daemon)`
- `git diff --check`

Review the diff for unintended changes and report that physical-device delivery still requires an Android/iOS device test.
