#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
APP_NAME="Adventurers"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
VERSION="${1:-1.0.0}"

echo "========================================================="
echo "🚀 Adventurers Harness macOS ARM64 Build & Packager v${VERSION}"
echo "========================================================="

# Step 1: Ensure icons are built
if [ ! -f "${ROOT_DIR}/assets/AppIcon.icns" ]; then
    echo "🎨 AppIcon.icns not found, generating from SVG..."
    "${ROOT_DIR}/scripts/generate_icon.sh"
fi

# Step 2: Build release binary for macOS Apple Silicon (arm64)
echo "🔨 Building Release binary for macOS arm64..."
cd "${ROOT_DIR}"
swift build -c release --triple arm64-apple-macosx15.0

BIN_DIR="$(swift build -c release --triple arm64-apple-macosx15.0 --show-bin-path)"
EXECUTABLE_PATH="${BIN_DIR}/Adventurers"

if [ ! -f "${EXECUTABLE_PATH}" ]; then
    echo "✖ Error: Executable not found at ${EXECUTABLE_PATH}"
    exit 1
fi

# Verify architecture is arm64
ARCH_INFO="$(file "${EXECUTABLE_PATH}")"
echo "🔍 Binary Architecture: ${ARCH_INFO}"
if [[ "${ARCH_INFO}" != *"arm64"* ]]; then
    echo "✖ Error: Binary is not arm64!"
    exit 1
fi

# Step 3: Construct .app bundle
echo "📦 Constructing ${APP_NAME}.app bundle..."
rm -rf "${DIST_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Copy executable
cp "${EXECUTABLE_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# Copy AppIcon
cp "${ROOT_DIR}/assets/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
if [ -f "${ROOT_DIR}/assets/AppIcon.png" ]; then
    cp "${ROOT_DIR}/assets/AppIcon.png" "${APP_DIR}/Contents/Resources/AppIcon.png"
fi

# Write Info.plist
cat << PLIST > "${APP_DIR}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Adventurers</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.bytecats.adventurers</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSArchitecturePriority</key>
    <array>
        <string>arm64</string>
    </array>
    <key>NSMicrophoneUsageDescription</key>
    <string>Adventurers Harness uses your microphone for one-click voice dictation into the prompt bar.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Adventurers Harness uses Apple Speech recognition for live low-latency speech-to-text dictation.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSRequiresAquaSystemAppearance</key>
    <false/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 ByteCats. All rights reserved.</string>
</dict>
</plist>
PLIST

# Write PkgInfo
echo -n "APPL????" > "${APP_DIR}/Contents/PkgInfo"

# Step 4: Ad-hoc code signing for local & Apple Silicon execution
echo "🔏 Signing bundle with ad-hoc identity..."
codesign --force --deep --sign - "${APP_DIR}"

# Step 5: Package into distributable DMG
echo "💿 Creating DMG installer..."
DMG_PATH="${DIST_DIR}/${APP_NAME}-macOS-arm64.dmg"
hdiutil create -volname "${APP_NAME} Harness" \
    -srcfolder "${APP_DIR}" \
    -ov -format UDZO \
    "${DMG_PATH}"

# Step 6: Package into ZIP and TAR.GZ archives
echo "🗜 Creating ZIP & TAR.GZ distribution archives..."
ZIP_PATH="${DIST_DIR}/${APP_NAME}-macOS-arm64.zip"
TAR_PATH="${DIST_DIR}/${APP_NAME}-macOS-arm64.tar.gz"
cd "${DIST_DIR}"
zip -q -r -y "${ZIP_PATH}" "${APP_NAME}.app"
tar -czf "${TAR_PATH}" "${APP_NAME}.app"

# Step 7: Generate SHA256 checksums
echo "🔒 Computing SHA256 checksums..."
cd "${DIST_DIR}"
shasum -a 256 "${APP_NAME}-macOS-arm64.dmg" > "${APP_NAME}-macOS-arm64.dmg.sha256"
shasum -a 256 "${APP_NAME}-macOS-arm64.zip" > "${APP_NAME}-macOS-arm64.zip.sha256"
shasum -a 256 "${APP_NAME}-macOS-arm64.tar.gz" > "${APP_NAME}-macOS-arm64.tar.gz.sha256"

echo "========================================================="
echo "✔ Successfully packaged Adventurers Harness for macOS ARM64!"
echo "  • App Bundle: ${APP_DIR}"
echo "  • DMG Image:  ${DMG_PATH}"
echo "  • ZIP Archive:${ZIP_PATH}"
echo "  • TAR Archive:${TAR_PATH}"
echo "  • Checksum:   $(cat "${DIST_DIR}/${APP_NAME}-macOS-arm64.dmg.sha256")"
echo "========================================================="
