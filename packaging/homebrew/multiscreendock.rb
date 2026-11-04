# Official Homebrew Cask for MultiScreenDock (Apple Developer ID signed & notarized).
cask "multiscreendock" do
  version "1.3.5"
  sha256 "cc79e590f2eb5cda2c1f94bf257564b0bf98554f7c31cd8255612948c6c2fbc2"

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
