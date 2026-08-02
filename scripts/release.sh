#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/release.sh <version> <build> [--no-push] [--dry-run]
#   version — plain SemVer, e.g. 1.2.0
#   build   — Android build number, e.g. 3  (pubspec becomes 1.2.0+3)

VERSION="${1:-}"
BUILD="${2:-}"
DRY_RUN=0
NO_PUSH=0
for arg in "${@:3}"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --no-push) NO_PUSH=1 ;;
    *) echo "Unknown flag: $arg" >&2; exit 1 ;;
  esac
done

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must be plain SemVer (e.g. 1.2.0)" >&2
  exit 1
fi
if [[ ! "$BUILD" =~ ^[0-9]+$ ]]; then
  echo "Build must be an integer (e.g. 3)" >&2
  exit 1
fi

FULL="${VERSION}+${BUILD}"
TAG="v${FULL}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

step() { echo "==> $*"; }

# 1. Version bump (pubspec + APP_VERSION default).
step "Bumping pubspec.yaml to ${FULL}"
perl -pi -e "s/^version: .*/version: ${FULL}/" pubspec.yaml
step "Updating APP_VERSION default to ${VERSION}"
perl -pi -e "s/(defaultValue: ')[0-9]+\.[0-9]+\.[0-9]+(')/\${1}${VERSION}\${2}/" lib/core/version_service.dart

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Dry run — skipping build, commit, tag, and release."
  git diff --stat pubspec.yaml lib/core/version_service.dart
  exit 0
fi

# 2. Commit the bump.
step "Committing version bump"
git add pubspec.yaml lib/core/version_service.dart
git commit -m "chore: bump version to ${FULL}"

# 3. Build the arm64 APK with the correct APP_VERSION.
step "Building arm64 APK (APP_VERSION=${VERSION})"
flutter build apk \
  --target-platform android-arm64 \
  --split-per-abi \
  --release \
  --dart-define="APP_VERSION=${VERSION}"

APK="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
ASSET="build/app/outputs/flutter-apk/Asa-${FULL}-arm64-v8a.apk"
step "Copying asset to ${ASSET}"
cp "$APK" "$ASSET"

# 4. Tag.
step "Tagging ${TAG}"
git tag "$TAG"
if [[ "$NO_PUSH" -eq 0 ]]; then
  step "Pushing commit + tag"
  git push origin HEAD --tags
else
  echo "Skipping push (--no-push)."
fi

# 5. Release notes from git log since the previous tag.
PREV_TAG="$(git describe --tags --abbrev=0 "$TAG^" 2>/dev/null || echo '')"
if [[ -z "$PREV_TAG" ]]; then
  NOTES="Release ${VERSION}"
else
  NOTES="$(git log --format='- %s' "${PREV_TAG}..HEAD" | head -80)"
fi

# 6. Create the GitHub release + upload the APK.
if command -v gh >/dev/null 2>&1; then
  step "Creating release with gh"
  gh release create "$TAG" "$ASSET" \
    --title "ASA ${VERSION}" \
    --notes "$NOTES"
else
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "gh CLI not found and GITHUB_TOKEN is not set. Release not created." >&2
    echo "Tag and asset are ready: ${TAG} -> ${ASSET}" >&2
    exit 1
  fi
  step "Creating release via GitHub API"
  BODY_JSON="$(python3 -c 'import json,sys; print(json.dumps({"tag_name": sys.argv[1], "name": sys.argv[2], "body": sys.argv[3], "draft": False, "prerelease": False}))' "$TAG" "ASA ${VERSION}" "$NOTES")"
  RELEASE_JSON="$(curl -fsSL -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -d "$BODY_JSON" \
    "https://api.github.com/repos/SabirDzh/Asa/releases")"
  RELEASE_ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$RELEASE_JSON")"
  ENCODED="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "Asa-${FULL}-arm64-v8a.apk")"
  step "Uploading ${ASSET}"
  curl -fsSL -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/vnd.android.package-archive" \
    --data-binary "@${ASSET}" \
    "https://uploads.github.com/repos/SabirDzh/Asa/releases/${RELEASE_ID}/assets?name=${ENCODED}" >/dev/null
fi

echo "Done: ${TAG}"
