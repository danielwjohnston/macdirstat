#!/bin/zsh
set -e

cd "$(dirname "$0")"

echo "Building release binary..."
swift build -c release

APP_NAME="MacDirStat.app"
DEST="/Applications/${APP_NAME}"
CONTENTS="${DEST}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "Creating bundle at ${DEST}..."
rm -rf "${DEST}"
mkdir -p "${MACOS}" "${RESOURCES}"

cp .build/release/MacDirStat "${MACOS}/MacDirStat"
chmod +x "${MACOS}/MacDirStat"

# Copy generated .icns icon
if [ -f "../AppIcon.icns" ]; then
    cp "../AppIcon.icns" "${RESOURCES}/AppIcon.icns"
elif [ -f "AppIcon.icns" ]; then
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
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSRequiresAquaSystemAppearance</key>
    <false/>
</dict>
</plist>
PLIST

# Ad-hoc code sign so macOS gatekeeper & TCC acknowledge bundle identity
codesign --force --deep --sign - "${DEST}"

echo "Installed successfully to ${DEST}"
