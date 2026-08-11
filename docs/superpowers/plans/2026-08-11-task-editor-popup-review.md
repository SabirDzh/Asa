# Task Editor Popup Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task with review checkpoints.

**Goal:** Make attachment menus remain aligned with their selector while the keyboard opens/closes, keep their width equal to the selector, and preserve reliable `@` attachment suggestions.

**Architecture:** Keep the existing `showAnchoredPopupMenu` route and the current `TaskEditorSheet` composition. Make the popup route derive its current anchor rectangle on every layout rebuild, use keyboard insets only for the available viewport boundary, and capture the selector width at opening time for the width-matching mode. The attachment selector will wait for the keyboard inset to reach zero with a bounded time limit before pushing the popup route; mention suggestions remain inline in the editor and receive focused regression coverage.

**Tech Stack:** Flutter/Dart, `PopupRoute`, `CustomSingleChildLayout`, `MediaQuery.viewInsets`, Flutter widget tests.

## Global Constraints

- Do not replace the existing popup route or introduce a new dependency.
- Preserve the default width and behavior of task/folder popup menus; width matching is opt-in for the attachment selector.
- Do not alter the existing attachment validation or Markdown safety behavior.
- Keep unrelated notification, permissions, and update changes out of all commits.
- Every completed task must pass its stated verification before its own commit.

---

### Task 1: Correct popup viewport and dynamic anchor layout

**Files:**
- Modify: `lib/core/anchored_popup_menu.dart`
- Test: `test/anchored_popup_menu_test.dart`

**Interfaces:**
- Preserve `showAnchoredPopupMenu<T>(...)` and all existing call sites.
- Preserve `matchAnchorWidth` as an opt-in parameter.

- [ ] **Step 1: Add a regression test for a moving anchor**

Extend the popup test app with a state-controlled bottom inset/anchor offset. Open the popup, move the anchor by changing the inset, pump the route, and assert that the popup remains six logical pixels from the current anchor edge.

The assertion must use `tester.getRect` for both `anchorKey` and `menuKey` and accept either below or above placement while requiring the nearest edge gap to equal `6`.

- [ ] **Step 2: Run the focused popup tests and confirm the regression is observable**

Run:

```bash
flutter test test/anchored_popup_menu_test.dart
```

Expected: the new moving-anchor test fails before the layout fix if the route does not rebuild against the current anchor rectangle; existing placement tests continue to identify the expected six-pixel gap.

- [ ] **Step 3: Remove duplicate keyboard-inset accounting**

In `_AnchoredPopupMenuLayout.getConstraintsForChild`, deflate constraints by safe `viewPadding` only. Keep `viewInsets.bottom` in `getPositionForChild` as the single source for the usable lower viewport boundary. Retain `viewInsets` in `shouldRelayout` so the route recomputes when the keyboard changes.

Keep the lifecycle guard around the retained anchor context:

```dart
final anchor =
    anchorContext.mounted
        ? anchorContext.findRenderObject() as RenderBox?
        : null;
```

Only call `localToGlobal` when both the anchor and overlay render boxes are attached.

- [ ] **Step 4: Run the focused popup tests and analyzer**

Run:

```bash
flutter test test/anchored_popup_menu_test.dart test/attachment_action_menu_test.dart
dart analyze
```

Expected: all focused tests pass and analyzer reports `No issues found`.

- [ ] **Step 5: Commit the completed task**

```bash
git add lib/core/anchored_popup_menu.dart test/anchored_popup_menu_test.dart
git commit -m "fix(ui): keep anchored menus aligned through keyboard insets"
```

---

### Task 2: Make attachment-menu keyboard dismissal bounded and deterministic

**Files:**
- Modify: `lib/features/tasks/widgets/attachment_action_menu.dart`
- Test: `test/attachment_action_menu_test.dart`

**Interfaces:**
- Preserve `AttachmentActionMenu` public constructor and callbacks.
- Preserve `onActionChanged` behavior and the existing three attachment actions.

- [ ] **Step 1: Add a test that opens the selector while an inset is present**

Use a stateful test host with a non-zero `MediaQuery.viewInsets.bottom`, tap the selector, pump the dismissal frames, and assert that the dropdown width equals the selector width and that the menu is not positioned using the stale pre-dismissal location.

- [ ] **Step 2: Replace frame-count-only waiting with a bounded inset wait**

Update `_waitForKeyboardToClose` to poll `MediaQuery.viewInsetsOf(context).bottom` until it reaches zero, yielding at `WidgetsBinding.instance.endOfFrame`, with a hard deadline of 500 milliseconds. Return early if the context is unmounted. Do not block opening the menu indefinitely when a platform does not report inset completion.

- [ ] **Step 3: Run focused attachment-menu tests and analyzer**

Run:

```bash
flutter test test/attachment_action_menu_test.dart test/task_editor_sheet_test.dart
dart analyze
```

Expected: all focused tests pass and analyzer reports `No issues found`.

- [ ] **Step 4: Commit the completed task**

```bash
git add lib/features/tasks/widgets/attachment_action_menu.dart test/attachment_action_menu_test.dart
git commit -m "fix(editor): wait for keyboard dismissal before attachment menu"
```

---

### Task 3: Verify `@` attachment suggestions and list interaction polish

**Files:**
- Modify: `lib/features/tasks/widgets/attachment_mention_overlay.dart`
- Test: `test/task_editor_sheet_test.dart`

**Interfaces:**
- Preserve `AttachmentMentionSuggestions` constructor and `onSelected` callback.
- Preserve mention replacement format `[@name](attachment://id) `.

- [ ] **Step 1: Verify the existing mention regression test covers filtering and replacement**

Keep the test fixture metadata under `task_attachments/`, type `@con`, assert that only the matching attachment appears, tap it, and assert the description controller contains:

```text
[@contract.pdf](attachment://contract) 
```

- [ ] **Step 2: Keep each suggestion ListTile on a Material surface**

Retain the transparent `Material` wrapper around each `ListTile` so Flutter does not report invisible ink-splash/background diagnostics when the surrounding suggestion container has a decorated background. Run `dart format` after the edit.

- [ ] **Step 3: Run targeted, full, and static checks**

Run:

```bash
flutter test test/task_editor_sheet_test.dart test/description_markdown_test.dart
dart analyze
flutter test
git diff --check
```

Expected: the targeted tests and full suite pass, analyzer reports `No issues found`, and `git diff --check` is clean.

- [ ] **Step 4: Commit the completed task**

```bash
git add lib/features/tasks/widgets/attachment_mention_overlay.dart test/task_editor_sheet_test.dart
git commit -m "test(editor): cover attachment mention suggestions"
```

---

### Task 4: Final review and repository-safe handoff

**Files:**
- Review only: commits created by Tasks 1–3

- [ ] **Step 1: Inspect only the task commits**

Run:

```bash
git log --oneline -3
git show --stat --oneline HEAD~2..HEAD
git status --short
git diff --check HEAD~3..HEAD
```

Confirm the three task commits contain only the planned five feature/test files plus the planned popup test, and confirm pre-existing unrelated working-tree changes remain untouched.

- [ ] **Step 2: Run the final verification suite**

Run:

```bash
dart analyze
flutter test
```

Expected: analyzer is clean and the complete suite passes.

- [ ] **Step 3: Report the commit hashes and verification results**

Report each task commit, the tests run, and the fact that unrelated pre-existing changes were not staged or committed.
