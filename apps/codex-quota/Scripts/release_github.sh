#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PACKAGE_ROOT/../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=version.env
source "$SCRIPT_DIR/version.env"
TAG="v$APP_VERSION"
REPOSITORY="huangs9121/codex-assistant"
ZIP="outputs/Codex Quota-arm64.zip"
RELEASE_NOTES="docs/releases/$TAG.md"
TEMP_DIR=""

cleanup() {
    if [[ -n "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

validate_repository_url() {
    case "$1" in
        "https://github.com/$REPOSITORY" | \
        "https://github.com/$REPOSITORY.git" | \
        "git@github.com:$REPOSITORY" | \
        "git@github.com:$REPOSITORY.git" | \
        "ssh://git@github.com/$REPOSITORY" | \
        "ssh://git@github.com/$REPOSITORY.git")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

ensure_public_release_absent() {
    local release_error
    local release_status
    release_error="$(mktemp)"
    if gh release view "$TAG" --repo "$REPOSITORY" >/dev/null 2>"$release_error"; then
        rm -f "$release_error"
        echo "Public release already exists: $TAG" >&2
        exit 1
    else
        release_status=$?
        if ! grep -Eqi 'release not found|HTTP 404' "$release_error"; then
            cat "$release_error" >&2
            rm -f "$release_error"
            exit "$release_status"
        fi
    fi
    rm -f "$release_error"
}

cd "$REPO_ROOT"

ORIGIN_URL="$(git remote get-url origin)"
if ! validate_repository_url "$ORIGIN_URL"; then
    echo "Origin must be huangs9121/codex-assistant on github.com" >&2
    exit 1
fi

PUSH_URLS=()
while IFS= read -r push_url; do
    if [[ -n "$push_url" ]]; then
        PUSH_URLS+=("$push_url")
    fi
done < <(git remote get-url --push --all origin)
if [[ "${#PUSH_URLS[@]}" -ne 1 ]] || ! validate_repository_url "${PUSH_URLS[0]:-}"; then
    echo "Origin must have exactly one approved push URL" >&2
    exit 1
fi

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
SOURCE_COMMIT="$(git rev-parse HEAD)"
if git rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null; then
    echo "Local tag already exists: $TAG" >&2
    exit 1
fi
ensure_public_release_absent

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

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Release requires a clean Git worktree after building" >&2
    exit 1
fi
if [[ "$(git branch --show-current)" != "main" ]]; then
    echo "Release branch changed while building" >&2
    exit 1
fi
if [[ "$(git rev-parse HEAD)" != "$SOURCE_COMMIT" ]]; then
    echo "HEAD changed while building" >&2
    exit 1
fi

git fetch origin main --tags

CURRENT_HEAD="$(git rev-parse HEAD)"
REMOTE_HEAD="$(git rev-parse origin/main)"
if [[ "$CURRENT_HEAD" != "$SOURCE_COMMIT" ]] || [[ "$REMOTE_HEAD" != "$SOURCE_COMMIT" ]]; then
    echo "Release source changed after building" >&2
    exit 1
fi
if git rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null; then
    echo "Local tag already exists: $TAG" >&2
    exit 1
fi
ensure_public_release_absent

git tag -a "$TAG" "$SOURCE_COMMIT" -m "Codex Quota $APP_VERSION"
git push origin "$TAG"

if ! gh release create "$TAG" "$ZIP" \
    --repo "$REPOSITORY" \
    --title "Codex Quota $APP_VERSION" \
    --notes-file "$RELEASE_NOTES" \
    --verify-tag; then
    echo "Release creation failed after pushing $TAG; do not automatically delete or change the public tag" >&2
    exit 1
fi
