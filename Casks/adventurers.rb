cask "adventurers" do
  version "1.0.0"
  sha256 "8ae3e76db43a8ccdd276aa6858b012e36650c349e93370ef008cb2b74bd6c814"

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
