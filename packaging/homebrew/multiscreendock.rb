# Official Homebrew Cask for MultiScreenDock (Apple Developer ID signed & notarized).
cask "multiscreendock" do
  version "1.4.2"
  sha256 "c4ebce1917bd0ed69ddc91e99e1a706a2d68d41f1b1bae8440f068dbc31e7235"

  url "https://github.com/fgomsan/MultiScreenDock/releases/download/v#{version}/MultiScreenDock-v#{version}-macOS.zip"
  name "MultiScreenDock"
  desc "Synchronized macOS Dock on every connected display, including stacked rows"
  homepage "https://multiscreendock.fgomsan.here.now/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "MultiScreenDock.app"

  uninstall login_item: "MultiScreenDock",
            quit: "io.github.fgomsan.MultiScreenDock"

  zap trash: "~/Library/Preferences/io.github.fgomsan.MultiScreenDock.plist"
end
