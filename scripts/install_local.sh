#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
DEFAULT_SRC="${DIST_DIR}/Adventurers.app"
APP_NAME="Adventurers"
DEST_APP="/Applications/${APP_NAME}.app"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--no-launch] [--dry-run] [-h | --help] [APP_PATH]

Locally installs a packaged Adventurers.app bundle into /Applications.

Options:
  --no-launch   Install but do not launch the app afterwards
  --dry-run     Print every action instead of performing it (no changes made)
  -h, --help    Show this help and exit

Arguments:
  APP_PATH      Optional path to a .app bundle to install instead of
                ${DEFAULT_SRC} (useful for testing).
EOF
}

die() {
    echo "❌ $*" >&2
    exit 1
}

DRY_RUN="false"
NO_LAUNCH="false"
SRC_APP=""
POSITIONAL_SEEN="false"

while [ $# -gt 0 ]; do
    case "$1" in
        --no-launch)
            NO_LAUNCH="true"
            ;;
        --dry-run)
            DRY_RUN="true"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            usage >&2
            die "Unknown option: $1"
            ;;
        *)
            if [ "${POSITIONAL_SEEN}" = "true" ]; then
                die "Unexpected extra argument: $1 (only one APP_PATH is supported)"
            fi
            POSITIONAL_SEEN="true"
            SRC_APP="$1"
            ;;
    esac
    shift
done

if [ -z "${SRC_APP}" ]; then
    SRC_APP="${DEFAULT_SRC}"
fi

run() {
    if [ "${DRY_RUN}" = "true" ]; then
        echo "   [dry-run] $*"
    else
        "$@"
    fi
}

echo "========================================================="
echo "📦 Adventurers local installer"
echo "========================================================="

if [ ! -d "${SRC_APP}" ]; then
    echo "" >&2
    echo "❌ Source app not found: ${SRC_APP}" >&2
    echo "" >&2
    echo "   Build and package it first with:" >&2
    echo "     ./scripts/package_app.sh" >&2
    echo "" >&2
    echo "   (or pass an explicit bundle: ./scripts/install_local.sh /path/to/Adventurers.app)" >&2
    exit 1
fi

echo "Source: ${SRC_APP}"
echo "Target: ${DEST_APP}"
if [ "${DRY_RUN}" = "true" ]; then
    echo "Mode:   dry run (nothing will be modified)"
fi
echo ""

echo "-> Quitting any running instance of ${APP_NAME}..."
run osascript -e 'quit app "Adventurers"' 2>/dev/null || true
run pkill -f "${DEST_APP}" 2>/dev/null || true
sleep 1

echo "-> Removing previous installation..."
run rm -rf "${DEST_APP}"

echo "-> Installing bundle (ditto preserves signatures and metadata)..."
run ditto "${SRC_APP}" "${DEST_APP}"

echo "-> Clearing quarantine attribute if present..."
run xattr -dr com.apple.quarantine "${DEST_APP}" 2>/dev/null || true

echo "-> Verifying code signature at destination..."
run codesign --verify --deep --strict "${DEST_APP}"
echo "   Signature OK."

if [ "${NO_LAUNCH}" = "true" ]; then
    echo "-> Skipping launch (--no-launch)."
else
    echo "-> Launching ${APP_NAME}..."
    run open "${DEST_APP}"
fi

INFO_PLIST="${SRC_APP}/Contents/Info.plist"
VERSION="$(plutil -extract CFBundleShortVersionString raw "${INFO_PLIST}" 2>/dev/null || plutil -extract CFBundleVersion raw "${INFO_PLIST}" 2>/dev/null || echo "unknown")"

echo ""
echo "========================================================="
if [ "${DRY_RUN}" = "true" ]; then
    echo "🧪 Dry run complete — no changes were made."
else
    echo "✅ Installation complete."
fi
echo "---------------------------------------------------------"
if [ "${DRY_RUN}" = "true" ]; then
    echo "   Would install: ${DEST_APP}"
else
    echo "   Installed:     ${DEST_APP}"
fi
echo "   Version:       ${VERSION}"
echo "   Launch later:  open ${DEST_APP}"
echo "   Uninstall:     rm -rf ${DEST_APP}"
echo "========================================================="
