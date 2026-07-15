#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PACKAGE_ROOT/../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=version.env
source "$SCRIPT_DIR/version.env"
TAG="v$APP_VERSION"
REPO="huangs9121/codex-assistant"
ZIP="outputs/Codex Quota-arm64.zip"
RELEASE_NOTES="docs/releases/$TAG.md"
TEMP_DIR=""

cleanup() {
    if [[ -n "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

cd "$REPO_ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Release requires a clean Git worktree" >&2
    exit 1
fi
if [[ "$(git branch --show-current)" != "main" ]]; then
    echo "Release must run from the main branch" >&2
    exit 1
fi

git fetch origin main --tags

if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
    echo "HEAD must match origin/main" >&2
    exit 1
fi
if git rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null; then
    echo "Local tag already exists: $TAG" >&2
    exit 1
fi

RELEASE_ERROR="$(mktemp)"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>"$RELEASE_ERROR"; then
    rm -f "$RELEASE_ERROR"
    echo "Public release already exists: $TAG" >&2
    exit 1
else
    RELEASE_STATUS=$?
    if ! grep -Eqi 'release not found|HTTP 404' "$RELEASE_ERROR"; then
        cat "$RELEASE_ERROR" >&2
        rm -f "$RELEASE_ERROR"
        exit "$RELEASE_STATUS"
    fi
fi
rm -f "$RELEASE_ERROR"

"$SCRIPT_DIR/build_app.sh"

test -f "$ZIP"
test -f "$RELEASE_NOTES"
unzip -t "$ZIP" >/dev/null
TEMP_DIR="$(mktemp -d)"
ditto -x -k "$ZIP" "$TEMP_DIR"
ZIP_APP="$TEMP_DIR/Codex Quota.app"
test "$(plutil -extract CFBundleShortVersionString raw "$ZIP_APP/Contents/Info.plist")" = "$APP_VERSION"
test "$(plutil -extract CFBundleVersion raw "$ZIP_APP/Contents/Info.plist")" = "$BUILD_NUMBER"
codesign --verify --deep --strict "$ZIP_APP"
file "$ZIP_APP/Contents/MacOS/CodexQuotaApp" | grep -q 'arm64'
rm -rf "$TEMP_DIR"
TEMP_DIR=""

git tag -a "$TAG" -m "Codex Quota $APP_VERSION"
git push origin "$TAG"

if ! gh release create "$TAG" "$ZIP" \
    --repo "$REPO" \
    --title "Codex Quota $APP_VERSION" \
    --notes-file "$RELEASE_NOTES" \
    --verify-tag; then
    echo "Release creation failed after pushing $TAG; do not automatically delete or change the public tag" >&2
    exit 1
fi
