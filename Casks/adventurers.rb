cask "adventurers" do
  version "1.0.0"
  sha256 "d715a109bea3651b3b32274e72be72141c85fa1322b7dec59a381f9ad964b540"

  url "https://github.com/4cecoder/adventurers-harness/releases/download/v#{version}/Adventurers-macOS-arm64.dmg"
  name "Adventurers Harness"
  desc "Next-Gen macOS Native Coding Agent Harness with Deterministic Gate Certification"
  homepage "https://github.com/4cecoder/adventurers-harness"

  depends_on macos: ">= :sequoia"
  depends_on arch: :arm64

  app "Adventurers.app"
  binary "#{appdir}/Adventurers.app/Contents/MacOS/Adventurers", target: "adventurers"

  zap trash: [
    "~/.adventurers",
    "~/Library/Application Support/Adventurers",
    "~/Library/Preferences/com.bytecats.adventurers.plist",
    "~/Library/Saved Application State/com.bytecats.adventurers.savedState",
  ]
end
