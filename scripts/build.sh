#!/usr/bin/env bash
# scripts/build.sh — Сборка release APK с автоматической подстановкой BUILD_TIME.
#
# Использование:
#   ./scripts/build.sh              # обычная сборка (fat APK)
#   ./scripts/build.sh --split      # split per-ABI (arm64 / armeabi / x86_64)
#
# BUILD_TIME автоматически устанавливается в текущее UTC-время, если не задан
# через переменную окружения.
#
# APP_VERSION берётся из pubspec.yaml (строка "version: X.Y.Z+N"),
# если не задан через переменную окружения.

set -euo pipefail
cd "$(dirname "$0")/.."

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

# ── Сборка ─────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--split" ]]; then
  echo "Building split-per-abi APKs…"
  flutter build apk --release --split-per-abi "${DART_DEFINES[@]}"
else
  echo "Building fat APK…"
  flutter build apk --release "${DART_DEFINES[@]}"
fi

echo ""
echo "✅ Сборка завершена."
echo "   APK: build/app/outputs/flutter-apk/"
