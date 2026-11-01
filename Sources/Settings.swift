import Cocoa

final class DockSettings {
    static let shared = DockSettings()

    static let bundleIdentifier = "io.github.fgomsan.MultiScreenDock"
    static let launchAgentLabel = "io.github.fgomsan.multiscreendock"

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let iconSize = "iconSize"
        static let avoidNativeDockOverlap = "avoidNativeDockOverlap"
        static let showOverFullScreen = "showOverFullScreen"
        static let hoverMagnification = "hoverMagnification"
        static let showRunningUnpinned = "showRunningUnpinned"
        static let bottomMargin = "bottomMargin"
        static let disabledScreens = "disabledScreens"
    }

    var onChange: (() -> Void)?

    private init() {
        let initialTileSize = Self.readNativeTileSize() ?? 36.0
        defaults.register(defaults: [
            Keys.iconSize: initialTileSize,
            Keys.avoidNativeDockOverlap: true,
            Keys.showOverFullScreen: true,
            Keys.hoverMagnification: true,
            Keys.showRunningUnpinned: true,
            Keys.bottomMargin: 6.0,
            Keys.disabledScreens: [String]()
        ])
    }

    private static func readNativeTileSize() -> Double? {
        guard let appleDock = UserDefaults(suiteName: "com.apple.dock") else { return nil }
        let val = appleDock.double(forKey: "tilesize")
        return (val >= 20 && val <= 80) ? val : nil
    }

    var iconSize: CGFloat {
        get { CGFloat(defaults.double(forKey: Keys.iconSize)) }
        set {
            defaults.set(Double(newValue), forKey: Keys.iconSize)
            onChange?()
        }
    }

    var avoidNativeDockOverlap: Bool {
        get { defaults.bool(forKey: Keys.avoidNativeDockOverlap) }
        set {
            defaults.set(newValue, forKey: Keys.avoidNativeDockOverlap)
            onChange?()
        }
    }

    var showOverFullScreen: Bool {
        get { defaults.bool(forKey: Keys.showOverFullScreen) }
        set {
            defaults.set(newValue, forKey: Keys.showOverFullScreen)
            onChange?()
        }
    }

    var hoverMagnification: Bool {
        get { defaults.bool(forKey: Keys.hoverMagnification) }
        set {
            defaults.set(newValue, forKey: Keys.hoverMagnification)
            onChange?()
        }
    }

    var showRunningUnpinned: Bool {
        get { defaults.bool(forKey: Keys.showRunningUnpinned) }
        set {
            defaults.set(newValue, forKey: Keys.showRunningUnpinned)
            onChange?()
        }
    }

    var bottomMargin: CGFloat {
        get { CGFloat(defaults.double(forKey: Keys.bottomMargin)) }
        set {
            defaults.set(Double(newValue), forKey: Keys.bottomMargin)
            onChange?()
        }
    }

    var disabledScreens: Set<String> {
        get { Set(defaults.stringArray(forKey: Keys.disabledScreens) ?? []) }
        set {
            defaults.set(Array(newValue), forKey: Keys.disabledScreens)
            onChange?()
        }
    }

    func screenKey(for screen: NSScreen) -> String {
        if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "\(screen.localizedName)#\(num.uint32Value)"
        }
        return screen.localizedName
    }

    func isScreenEnabled(_ screen: NSScreen) -> Bool {
        !disabledScreens.contains(screenKey(for: screen))
    }

    func toggleScreen(_ screen: NSScreen) {
        let key = screenKey(for: screen)
        var current = disabledScreens
        if current.contains(key) {
            current.remove(key)
        } else {
            current.insert(key)
        }
        disabledScreens = current
    }

    // MARK: - Native Apple Dock Autohide Control

    var isNativeDockAutohideEnabled: Bool {
        let appleDock = UserDefaults(suiteName: "com.apple.dock")
        return appleDock?.bool(forKey: "autohide") ?? false
    }

    func setNativeDockAutohide(_ enabled: Bool) {
        let scriptSource = "tell application \"System Events\" to set autohide of dock preferences to \(enabled ? "true" : "false")"
        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if error == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.onChange?()
                }
                return
            }
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        proc.arguments = ["write", "com.apple.dock", "autohide", "-bool", enabled ? "true" : "false"]
        try? proc.run()
        proc.waitUntilExit()

        let killProc = Process()
        killProc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killProc.arguments = ["Dock"]
        try? killProc.run()
    }

    // MARK: - Launch at Login (LaunchAgent)

    private var launchAgentURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(Self.launchAgentLabel).plist")
    }

    var launchAtLogin: Bool {
        get { FileManager.default.fileExists(atPath: launchAgentURL.path) }
        set {
            let fm = FileManager.default
            if newValue {
                guard let execPath = Bundle.main.executablePath else { return }
                let plist: [String: Any] = [
                    "Label": Self.launchAgentLabel,
                    "ProgramArguments": [execPath],
                    "RunAtLoad": true,
                    "KeepAlive": false,
                    "ProcessType": "Interactive"
                ]
                try? fm.createDirectory(at: launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                    try? data.write(to: launchAgentURL)
                }
            } else {
                try? fm.removeItem(at: launchAgentURL)
            }
        }
    }
}
