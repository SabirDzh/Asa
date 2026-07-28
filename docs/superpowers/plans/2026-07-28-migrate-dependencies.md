# Dependencies Migration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade Flutter SDK and all project dependencies to latest compatible versions.

**Architecture:** Flutter 3.44.8 + Dart 3.12.2 already upgraded. Remaining work: verify `google_fonts` 6→8 API compatibility, run `dart fix` for `flutter_lints` 5→6 new rules, and clean up any deprecation warnings from the Flutter SDK bump.

**Tech Stack:** Flutter, Dart, google_fonts, flutter_lints

## Global Constraints

- Flutter >=3.44.8 (already on this version)
- Dart SDK >=3.7.2 (currently 3.12.2)
- Keep all existing functionality; no visual/behavioral changes
- Must pass `dart analyze lib/` with zero issues

---

### Task 1: Verify google_fonts 8.2.0 API compatibility

**Files:**
- Verify: `lib/core/theme.dart:91-93`

**Interfaces:**
- Consumes: none
- Produces: confirmed working `GoogleFonts.interTextTheme()` and `GoogleFonts.inter()` calls

- [ ] **Check that removed font methods are not used**

The project uses only `GoogleFonts.interTextTheme()` and `GoogleFonts.inter()`. These were NOT removed in google_fonts 7.x/8.x. The removed methods are condensed/expanded variants (robotoCondensed, bigShouldersDisplay, etc.) not used in this project.

```bash
# Verify no removed font method calls exist
rg -r 'GoogleFonts\.(robotoCondensed|openSansCondensed|bigShouldersDisplay|bigShouldersText|encodeSansCondensed|ibmPlexSansCondensed|montserratSubrayada|sairaCondensed|sairaExtraCondensed|sairaSemiCondensed|bioRhymeExpanded|encodeSansExpanded|encodeSansSemiCondensed|encodeSansSemiExpanded|notoSansPhagsPa)\(\'' lib/
```

Expected: no matches.

- [ ] **Verify Config → GoogleFontsConfig is not needed**

`Config` was renamed to `GoogleFontsConfig` with a backward-compat typedef. Since no code directly references `GoogleFonts.config` or `Config`, no changes needed.

```bash
rg 'GoogleFonts\.config' lib/
rg 'import.*Config' lib/
```

Expected: no matches.

- [ ] **Run analyzer**

```bash
dart analyze lib/
```

Expected: No issues found.

- [ ] **Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(deps): bump google_fonts to 8.2.0"
```

---

### Task 2: Fix flutter_lints 6.0.0 new lint violations

**Files:**
- Fix: all files in `lib/`

**Interfaces:**
- Consumes: `flutter_lints ^6.0.0` already in pubspec.yaml
- Produces: zero-lint codebase

- [ ] **Run `dart fix --apply` for auto-fixable issues**

```bash
dart fix --apply lib/
```

This will auto-fix `unnecessary_underscores` violations (redundant `_` wildcards).

- [ ] **Check for `strict_top_level_inference` violations**

Run `dart analyze lib/` and look for `strict_top_level_inference` errors. This lint flags top-level declarations (fields, getters, function return types) that rely on type inference.

```bash
dart analyze lib/ 2>&1 | grep strict_top_level_inference
```

If any violations are found, add explicit type annotations:

```dart
// Before (if flagged):
final count = 0;

// After:
final int count = 0;
```

- [ ] **Run final analyzer**

```bash
dart analyze lib/
```

Expected: No issues found.

- [ ] **Commit**

```bash
git add -A
git commit -m "chore(deps): bump flutter_lints to 6.0.0 and fix new lint rules"
```

---

### Task 3: Build verification

- [ ] **Build APK**

```bash
JAVA_HOME=/opt/homebrew/opt/openjdk@21 flutter build apk
```

Expected: `✓ Built build/app/outputs/flutter-apk/app-release.apk`

- [ ] **Run tests**

```bash
flutter test
```

Expected: All tests pass.
