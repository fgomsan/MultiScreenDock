# Official Homebrew Cask for MultiScreenDock (Apple Developer ID signed & notarized).
cask "multiscreendock" do
  version "1.4.0"
  sha256 "05c2a2f5670db33b910b3270617be7e39cf51d3f0d4a4974d1e1923118bd46d3"

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
