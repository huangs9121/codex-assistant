#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=version.env
source "$SCRIPT_DIR/version.env"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid APP_VERSION in version.env" >&2
    exit 1
fi
if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    echo "Invalid BUILD_NUMBER in version.env" >&2
    exit 1
fi
WORKSPACE_ROOT="$(cd "$PACKAGE_ROOT/../.." && pwd)"
OUTPUT_DIR="$WORKSPACE_ROOT/outputs"
APP="$OUTPUT_DIR/Codex Quota.app"
ZIP="$OUTPUT_DIR/Codex Quota-arm64.zip"
TEMP_DIR="$PACKAGE_ROOT/.build-app"
STAGING_APP="$TEMP_DIR/Codex Quota.app"
STAGING_ZIP="$TEMP_DIR/Codex Quota-arm64.zip"
BACKUP_APP="$OUTPUT_DIR/.Codex Quota.app.backup.$$"
BACKUP_ZIP="$OUTPUT_DIR/.Codex Quota-arm64.zip.backup.$$"
RETIRED_BACKUP_APP="$TEMP_DIR/previous.app"
RETIRED_BACKUP_ZIP="$TEMP_DIR/previous.zip"
ICONSET="$TEMP_DIR/icon.iconset"
SOURCE_ICON="$TEMP_DIR/icon-1024.png"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
HAD_PREVIOUS_APP=0
HAD_PREVIOUS_ZIP=0
APP_BACKED_UP=0
ZIP_BACKED_UP=0
NEW_APP_INSTALLED=0
NEW_ZIP_INSTALLED=0
REPLACEMENT_STARTED=0
REPLACEMENT_COMMITTED=0

cleanup() {
    status=$?
    trap - EXIT

    if [[ "$status" != "0" && "$REPLACEMENT_STARTED" == "1" && "$REPLACEMENT_COMMITTED" == "0" ]]; then
        if [[ "$NEW_APP_INSTALLED" == "1" ]]; then
            rm -rf "$APP"
        fi
        if [[ "$NEW_ZIP_INSTALLED" == "1" ]]; then
            rm -f "$ZIP"
        fi

        if [[ "$APP_BACKED_UP" == "1" ]]; then
            if [[ -e "$BACKUP_APP" ]]; then
                mv "$BACKUP_APP" "$APP" || status=1
            elif [[ -e "$RETIRED_BACKUP_APP" ]]; then
                mv "$RETIRED_BACKUP_APP" "$APP" || status=1
            else
                status=1
            fi
        fi
        if [[ "$ZIP_BACKED_UP" == "1" ]]; then
            if [[ -e "$BACKUP_ZIP" ]]; then
                mv "$BACKUP_ZIP" "$ZIP" || status=1
            elif [[ -e "$RETIRED_BACKUP_ZIP" ]]; then
                mv "$RETIRED_BACKUP_ZIP" "$ZIP" || status=1
            else
                status=1
            fi
        fi
    fi

    rm -rf "$TEMP_DIR"
    exit "$status"
}

trap cleanup EXIT
rm -rf "$TEMP_DIR"
mkdir -p "$STAGING_APP/Contents/MacOS" "$STAGING_APP/Contents/Resources" "$ICONSET"

swift run --package-path "$PACKAGE_ROOT" CodexQuotaCoreTests
swift build --package-path "$PACKAGE_ROOT" -c release --arch arm64
BIN_DIR="$(swift build --package-path "$PACKAGE_ROOT" -c release --arch arm64 --show-bin-path)"
cp "$BIN_DIR/CodexQuotaApp" "$STAGING_APP/Contents/MacOS/CodexQuotaApp"

swift "$SCRIPT_DIR/generate_icon.swift" "$SOURCE_ICON"
while IFS=: read -r size name; do
    sips -z "$size" "$size" "$SOURCE_ICON" --out "$ICONSET/$name" >/dev/null
done <<'SIZES'
16:icon_16x16.png
32:icon_16x16@2x.png
32:icon_32x32.png
64:icon_32x32@2x.png
128:icon_128x128.png
256:icon_128x128@2x.png
256:icon_256x256.png
512:icon_256x256@2x.png
512:icon_512x512.png
1024:icon_512x512@2x.png
SIZES
iconutil -c icns "$ICONSET" -o "$STAGING_APP/Contents/Resources/icon.icns"

cat > "$STAGING_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CodexQuotaApp</string>
    <key>CFBundleIconFile</key>
    <string>icon</string>
    <key>CFBundleIdentifier</key>
    <string>local.openclaw.codexquota</string>
    <key>CFBundleName</key>
    <string>Codex Quota</string>
    <key>CFBundleDisplayName</key>
    <string>Codex Quota</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
    </array>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

