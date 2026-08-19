# Crash Logs & Native Diagnostics in Adventurers Harness

Adventurers Harness provides **fail-closed native crash diagnostics**, thread callstack capture, activity breadcrumbs, and Apple DiagnosticReport integration.

---

## 1. Crash Log Storage Locations

| Artifact | Location | Format | Description |
| :--- | :--- | :--- | :--- |
| **Crash Reports (JSON)** | `~/.adventurers/crashes/crash_<timestamp>_<id>.json` | Structured JSON | Machine-readable signal, exception, active model, and callstack. |
| **Crash Reports (Log)** | `~/.adventurers/crashes/crash_<timestamp>_<id>.log` | Formatted Plaintext | Instant copy-paste diagnostic summary with full stack frames. |
| **Session Event Logs** | `~/.adventurers/sessions/{threadID}.jsonl` | Append-only JSONL | Streaming trace of turns, thoughts, tool calls, and gate passes. |
| **macOS DiagnosticReports**| `~/Library/Logs/DiagnosticReports/Adventurers_*.ips` | Apple System Report | OS-level Mach kernel crash dumps. |

---

## 2. Captured Diagnostic Metadata

Every crash dump automatically records:
- **Timestamp & Architecture** (e.g. `arm64 Apple Silicon`, OS build).
- **Signal / Exception Name** (e.g. `SIGSEGV`, `SIGBUS`, `SIGABRT`, `NSInvalidArgumentException`).
- **Reason & Faulting Function**.
- **Active Execution Strategy** (`Subscription`, `Pay-As-You-Go`, or `Meta Harness`).
- **Active Model & Thread ID**.
- **Memory RSS Consumption** (via POSIX `getrusage`).
- **Recent Activity Breadcrumbs** (last 40 user actions, model selections, and gate transitions).
- **Full Callstack Backtrace** with symbol demangling.

---

## 3. UI Diagnostics Viewer

Open **Settings (⌘,) $\rightarrow$ Crash Logs & Diagnostics** to:
1. View a list of all recorded crash events.
2. 1-click **"Copy Full Report"** to copy the backtrace and breadcrumbs to your clipboard.
3. 1-click **"Open Crash Folder"** or **"Open Session JSONL Logs"** in macOS Finder.
4. Inspect recent in-flight activity breadcrumbs.
