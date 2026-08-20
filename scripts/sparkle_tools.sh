#!/usr/bin/env bash
# Downloads (and caches) Sparkle's CLI tools — generate_keys, sign_update, generate_appcast —
# and dispatches to them. These ship in Sparkle's "for general use" tarball, which is a separate
# release asset from the SPM binary framework that Package.swift depends on, so they aren't
# available via `swift build`/`swift run`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SPARKLE_VERSION="2.9.6"
TOOLS_DIR="${ROOT_DIR}/.sparkle-tools"
BIN_DIR="${TOOLS_DIR}/bin"

fetch_tools() {
    if [ -x "${BIN_DIR}/generate_keys" ] && [ -x "${BIN_DIR}/sign_update" ] && [ -x "${BIN_DIR}/generate_appcast" ]; then
        return
    fi
    echo "⬇️  Fetching Sparkle ${SPARKLE_VERSION} CLI tools..." >&2
    mkdir -p "${TOOLS_DIR}"
    local archive="${TOOLS_DIR}/Sparkle-${SPARKLE_VERSION}.tar.xz"
    curl -sL -o "${archive}" "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
    tar -xJf "${archive}" -C "${TOOLS_DIR}" bin
    rm -f "${archive}"
}

usage() {
    echo "Usage: $0 {generate_keys|sign_update|generate_appcast} [args...]" >&2
    exit 1
}

[ "$#" -ge 1 ] || usage
TOOL="$1"
shift

case "${TOOL}" in
    generate_keys|sign_update|generate_appcast)
        fetch_tools
        exec "${BIN_DIR}/${TOOL}" "$@"
        ;;
    *)
        usage
        ;;
esac