chmod -R u=rwX,go=rX "$STAGING_APP"
chmod 755 "$STAGING_APP/Contents/MacOS/CodexQuotaApp"
xattr -cr "$STAGING_APP"
plutil -lint "$STAGING_APP/Contents/Info.plist"
test "$(plutil -extract CFBundleShortVersionString raw "$STAGING_APP/Contents/Info.plist")" = "$APP_VERSION"
test "$(plutil -extract CFBundleVersion raw "$STAGING_APP/Contents/Info.plist")" = "$BUILD_NUMBER"
test "$(plutil -extract CFBundleDevelopmentRegion raw "$STAGING_APP/Contents/Info.plist")" = "en"
test "$(plutil -extract CFBundleLocalizations.0 raw "$STAGING_APP/Contents/Info.plist")" = "en"
test "$(plutil -extract CFBundleLocalizations.1 raw "$STAGING_APP/Contents/Info.plist")" = "zh-Hans"

VERIFY_ICONSET="$TEMP_DIR/verify.iconset"
EXPECTED_ICONS="$TEMP_DIR/expected-icons.txt"
ACTUAL_ICONS="$TEMP_DIR/actual-icons.txt"
iconutil -c iconset "$STAGING_APP/Contents/Resources/icon.icns" -o "$VERIFY_ICONSET"
printf '%s\n' \
    icon_16x16.png icon_16x16@2x.png \
    icon_32x32.png icon_32x32@2x.png \
    icon_128x128.png icon_128x128@2x.png \
    icon_256x256.png icon_256x256@2x.png \
    icon_512x512.png icon_512x512@2x.png \
    | sort > "$EXPECTED_ICONS"
find "$VERIFY_ICONSET" -maxdepth 1 -type f -exec basename {} \; | sort > "$ACTUAL_ICONS"
diff -u "$EXPECTED_ICONS" "$ACTUAL_ICONS"

codesign --force --deep --sign - "$STAGING_APP"
chmod -R u=rwX,go=rX "$STAGING_APP"
chmod 755 "$STAGING_APP/Contents/MacOS/CodexQuotaApp"
if find "$STAGING_APP" \( -perm -002 -o -perm -020 \) -print -quit | grep -q .; then
    echo "staging app contains group- or world-writable paths" >&2
    exit 1
fi
codesign --verify --deep --strict "$STAGING_APP"

ditto -c -k --sequesterRsrc --keepParent "$STAGING_APP" "$STAGING_ZIP"
chmod 644 "$STAGING_ZIP"
unzip -t "$STAGING_ZIP" >/dev/null

VERIFY_ZIP_DIR="$TEMP_DIR/verify-zip"
mkdir -p "$VERIFY_ZIP_DIR"
ditto -x -k "$STAGING_ZIP" "$VERIFY_ZIP_DIR"
VERIFY_ZIP_APP="$VERIFY_ZIP_DIR/Codex Quota.app"
test -d "$VERIFY_ZIP_APP"
test -x "$VERIFY_ZIP_APP/Contents/MacOS/CodexQuotaApp"
test -f "$VERIFY_ZIP_APP/Contents/Resources/icon.icns"
plutil -lint "$VERIFY_ZIP_APP/Contents/Info.plist"
test "$(plutil -extract CFBundlePackageType raw "$VERIFY_ZIP_APP/Contents/Info.plist")" = "APPL"
test "$(plutil -extract CFBundleShortVersionString raw "$VERIFY_ZIP_APP/Contents/Info.plist")" = "$APP_VERSION"
test "$(plutil -extract CFBundleVersion raw "$VERIFY_ZIP_APP/Contents/Info.plist")" = "$BUILD_NUMBER"
file "$VERIFY_ZIP_APP/Contents/MacOS/CodexQuotaApp" | grep -q 'arm64'
if find "$VERIFY_ZIP_APP" \( -perm -002 -o -perm -020 \) -print -quit | grep -q .; then
    echo "staged ZIP contains group- or world-writable app paths" >&2
    exit 1
fi
codesign --verify --deep --strict "$VERIFY_ZIP_APP"

mkdir -p "$OUTPUT_DIR"
test ! -e "$BACKUP_APP"
test ! -e "$BACKUP_ZIP"
if [[ -e "$APP" ]]; then
    HAD_PREVIOUS_APP=1
fi
if [[ -e "$ZIP" ]]; then
    HAD_PREVIOUS_ZIP=1
fi

REPLACEMENT_STARTED=1
if [[ "$HAD_PREVIOUS_APP" == "1" ]]; then
    mv "$APP" "$BACKUP_APP"
    APP_BACKED_UP=1
fi
if [[ "$HAD_PREVIOUS_ZIP" == "1" ]]; then
    mv "$ZIP" "$BACKUP_ZIP"
    ZIP_BACKED_UP=1
fi

mv "$STAGING_APP" "$APP"
NEW_APP_INSTALLED=1
mv "$STAGING_ZIP" "$ZIP"
NEW_ZIP_INSTALLED=1

"$LSREGISTER" -f -R "$APP"
touch "$APP"

if [[ "$APP_BACKED_UP" == "1" ]]; then
    mv "$BACKUP_APP" "$RETIRED_BACKUP_APP"
fi
if [[ "$ZIP_BACKED_UP" == "1" ]]; then
    mv "$BACKUP_ZIP" "$RETIRED_BACKUP_ZIP"
fi
REPLACEMENT_COMMITTED=1

echo "Built $APP"
echo "Built $ZIP"
