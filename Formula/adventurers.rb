# Formula/adventurers.rb
#
# Homebrew formula for Adventurers Harness (macOS Native Coding Agent Harness).
# Fetches the prebuilt Adventurers-macOS-arm64.tar.gz asset from GitHub Releases.
#
# To install:
#   brew tap 4cecoder/adventurers https://github.com/4cecoder/adventurers-harness
#   brew install adventurers
#
# Or directly from repo:
#   brew install --formula Formula/adventurers.rb

class Adventurers < Formula
  desc "Next-Gen macOS Native Coding Agent Harness with Deterministic Gate Certification"
  homepage "https://github.com/4cecoder/adventurers-harness"
  version "1.0.0"

  if Hardware::CPU.arm?
    url "https://github.com/4cecoder/adventurers-harness/releases/download/v1.0.0/Adventurers-macOS-arm64.tar.gz"
    sha256 "bf37584c4fc6a8b0cbd68681707cbdfb52fac1be14727ab1343f272a3944d810"
  else
    odie "Adventurers Harness requires Apple Silicon (arm64) macOS."
  end

  depends_on :macos => :sequoia

  def install
    # Install the full .app bundle into libexec to preserve bundle structure
    libexec.install "Adventurers.app"

    # Expose a CLI launcher wrapper on PATH
    (bin/"adventurers").write <<~SH
      #!/usr/bin/env bash
      exec "#{libexec}/Adventurers.app/Contents/MacOS/Adventurers" "$@"
    SH
    (bin/"adventurers").chmod 0755
  end

  def caveats
    <<~EOS
      Adventurers Harness is ad-hoc signed for Apple Silicon.
      If macOS Gatekeeper prevents execution on first launch:
        xattr -cr #{libexec}/Adventurers.app

      Launch from CLI:
        adventurers
    EOS
  end

  test do
    assert_predicate bin/"adventurers", :exist?
  end
end
