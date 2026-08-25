#!/usr/bin/env bash
# Build-lock janitor: prevents silent queueing behind orphaned SwiftPM builds.
#
# Why this exists: SwiftPM's .build lock is advisory and waits indefinitely ("Another instance
# of SwiftPM (PID: N) is already running..."). When a wrapper script is aborted (timeout/Ctrl-C
# of a piped invocation), its child `swift-build` survives as an orphan and keeps holding the
# lock — every later build then stalls with no diagnosis. This script:
#   1. Finds SwiftPM processes scoped to THIS repo (cwd match — never touches other projects).
#   2. Waits up to WAIT_SECONDS for them to finish naturally (they may be legitimate).
#   3. Escalates SIGTERM -> SIGKILL on stragglers.
#   4. Clears maintenance.lock debris left by killed fetches (only when no SwiftPM remains).
#
# Usage: wait_build_lock.sh [WAIT_SECONDS]   (default 600)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WAIT_SECONDS="${1:-600}"
POLL_INTERVAL=5

# SwiftPM processes (planner + compiler children) whose current working directory is this repo.
repo_swiftpm_pids() {
    local pids=""
    for pid in $(pgrep -f "swift-build|swift-package|swift-frontend" 2>/dev/null || true); do
        local cwd
        cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
        if [ "${cwd}" = "${ROOT_DIR}" ]; then
            pids+="${pid} "
        fi
    done
    echo "${pids}"
}

holders="$(repo_swiftpm_pids)"
if [ -z "${holders// }" ]; then
    exit 0
fi

echo "⏳ SwiftPM already active in this repo (PID(s): ${holders% }). Waiting up to ${WAIT_SECONDS}s..."
deadline=$(( $(date +%s) + WAIT_SECONDS ))
while :; do
    sleep "${POLL_INTERVAL}"
    holders="$(repo_swiftpm_pids)"
    [ -z "${holders// }" ] && { echo "✔ Lock released."; exit 0; }
    [ "$(date +%s)" -ge "${deadline}" ] && break
done

echo "⚠️  Orphaned SwiftPM build still holding the .build lock after ${WAIT_SECONDS}s — clearing: ${holders% }"
kill ${holders} 2>/dev/null || true
sleep 10
holders="$(repo_swiftpm_pids)"
if [ -n "${holders// }" ]; then
    echo "🔪 Force-killing: ${holders% }"
    kill -9 ${holders} 2>/dev/null || true
    sleep 2
fi

# Hard-killed fetches leave dangling maintenance.lock files which make subsequent resolves skip
# caches ("skipping cache due to an error ... maintenance.lock doesn't exist"). Sweep them only
# when absolutely no SwiftPM process is left anywhere.
if [ -z "$(pgrep -f 'swift-build|swift-package|swift-frontend' 2>/dev/null || true)" ]; then
    find "${ROOT_DIR}/.build/repositories" -name 'maintenance.lock' -delete 2>/dev/null || true
    find "$HOME/Library/Caches/org.swift.swiftpm/repositories" -name 'maintenance.lock' -delete 2>/dev/null || true
fi

echo "✔ Lock cleared. Re-running the build."
