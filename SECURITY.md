# Security Policy

## Reporting a Vulnerability

Please report security vulnerabilities privately through
[GitHub Security Advisories](https://github.com/4cecoder/adventurers-harness/security/advisories/new)
rather than opening a public issue — this lets us fix the problem before details are public.

Include:
- A description of the vulnerability and its potential impact.
- Steps to reproduce (a minimal example, if possible).
- The affected version/commit.

We'll acknowledge reports as soon as we can and follow up once a fix is available.

## Scope

Adventurers Harness executes shell commands, edits files, and calls out to cloud LLM providers on
the user's behalf. Reports about any of the following are especially relevant:
- Tool execution bypassing the approval flow (`ToolApprovalManager` / `Sources/GUI/ThreadViewModel.swift`).
- Sandbox escapes from `DarwinSandbox`'s generated Seatbelt profiles.
- Dangerous-command detection bypasses (`DangerousCommandDetector`).
- Auto-update integrity issues — a forged or unsigned update being accepted (see `docs/updating.md`
  for how Sparkle's EdDSA signing is supposed to prevent this).
- Credential/API-key handling and storage.

## Supported Versions

Only the latest `stable` release receives security fixes. See `docs/updating.md` for how release
channels (stable/beta/alpha) work.
