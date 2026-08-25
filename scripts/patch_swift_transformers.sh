#!/usr/bin/env bash
# Patches the swift-transformers dependency (via SwiftPM edit mode) to work around a
# Swift 6.2.3-RELEASE toolchain ICE under -O: SIL lifetime verifier crash (OwnershipModelEliminator)
# in Trie.swift's lazy existential iterator — upstream: swiftlang/swift#85729.
# Idempotent: safe to run before every release build. Edit copy lives in .tools/ (gitignored).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
EDIT_DIR="${ROOT_DIR}/.tools/swift-transformers-edit"
PATCH_FILE="${ROOT_DIR}/scripts/patches/swift-transformers-6.2.3-ice.patch"
CHECKOUT_LINK="${ROOT_DIR}/.build/checkouts/swift-transformers"

if [ ! -f "${PATCH_FILE}" ]; then
    echo "❌ Patch file missing: ${PATCH_FILE}"
    exit 1
fi

# Locate the REGISTERED edit checkout (symlink in checkouts, or path recorded in
# workspace-state.json). A bare .tools copy alone proves nothing — its registration may have
# been lost with a wiped .build, in which case SwiftPM would compile pristine (unpatched) code.
registered_edit="$( [ -L "${CHECKOUT_LINK}" ] && (cd "$(dirname "${CHECKOUT_LINK}")" && readlink "${CHECKOUT_LINK}") || true )"
if [ -z "${registered_edit}" ]; then
    registered_edit="$(python3 - <<'PY' 2>/dev/null || true
import json, os
try:
    s = json.load(open('.build/workspace-state.json'))
    for r in s.get('object', {}).get('dependencies', []):
        st = r.get('state', {})
        if isinstance(st, dict) and st.get('name') == 'edited' and r['packageRef']['identity'] == 'swift-transformers':
            p = st['path']
            if os.path.isdir(p):
                print(p)
except Exception:
    pass
PY
)"
fi

already_patched() {
    [ -n "$1" ] && grep -q "OwnershipModelEliminator" "$1/Sources/Tokenizers/Trie.swift" 2>/dev/null
}

if [ -n "${registered_edit}" ] && already_patched "${registered_edit}"; then
    echo "✔ swift-transformers already patched (${registered_edit})"
    exit 0
fi

apply_patch() {
    local dir="$1"
    if git -C "${dir}" apply --check "${PATCH_FILE}" 2>/dev/null; then
        git -C "${dir}" apply "${PATCH_FILE}"
    elif git -C "${dir}" apply --check --3way "${PATCH_FILE}" 2>/dev/null; then
        echo "ℹ️  Upstream Trie.swift shifted; using 3-way merge."
        git -C "${dir}" apply --3way "${PATCH_FILE}"
    elif ! grep -q "lazy var iterator = text.makeIterator()" "${dir}/Sources/Tokenizers/Trie.swift"; then
        echo "✔ Upstream no longer matches the crashing pattern; skipping patch."
        return 2
    else
        echo "❌ Patch does not apply to current swift-transformers checkout. Update scripts/patches/."
        return 1
    fi
    echo "✔ Patched ${dir}/Sources/Tokenizers/Trie.swift"
}

cd "${ROOT_DIR}"

if [ -n "${registered_edit}" ] && [ -d "${registered_edit}" ]; then
    # Already in edit mode somewhere — patch that checkout in place.
    apply_patch "${registered_edit}"
    exit $?
fi

echo "🔧 Applying swift-transformers ICE workaround (Swift 6.2.3 -O, swiftlang/swift#85729)..."
mkdir -p "${ROOT_DIR}/.tools"
rm -rf "${EDIT_DIR}"
swift package edit swift-transformers --path "${EDIT_DIR}" >/dev/null
if apply_patch "${EDIT_DIR}"; then
    exit 0
else
    # Bad patch against an updated dependency — revert the edit we just created.
    git -C "${EDIT_DIR}" checkout -- . 2>/dev/null || true
    exit 1
fi
