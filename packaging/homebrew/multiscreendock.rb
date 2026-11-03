# Official Homebrew Cask for MultiScreenDock (Apple Developer ID signed & notarized).
cask "multiscreendock" do
  version "1.3.2"
  sha256 "eefc6551dc2d02b9b133d14fb1333b9e3748165f4d07a7ce46140eab56184ae2"

  url "https://github.com/fgomsan/MultiScreenDock/releases/download/v#{version}/MultiScreenDock-v#{version}-macOS.zip",
      verified: "github.com/fgomsan/MultiScreenDock/"
  name "MultiScreenDock"
  desc "Synchronized macOS Dock on every connected display, including stacked rows"
  homepage "https://multiscreendock.fgomsan.here.now/"

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
end
