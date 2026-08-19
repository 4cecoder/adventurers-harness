#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "🎨 [1/2] Rendering AppIcon.svg to Apple standard .iconset sizes..."
cd "${ROOT_DIR}"
swiftc "${ROOT_DIR}/scripts/render_icon.swift" -o "${ROOT_DIR}/scripts/render_icon_bin"
"${ROOT_DIR}/scripts/render_icon_bin"
rm -f "${ROOT_DIR}/scripts/render_icon_bin"

echo "📦 [2/2] Compiling iconset into macOS AppIcon.icns..."
if [ -d "${ROOT_DIR}/assets/AppIcon.iconset" ]; then
    iconutil -c icns "${ROOT_DIR}/assets/AppIcon.iconset" -o "${ROOT_DIR}/assets/AppIcon.icns"
    echo "✔ Successfully generated AppIcon.icns: ${ROOT_DIR}/assets/AppIcon.icns"
else
    echo "✖ Error: AppIcon.iconset was not generated."
    exit 1
fi
