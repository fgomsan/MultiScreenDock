# Official Homebrew Cask for MultiScreenDock (Apple Developer ID signed & notarized).
cask "multiscreendock" do
  version "1.3.3"
  sha256 "d70e6ac395cb60718df1977e85a70d28693f95d88f3a6cf0183fee02e1772e86"

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
