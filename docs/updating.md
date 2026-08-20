# Auto-Updates & Clean Reinstalls

Adventurers Harness updates itself via [Sparkle](https://sparkle-project.org), the standard
macOS auto-update framework, rather than the old flow of downloading a DMG to `~/Downloads` and
leaving the user to drag it into `/Applications` by hand. Sparkle owns the security-sensitive
parts of that pipeline: verifying the update is signed by us, downloading it, atomically replacing
the running `.app` bundle in place, and relaunching. Nothing in this app hand-rolls any of that.

Separately, a small in-app **Duplicate Installs** scanner (Settings → General) finds and offers to
remove other copies of the app in `/Applications` — e.g. left behind by an old manual DMG install —
so updates don't quietly accumulate stale copies. It is intentionally scoped to `/Applications`
only; it never inspects or deletes anything in `~/Downloads`, `~/Desktop`, or other user folders,
and removed copies go to the Trash, never a permanent delete.

## One-time setup: the signing key

Sparkle verifies every update with an EdDSA (ed25519) signature before installing it — without a
valid signature, it refuses to install. This means an update channel needs exactly one signing
key, generated once and kept for the life of the app (rotating it later breaks auto-update for
everyone who already has an older version installed, since old versions were built expecting the
old public key).

1. Generate the keypair locally:
   ```bash
   ./scripts/sparkle_tools.sh generate_keys
   ```
   This stores the **private key** in your macOS Keychain and prints the **public key** to paste
   into `Info.plist` (this repo does that automatically — see below).

2. Export the private key so CI can use it (GitHub's macOS runners are ephemeral and don't have
   your Keychain):
   ```bash
   ./scripts/sparkle_tools.sh generate_keys -x /tmp/sparkle_private_key.pem
   ```
   Paste the contents of that file into a **repository secret** named `SPARKLE_PRIVATE_KEY`
   (Settings → Secrets and variables → Actions → New repository secret), then delete the local
   file. Never commit it.

3. Add the printed public key as a **repository variable** (not a secret — it's not sensitive)
   named `SPARKLE_PUBLIC_KEY`.

Until both of these are set, `scripts/package_app.sh` still builds the app (with a warning), but
Sparkle has no way to verify updates, so `checkForUpdates()` will find releases but refuse to
install them.

## How a release gets built and signed

`scripts/package_app.sh`:
- Builds the release binary, embeds `Sparkle.framework` (and its two XPC helper services) into
  `Contents/Frameworks`, and code-signs everything inside-out — nested XPC services and the
  framework's helper app first, then the framework, then the outer `.app` — rather than relying on
  `codesign --deep`, which is unreliable for bundles containing their own nested helper apps.
- Writes `SUFeedURL` and `SUPublicEDKey` into `Info.plist` from `$SPARKLE_FEED_URL` /
  `$SPARKLE_PUBLIC_KEY`.

`.github/workflows/build-macos-arm64.yml`, after packaging:
- Downloads the previous `appcast.xml` from the `latest` release (if any) so version history
  accumulates across builds instead of resetting every time.
- Runs `scripts/sparkle_tools.sh generate_appcast`, feeding `SPARKLE_PRIVATE_KEY` in over stdin
  (`--ed-key-file -`) — the key is never written to disk on the runner.
- Uploads the resulting signed `appcast.xml` — always to the `latest` release's assets, since
  that's the one fixed URL the app's `SUFeedURL` points at.

The app's `SUFeedURL` is
`https://github.com/4cecoder/adventurers-harness/releases/download/latest/appcast.xml` — a stable
URL regardless of version or channel.

## Release channels: alpha / beta / stable

Sparkle tells channels apart with a per-item `<sparkle:channel>` tag inside that single shared
feed — not with separate feed URLs — so `generate_appcast --channel <name>` is what tags each new
entry, and the client opts into extra channels via `SPUUpdaterDelegate.allowedChannels(for:)`
(implemented in `AppUpdateManager`). The default (untagged) channel is always included, so each
tier is additive:

| CI trigger | Channel | `allowedChannels` when selected |
| --- | --- | --- |
| Push to `master`/`main` | `alpha` | stable + beta + alpha |
| Tag `vX.Y.Z-beta.N` | `beta` | stable + beta |
| Tag `vX.Y.Z` | `stable` (untagged) | stable only |

The channel is picked in `.github/workflows/build-macos-arm64.yml`'s "Determine Release Channel"
step from `github.ref`, and the user picks which channels to receive in Settings → General →
Update Channel, persisted via `SettingsModel.updateChannel`.

Only stable tags set `make_latest: true` on the `latest` GitHub Release and only stable tags sync
the Homebrew formula/cask — alpha and beta builds publish their binaries and appcast entries, but
never become "the" latest release or reach Homebrew users.

To ship a beta: tag `vX.Y.Z-beta.N` and push it (`git tag v1.1.0-beta.1 && git push origin
v1.1.0-beta.1`). To ship stable: tag plain `vX.Y.Z`.

## What Sparkle does at runtime

`AppUpdateManager` (`Sources/GUI/AppUpdateManager.swift`) is a thin, app-branded facade: it starts
Sparkle's `SPUStandardUpdaterController` and mirrors `SPUUpdaterDelegate` callbacks into a simple
`status` enum so the existing status-bar badge and Settings pane can show "update available"
without re-implementing anything. The actual download, signature verification, install, and
relaunch consent UI are entirely Sparkle's own native, audited flow — this app only decides *when*
to ask Sparkle to check (on launch, from the menu, or from the status bar/Settings button).

## Known limitation: code signing identity

The app is currently ad-hoc signed (`codesign --sign -`), not signed with a real Apple Developer
ID or notarized. Sparkle's own signature check is independent of this and still verifies update
authenticity, but macOS Gatekeeper may still prompt on a fresh install of a downloaded, unsigned
app before Sparkle's self-update mechanism reduces friction on later automatic updates. Getting a
real Developer ID certificate and notarizing releases (`notarytool`) would remove this remaining
rough edge but requires a paid Apple Developer Program membership and is out of scope here.
