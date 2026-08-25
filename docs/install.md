# Build & Install Guide

Everything from source checkout to a working app in `/Applications` is standardized around three scripts:

| Script | What it produces | When to use it |
|---|---|---|
| `scripts/run_dev_app.sh` | Debug build wrapped in `.build/dev/AdventurersDev.app`, then relaunches | Daily development |
| `scripts/package_app.sh` | Release build → `dist/Adventurers.app` + DMG/ZIP/TAR.GZ + SHA256 checksums | Cutting a local release |
| `scripts/install_local.sh` | Copies `dist/Adventurers.app` to `/Applications/Adventurers.app` and launches | Installing the packaged app |

> 💡 Voice dictation runs **fully on-device** via WhisperKit — no Python, no cloud calls. See [Voice Dictation Notes](#voice-dictation-notes) below.

---

## Prerequisites

- **macOS 15 (Sequoia) or later.** The release build targets the `arm64-apple-macosx15.0` triple.
- **Apple Silicon Mac (recommended).** All release artifacts are ARM64-only; on-device inference (dictation, MLX features) performs best on Apple Silicon.
- **Xcode Command Line Tools with the Swift 6.2 toolchain:**

```bash
xcode-select --install        # first-time setup
swift --version               # expect Swift 6.2.x
```

That's it — the project builds with SwiftPM alone; no Xcode IDE, Python, or Homebrew packages are required to build or run.

---

## ⚡ Quick Dev Loop

For day-to-day development, always launch through the wrapper script:

```bash
./scripts/run_dev_app.sh
```

What it does:

1. Builds the **debug** configuration.
2. Wraps the binary in a proper `.app` bundle at `.build/dev/AdventurersDev.app`, including an `Info.plist` with the `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` strings.
3. Ad-hoc codesigns the bundle.
4. Relaunches it, killing any previous instance.

### Why a raw `.build/debug` binary breaks mic permissions

If you run the bare executable directly (`swift run` or executing `.build/debug/Adventurers`), microphone access fails even though the code is correct:

- **No bundle = no usage descriptions.** macOS TCC refuses to grant microphone or speech-recognition access to an app whose `Info.plist` lacks the required `NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription` strings. A raw SwiftPM binary has no `Info.plist` at all.
- **No bundle = no stable identity.** Permission grants are attributed to a signed bundle identity (`CFBundleIdentifier`). A loose binary has none, and its ad-hoc signature changes on every rebuild, so TCC has nothing stable to attach a grant to — prompts never appear or are silently denied.

The `.app` wrapper fixes both problems: the bundle provides the usage strings and a stable signed identity that TCC can track. **Rule of thumb: test anything microphone-related through `run_dev_app.sh`, never through `swift run`.**

---

## 📦 Local Install

Two steps: package a release, then install it system-wide.

```bash
./scripts/package_app.sh      # release build → dist/
./scripts/install_local.sh    # dist/Adventurers.app → /Applications → launch
```

### Step 1: Package (`package_app.sh`)

Optionally pass a version (defaults to `1.0.0`):

```bash
./scripts/package_app.sh 1.2.0
```

The script:

- Builds a release binary for `arm64-apple-macos15.0` and verifies the architecture.
- Assembles `dist/Adventurers.app`: executable, icon, `Info.plist`, and the embedded `Sparkle.framework` (with the app-bundle rpath added).
- Ad-hoc codesigns inside-out (Sparkle's XPC services/helper first, then the framework, then the app with `entitlements.plist` granting audio-input, microphone, and speech recognition) and verifies with `codesign --verify --deep --strict`.
- Produces the DMG, ZIP, TAR.GZ archives and `.sha256` checksums in `dist/` (see [Build Artifacts](#build-artifacts)).

> ℹ️ If you see a `SPARKLE_PUBLIC_KEY is not set` warning, see [Troubleshooting](#troubleshooting).

### Step 2: Install (`install_local.sh`)

```bash
./scripts/install_local.sh
```

The script:

1. Quits any running Adventurers instance.
2. `ditto`-installs `dist/Adventurers.app` → `/Applications/Adventurers.app` (preserves signatures and metadata exactly).
3. Strips the `com.apple.quarantine` extended attribute.
4. Verifies the code signature.
5. Launches the freshly installed app.

Flags:

| Flag | Effect |
|---|---|
| `--no-launch` | Install but don't start the app. |
| `--dry-run` | Print every planned action without changing anything. |
| `APP_PATH` (optional) | Install a different bundle instead of `dist/Adventurers.app`, e.g. `./scripts/install_local.sh ~/Downloads/Adventurers.app`. |

### Quarantine & Gatekeeper (ad-hoc signing)

The app is **ad-hoc signed** — it has no Developer ID certificate and is not notarized. `install_local.sh` handles this for local installs by stripping quarantine, so launching from `/Applications` just works.

You only hit Gatekeeper when moving a build to another Mac (or opening the app directly out of a DMG/archive). If macOS reports *"Adventurers cannot be opened because Apple cannot check it for malicious software"* or claims the app is *damaged*:

- **Right-click the app → Open → Open** (approve once; subsequent launches are unaffected), or
- Remove the quarantine flag manually:

```bash
xattr -dr com.apple.quarantine /Applications/Adventurers.app
```

Only bypass Gatekeeper on apps you built yourself or otherwise trust.

---

## 🗂️ Build Artifacts

After `package_app.sh`, `dist/` contains:

| Artifact | Description |
|---|---|
| `Adventurers.app` | Signed macOS application bundle (Sparkle.framework embedded). |
| `Adventurers-macOS-arm64.dmg` | Disk image installer for end users. |
| `Adventurers-macOS-arm64.zip` | Distribution archive. |
| `Adventurers-macOS-arm64.tar.gz` | Tarball used for Homebrew distribution. |
| `*.sha256` | One SHA256 checksum file per archive. |

Verify a download against its checksum:

```bash
cd dist
shasum -a 256 -c Adventurers-macOS-arm64.dmg.sha256
```

---

## 🎙️ Voice Dictation Notes

Dictation transcribes your voice **entirely on your Mac** using WhisperKit:

- **First use:** the `openai_whisper-base` model (~150 MB) downloads automatically the first time you dictate. Have a network connection for that first session.
- **Every use after that:** fully offline. No audio, transcripts, or metadata ever leave your machine — there is no cloud component and no Python dependency.
- **Permissions:** approve the microphone (and speech-recognition, if prompted) dialogs on first use. See [Troubleshooting](#troubleshooting) if the prompt doesn't appear.
- **Requirements:** macOS 15+, Apple Silicon recommended.

---

## 🔧 Troubleshooting

### Microphone permission missing, denied, or the prompt never reappears

macOS remembers permission decisions per bundle ID — including accidental "Don't Allow" clicks. Reset the stored decision and relaunch:

```bash
tccutil reset Microphone com.bytecats.adventurers
```

Then restart the app and approve the prompt. If dictation still doesn't engage, also reset the speech-recognition entry:

```bash
tccutil reset SpeechRecognition com.bytecats.adventurers
```

> ℹ️ The dev bundle (`.build/dev/AdventurersDev.app`) and the installed app hold **separate** TCC entries — approving one doesn't carry over to the other. Additionally, because dev builds are ad-hoc signed, the signature changes on every rebuild; if the dev bundle starts re-prompting, simply approve it again (or reset with `tccutil` as above).

### `⚠️ SPARKLE_PUBLIC_KEY is not set` during packaging

This warning means `package_app.sh` baked an **empty `SUPublicEDKey`** into the app's `Info.plist`. Consequences: the app cannot verify the EdDSA signatures on Sparkle update-feed releases, so in-app auto-updates can't validate that an update is authentic. Packaging itself succeeds; the app is only missing update-signature verification.

Fix (once per machine):

```bash
./scripts/sparkle_tools.sh generate_keys       # prints the public key, stores the private key
export SPARKLE_PUBLIC_KEY="<public key from above>"
./scripts/package_app.sh
```

The public key is safe to commit and share — only the matching private key (used by CI to sign each release) must stay secret. Details: [docs/updating.md](updating.md).

---

## Related Docs

- [Getting Started](getting-started.md) — credentials, execution modes, and your first task
- [Auto-Updates (Sparkle)](updating.md) — key generation and the appcast feed
