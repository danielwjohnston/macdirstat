#!/bin/zsh
set -e

cd "$(dirname "$0")"

# Optional overrides:
#   DEST_DIR=~/Apps ./build_app.sh            install somewhere other than /Applications
#   SCRATCH_PATH=/Volumes/X/.build ./build_app.sh
#       keep build products elsewhere, e.g. on an APFS volume when the checkout lives on
#       exFAT/FAT, where AppleDouble "._" files make codesign fail
DEST_DIR="${DEST_DIR:-/Applications}"
BUILD_ARGS=(-c release)
if [ -n "${SCRATCH_PATH}" ]; then
    BUILD_ARGS+=(--scratch-path "${SCRATCH_PATH}")
fi

echo "Building release binary..."
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

APP_NAME="MacDirStat.app"
DEST="${DEST_DIR}/${APP_NAME}"
CONTENTS="${DEST}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "Creating bundle at ${DEST}..."
rm -rf "${DEST}"
mkdir -p "${MACOS}" "${RESOURCES}"

cp "${BIN_DIR}/MacDirStat" "${MACOS}/MacDirStat"
chmod +x "${MACOS}/MacDirStat"

# Copy generated .icns icon
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "${RESOURCES}/AppIcon.icns"
fi

cat << 'PLIST' > "${CONTENTS}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>MacDirStat</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.dwjohnston.MacDirStat</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MacDirStat</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSRequiresAquaSystemAppearance</key>
    <false/>
</dict>
</plist>
PLIST

# Extended attributes (quarantine, Finder info) are "detritus" to codesign
xattr -cr "${DEST}"

# Ad-hoc code sign so macOS gatekeeper & TCC acknowledge bundle identity
codesign --force --deep --sign - "${DEST}"

echo "Installed successfully to ${DEST}"
