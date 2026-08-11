#!/usr/bin/env bash
# scripts/build.sh — Сборка release APK с автоматической подстановкой BUILD_TIME.
#
# Использование:
#   ./scripts/build.sh              # обычная сборка (fat APK)
#   ./scripts/build.sh --split      # split per-ABI (arm64 / armeabi / x86_64)
#
# The ignored config/private.env file is required and is read without sourcing
# shell code. Use --without-diagnostics only for an intentional local build
# where diagnostic reporting must remain disabled.
#
# BUILD_TIME автоматически устанавливается в текущее UTC-время, если не задан
# через переменную окружения.
#
# APP_VERSION берётся из pubspec.yaml (строка "version: X.Y.Z+N"),
# если не задан через переменную окружения.

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Parse flags before constructing any build arguments. Unknown flags fail
# instead of silently producing a different artifact than requested.
WITHOUT_DIAGNOSTICS=0
SPLIT=0
for arg in "$@"; do
  case "$arg" in
    --without-diagnostics) WITHOUT_DIAGNOSTICS=1 ;;
    --split) SPLIT=1 ;;
    '') ;;
    *) echo "Unknown flag: $arg" >&2; exit 1 ;;
  esac
done

# Read the config without sourcing it, so arbitrary lines cannot execute as
# shell code.
if [[ "$WITHOUT_DIAGNOSTICS" -eq 0 ]]; then
  # shellcheck source=scripts/load_diagnostics_config.sh
  source "$REPO_ROOT/scripts/load_diagnostics_config.sh"
  load_diagnostics_config "${DIAGNOSTICS_CONFIG:-$REPO_ROOT/config/private.env}" 1
fi

# ── Определить версию из pubspec.yaml ──────────────────────────────────────
if [[ -z "${APP_VERSION:-}" ]]; then
  APP_VERSION=$(grep -E '^version:' pubspec.yaml | head -1 | awk '{print $2}' | cut -d'+' -f1)
fi
echo "APP_VERSION=${APP_VERSION}"

# ── Определить BUILD_TIME ──────────────────────────────────────────────────
if [[ -z "${BUILD_TIME:-}" ]]; then
  BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fi
echo "BUILD_TIME=${BUILD_TIME}"

# ── Общие dart-define ──────────────────────────────────────────────────────
DART_DEFINES=(
  "--dart-define=APP_VERSION=${APP_VERSION}"
  "--dart-define=BUILD_TIME=${BUILD_TIME}"
)
if [[ "$WITHOUT_DIAGNOSTICS" -eq 0 && -n "${DIAGNOSTICS_ENDPOINT:-}" ]]; then
  DART_DEFINES+=("--dart-define=DIAGNOSTICS_ENDPOINT=${DIAGNOSTICS_ENDPOINT}")
fi

# ── Сборка ─────────────────────────────────────────────────────────────────
if [[ "$SPLIT" -eq 1 ]]; then
  echo "Building split-per-abi APKs…"
  flutter build apk --release --split-per-abi "${DART_DEFINES[@]}"
else
  echo "Building fat APK…"
  flutter build apk --release "${DART_DEFINES[@]}"
fi

echo ""
echo "✅ Сборка завершена."
echo "   APK: build/app/outputs/flutter-apk/"
