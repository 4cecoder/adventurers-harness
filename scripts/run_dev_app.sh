#!/usr/bin/env bash
set -euo pipefail

# Dev launcher: wraps the raw SwiftPM debug binary in a minimal .app bundle so macOS grants it a
# proper bundle identity. Without this, NSMicrophoneUsageDescription / NSSpeechRecognitionUsageDescription
# prompts never appear for `.build/debug/Adventurers` and voice dictation breaks in dev.
#
# Usage: scripts/run_dev_app.sh
#   Set ADVENTURERS_DEV_SKIP_LAUNCH=1 to build/sign the bundle without killing/opening it (CI-friendly).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_NAME="AdventurersDev"
DEV_DIR="${ROOT_DIR}/.build/dev"
APP_DIR="${DEV_DIR}/${APP_NAME}.app"
ENTITLEMENTS="${ROOT_DIR}/entitlements.plist"
ICON_SRC="${ROOT_DIR}/assets/AppIcon.icns"

echo "========================================================="
echo "🛠  Adventurers Harness Dev Bundle Launcher (${APP_NAME})"
echo "========================================================="

# Step 1: Build debug binaries
echo "🔨 Building debug binary..."
cd "${ROOT_DIR}"

# Clear orphaned SwiftPM builds holding the .build lock (see script header for rationale).
"${ROOT_DIR}/scripts/wait_build_lock.sh"

swift build

# Step 2: Locate the debug binary
BIN_DIR="$(swift build --show-bin-path)"
EXECUTABLE_PATH="${BIN_DIR}/Adventurers"
SPARKLE_FRAMEWORK_SRC="${BIN_DIR}/Sparkle.framework"

if [ ! -f "${EXECUTABLE_PATH}" ]; then
    echo "✖ Error: Executable not found at ${EXECUTABLE_PATH}"
    exit 1
fi

# Step 3: Construct the minimal dev .app bundle (idempotent)
echo "📦 Constructing ${APP_NAME}.app bundle..."
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Copy the executable under the dev bundle name
cp "${EXECUTABLE_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# SwiftPM links Sparkle via @rpath and relies on the @loader_path rpath baked into the binary,
# so the framework must sit next to the executable (Contents/MacOS) for the app to launch.
if [ -d "${SPARKLE_FRAMEWORK_SRC}" ]; then
    echo "🔧 Copying Sparkle.framework next to the dev executable..."
    cp -R "${SPARKLE_FRAMEWORK_SRC}" "${APP_DIR}/Contents/MacOS/Sparkle.framework"
fi

# Step 4: Write Info.plist with the mic/speech usage strings macOS needs to prompt properly
cat << PLIST > "${APP_DIR}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.bytecats.adventurers.dev</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Adventurers Harness uses your microphone for one-click voice dictation into the prompt bar.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Adventurers Harness uses Apple Speech recognition for live low-latency speech-to-text dictation.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Step 5: Bundle the app icon when available
if [ -f "${ICON_SRC}" ]; then
    echo "🎨 Bundling AppIcon.icns..."
    cp "${ICON_SRC}" "${APP_DIR}/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${APP_DIR}/Contents/Info.plist"
else
    echo "⚠️  No AppIcon.icns found — bundling without an icon."
fi

# PkgInfo is expected by LaunchServices
echo -n "APPL????" > "${APP_DIR}/Contents/PkgInfo"

# Step 6: Ad-hoc code sign with the repo entitlements (mic + speech recognition + get-task-allow)
echo "🔏 Ad-hoc signing ${APP_NAME}.app with audio/speech entitlements..."
codesign --force --entitlements "${ENTITLEMENTS}" --sign - "${APP_DIR}"

# Step 7: Relaunch — kill any stale instance, then open the fresh bundle
if [ "${ADVENTURERS_DEV_SKIP_LAUNCH:-0}" != "1" ]; then
    echo "🔁 Killing any previously running ${APP_NAME} instance..."
    pkill -f "${APP_NAME}" || true
    echo "🚀 Opening ${APP_DIR} ..."
    open "${APP_DIR}"
    echo "✔ ${APP_NAME}.app launched. Microphone prompts should now appear correctly."
else
    echo "✔ ADVENTURERS_DEV_SKIP_LAUNCH=1 — bundle built & signed but not launched."
fi

echo "========================================================="
echo "✔ Dev bundle ready: ${APP_DIR}"
echo "========================================================="
