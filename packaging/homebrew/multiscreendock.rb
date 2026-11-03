# Personal-tap cask for the v1.2.0 GitHub release asset.
# sha256 is of MultiScreenDock-v1.2.0-macOS.zip (492,962 bytes), computed
# from the downloaded asset. Both slices inside are ad-hoc signed
# (CS_ADHOC, empty CMS signature, no Team ID, no notarization ticket),
# so homebrew/homebrew-cask will reject this until a Developer ID build
# is published. Recompute sha256 when that zip replaces the asset.
cask "multiscreendock" do
  version "1.2.0"
  sha256 "95ef7ecf5b2167b4ec68b0d08f7f4a3c506fd2dae9dfb2c507cd6b320b55d6ab"

  url "https://github.com/fgomsan/MultiScreenDock/releases/download/v#{version}/MultiScreenDock-v#{version}-macOS.zip"
  name "MultiScreenDock"
  desc "Synchronized Dock on every connected display"
  homepage "https://github.com/fgomsan/MultiScreenDock"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "MultiScreenDock.app"

  uninstall quit: "io.github.fgomsan.MultiScreenDock",
            launchctl: "io.github.fgomsan.multiscreendock",
            delete: "~/Library/LaunchAgents/io.github.fgomsan.multiscreendock.plist"

  zap trash: "~/Library/Preferences/io.github.fgomsan.MultiScreenDock.plist"

  caveats <<~EOS
    This build is ad-hoc signed and has no Apple notarization ticket.
    Gatekeeper blocks the quarantined app. After install, clear it once:

      xattr -dr com.apple.quarantine "/Applications/MultiScreenDock.app"

    Use ~/Applications instead when Homebrew installed it there.
    `brew install --cask --no-quarantine` skips the quarantine flag.
    Launch at Login stores an absolute path in
    ~/Library/LaunchAgents/io.github.fgomsan.multiscreendock.plist.
  EOS
end
