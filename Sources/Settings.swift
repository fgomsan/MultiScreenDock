import Cocoa
import ColorSync
import ServiceManagement

enum DockVisibilityMode: String {
    case alwaysVisible = "alwaysVisible"
    case autoHide = "autoHide"
}

enum FolderStackStylePreference: String, CaseIterable {
    case dockDefault = "dockDefault"
    case fan = "fan"
    case grid = "grid"
    case list = "list"
}

enum AppLanguage: String, CaseIterable {
    case system = "system"
    case en = "en"
    case es = "es"
    case fr = "fr"
    case de = "de"
    case pt = "pt"
    case it = "it"
    case ja = "ja"
    case zhHans = "zh-Hans"

    var nativeDisplayName: String {
        switch self {
        case .system: return ""
        case .en: return "English"
        case .es: return "Español"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .pt: return "Português"
        case .it: return "Italiano"
        case .ja: return "日本語"
        case .zhHans: return "简体中文"
        }
    }
}

enum AutoHideResponsiveness: String {
    case fast = "fast"
    case balanced = "balanced"
    case relaxed = "relaxed"

    var bottomEdgeDwell: TimeInterval {
        switch self {
        case .fast: return 0.04
        case .balanced: return 0.08
        case .relaxed: return 0.16
        }
    }

    /// Dwell slightly longer when the bottom edge is shared with a lower monitor so fast vertical crossings never trigger the upper Dock.
    var stackedEdgeDwell: TimeInterval {
        switch self {
        case .fast: return 0.09
        case .balanced: return 0.15
        case .relaxed: return 0.25
        }
    }

    var hideDelay: TimeInterval {
        switch self {
        case .fast: return 0.22
        case .balanced: return 0.32
        case .relaxed: return 0.45
        }
    }
}

struct ScreenIdentityDescriptor: Equatable {
    let index: Int
    let baseKey: String
    let originX: Int
    let originY: Int
    let unitNumber: UInt32
    let displayID: CGDirectDisplayID
}

final class DockSettings {
    static let shared = DockSettings()

    static let bundleIdentifier = "io.github.fgomsan.MultiScreenDock"
    static let launchAgentLabel = "io.github.fgomsan.multiscreendock"

    private let defaults: UserDefaults

    private enum Keys {
        static let visibilityMode = "visibilityMode"
        static let responsiveness = "responsiveness"
        static let showHiddenHintPill = "showHiddenHintPill"
        static let skipPrimaryDisplay = "skipPrimaryDisplay"
        static let iconSize = "iconSize"
        static let avoidNativeDockOverlap = "avoidNativeDockOverlap"
        static let showOverFullScreen = "showOverFullScreen"
        static let hoverMagnification = "hoverMagnification"
        static let showRunningUnpinned = "showRunningUnpinned"
        static let bottomMargin = "bottomMargin"
        static let disabledScreens = "disabledScreens"
        static let appLanguage = "appLanguage"
        static let autoCheckUpdates = "autoCheckUpdates"
        static let lastUpdateCheckTimestamp = "lastUpdateCheckTimestamp"
        static let folderStackStyle = "folderStackStyle"
    }

    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let initialTileSize = Self.readNativeTileSize() ?? 36.0
        defaults.register(defaults: [
            Keys.visibilityMode: DockVisibilityMode.autoHide.rawValue,
            Keys.responsiveness: AutoHideResponsiveness.balanced.rawValue,
            Keys.showHiddenHintPill: true,
            Keys.skipPrimaryDisplay: true,
            Keys.iconSize: initialTileSize,
            Keys.avoidNativeDockOverlap: true,
            Keys.showOverFullScreen: true,
            Keys.hoverMagnification: true,
            Keys.showRunningUnpinned: true,
            Keys.bottomMargin: 6.0,
            Keys.disabledScreens: [String](),
            Keys.appLanguage: AppLanguage.system.rawValue,
            Keys.autoCheckUpdates: true,
            Keys.lastUpdateCheckTimestamp: 0.0,
            Keys.folderStackStyle: FolderStackStylePreference.dockDefault.rawValue
        ])
    }

    static func readNativeTileSize() -> Double? {
        guard let appleDock = UserDefaults(suiteName: "com.apple.dock") else { return nil }
        let val = appleDock.double(forKey: "tilesize")
        return (val >= 20 && val <= 80) ? val : nil
    }

    var visibilityMode: DockVisibilityMode {
        get {
            guard let raw = defaults.string(forKey: Keys.visibilityMode),
                  let mode = DockVisibilityMode(rawValue: raw) else {
                return .autoHide
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.visibilityMode)
            onChange?()
        }
    }

    var responsiveness: AutoHideResponsiveness {
        get {
            guard let raw = defaults.string(forKey: Keys.responsiveness),
                  let val = AutoHideResponsiveness(rawValue: raw) else {
                return .balanced
            }
            return val
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.responsiveness)
            onChange?()
        }
    }

    var showHiddenHintPill: Bool {
        get { defaults.bool(forKey: Keys.showHiddenHintPill) }
        set {
            defaults.set(newValue, forKey: Keys.showHiddenHintPill)
            onChange?()
        }
    }

    var skipPrimaryDisplay: Bool {
        get { defaults.bool(forKey: Keys.skipPrimaryDisplay) }
        set {
            defaults.set(newValue, forKey: Keys.skipPrimaryDisplay)
            onChange?()
        }
    }

    var iconSize: CGFloat {
        get {
            let v = defaults.double(forKey: Keys.iconSize)
            return (v >= 20 && v <= 80) ? CGFloat(v) : CGFloat(Self.readNativeTileSize() ?? 36.0)
        }
        set {
            let clamped = min(max(Double(newValue), 20.0), 80.0)
            defaults.set(clamped, forKey: Keys.iconSize)
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
        get {
            guard defaults.object(forKey: Keys.bottomMargin) != nil else { return 6.0 }
            let v = defaults.double(forKey: Keys.bottomMargin)
            return (v >= 0 && v <= 40) ? CGFloat(v) : 6.0
        }
        set {
            let clamped = min(max(Double(newValue), 0.0), 40.0)
            defaults.set(clamped, forKey: Keys.bottomMargin)
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

    var appLanguage: AppLanguage {
        get {
            guard let raw = defaults.string(forKey: Keys.appLanguage),
                  let lang = AppLanguage(rawValue: raw) else {
                return .system
            }
            return lang
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.appLanguage)
            onChange?()
        }
    }

    var autoCheckUpdates: Bool {
        get { defaults.bool(forKey: Keys.autoCheckUpdates) }
        set {
            defaults.set(newValue, forKey: Keys.autoCheckUpdates)
            onChange?()
        }
    }

    var lastUpdateCheckTimestamp: TimeInterval {
        get { defaults.double(forKey: Keys.lastUpdateCheckTimestamp) }
        set { defaults.set(newValue, forKey: Keys.lastUpdateCheckTimestamp) }
    }

    var folderStackStyle: FolderStackStylePreference {
        get {
            guard let raw = defaults.string(forKey: Keys.folderStackStyle),
                  let val = FolderStackStylePreference(rawValue: raw) else {
                return .dockDefault
            }
            return val
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.folderStackStyle)
            onChange?()
        }
    }

    func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(num.uint32Value)
    }

    private func legacyScreenKey(for screen: NSScreen) -> String {
        if let id = displayID(for: screen) {
            return "\(screen.localizedName)#\(id)"
        }
        return screen.localizedName
    }

    /// Disambiguates two identical monitors (which may share the same EDID UUID or vendor/model/0-serial)
    /// across in-memory panel/timer dictionaries by suffixing the active CGDirectDisplayID.
    static func composeRuntimeScreenKey(persistentKey: String, displayID: CGDirectDisplayID?) -> String {
        guard let id = displayID else { return persistentKey }
        return "\(persistentKey)#\(id)"
    }

    /// Resolves persistent preference keys across connected screens.
    /// Single-instance hardware UUIDs stay untouched (`uuid:...`), preserving position-independence.
    /// When 2+ identical monitors share the exact same hardware `baseKey` (e.g., cloned EDID or MST hub),
    /// they are deterministically disambiguated by arrangement slot (`@slot:1`, `@slot:2`, ...) ordered by
    /// `(originX, originY, unitNumber, displayID)` so each twin monitor can be toggled independently across reboots.
    static func resolvePersistentScreenKeys(for descriptors: [ScreenIdentityDescriptor]) -> [String] {
        guard !descriptors.isEmpty else { return [] }
        var countsByBase: [String: Int] = [:]
        for d in descriptors {
            countsByBase[d.baseKey, default: 0] += 1
        }

        var resolved = descriptors.map { $0.baseKey }
        for (baseKey, count) in countsByBase where count > 1 {
            let group = descriptors.filter { $0.baseKey == baseKey }.sorted { a, b in
                if a.originX != b.originX { return a.originX < b.originX }
                if a.originY != b.originY { return a.originY < b.originY }
                if a.unitNumber != b.unitNumber { return a.unitNumber < b.unitNumber }
                if a.displayID != b.displayID { return a.displayID < b.displayID }
                return a.index < b.index
            }
            for (slotOffset, item) in group.enumerated() where item.index >= 0 && item.index < resolved.count {
                resolved[item.index] = "\(baseKey)@slot:\(slotOffset + 1)"
            }
        }
        return resolved
    }

    /// Persistent hardware identifier across macOS reboots using ColorSync/EDID display UUID.
    func screenKey(for screen: NSScreen) -> String {
        if let id = displayID(for: screen) {
            if let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(id) {
                let uuid = unmanagedUUID.takeRetainedValue()
                if let cfStr = CFUUIDCreateString(nil, uuid) {
                    return "uuid:\(cfStr as String)"
                }
            }
            let vendor = CGDisplayVendorNumber(id)
            let model = CGDisplayModelNumber(id)
            let serial = CGDisplaySerialNumber(id)
            let builtin = CGDisplayIsBuiltin(id)
            return "hw:\(vendor)-\(model)-\(serial)-\(builtin)-\(screen.localizedName)"
        }
        return screen.localizedName
    }

    private func persistentScreenKeyInfo(
        for screen: NSScreen,
        among screens: [NSScreen] = NSScreen.screens
    ) -> (effectiveKey: String, baseKey: String, siblingEffectiveKeys: [String]) {
        let base = screenKey(for: screen)
        guard !screens.isEmpty else {
            return (base, base, [base])
        }
        let descriptors: [ScreenIdentityDescriptor] = screens.enumerated().map { idx, s in
            let id = displayID(for: s)
            return ScreenIdentityDescriptor(
                index: idx,
                baseKey: screenKey(for: s),
                originX: Int(round(s.frame.origin.x)),
                originY: Int(round(s.frame.origin.y)),
                unitNumber: id.map { CGDisplayUnitNumber($0) } ?? 0,
                displayID: id ?? 0
            )
        }
        let resolved = Self.resolvePersistentScreenKeys(for: descriptors)
        let targetID = displayID(for: screen)
        let matchIdx = screens.firstIndex(where: { $0 === screen })
            ?? screens.firstIndex(where: { s in
                guard let t = targetID, let sid = displayID(for: s) else { return false }
                return t == sid
            })

        guard let idx = matchIdx, idx < resolved.count else {
            return (base, base, [base])
        }
        let siblings = zip(descriptors, resolved)
            .filter { $0.0.baseKey == base }
            .map { $0.1 }
        return (resolved[idx], base, siblings)
    }

    /// Per-connection unique key used by runtime panel, hint, and auto-hide work item maps.
    func runtimeScreenKey(for screen: NSScreen) -> String {
        Self.composeRuntimeScreenKey(persistentKey: screenKey(for: screen), displayID: displayID(for: screen))
    }

    func isPrimaryDisplay(_ screen: NSScreen) -> Bool {
        if let id = displayID(for: screen) {
            return id == CGMainDisplayID()
        }
        return screen === NSScreen.screens.first
    }

    func isScreenEnabled(_ screen: NSScreen) -> Bool {
        if skipPrimaryDisplay && isPrimaryDisplay(screen) {
            return false
        }
        let current = disabledScreens
        if current.isEmpty {
            return true
        }
        let info = persistentScreenKeyInfo(for: screen)
        if current.contains(info.effectiveKey) {
            return false
        }
        if info.effectiveKey != info.baseKey && current.contains(info.baseKey) {
            return false
        }
        let legacyKey = legacyScreenKey(for: screen)
        if legacyKey != info.effectiveKey && current.contains(legacyKey) {
            var migrated = current
            migrated.remove(legacyKey)
            migrated.insert(info.effectiveKey)
            defaults.set(Array(migrated), forKey: Keys.disabledScreens)
            return false
        }
        return true
    }

    func toggleScreen(_ screen: NSScreen) {
        let info = persistentScreenKeyInfo(for: screen)
        let legacyKey = legacyScreenKey(for: screen)
        if isPrimaryDisplay(screen) && skipPrimaryDisplay {
            defaults.set(false, forKey: Keys.skipPrimaryDisplay)
            var current = disabledScreens
            if info.effectiveKey != info.baseKey && current.contains(info.baseKey) {
                current.remove(info.baseKey)
                for sibling in info.siblingEffectiveKeys {
                    current.insert(sibling)
                }
            }
            current.remove(info.effectiveKey)
            current.remove(legacyKey)
            defaults.set(Array(current), forKey: Keys.disabledScreens)
            onChange?()
            return
        }
        var current = disabledScreens
        if info.effectiveKey != info.baseKey && current.contains(info.baseKey) {
            current.remove(info.baseKey)
            for sibling in info.siblingEffectiveKeys {
                current.insert(sibling)
            }
        }
        let wasDisabled = current.contains(info.effectiveKey) || current.contains(legacyKey)
        current.remove(legacyKey)
        if wasDisabled {
            current.remove(info.effectiveKey)
        } else {
            current.insert(info.effectiveKey)
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
        var scriptErr: NSDictionary?
        if let script = NSAppleScript(source: scriptSource) {
            script.executeAndReturnError(&scriptErr)
            if scriptErr == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.onChange?()
                }
                return
            }
        }

        let errNum = scriptErr?[NSAppleScript.errorNumber] as? Int
        let isPermDenied = (errNum == -1743)
        let extraDetail = (!isPermDenied ? (scriptErr?[NSAppleScript.errorMessage] as? String) : nil)

        // Ask explicit user confirmation before restarting Apple's Dock process
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = isPermDenied ? L10n.dockAutohidePermTitle : L10n.dockAutohideScriptErrorTitle
        if let detail = extraDetail, !detail.isEmpty {
            alert.informativeText = "\(L10n.dockAutohidePermMessage)\n\n(\(detail))"
        } else {
            alert.informativeText = L10n.dockAutohidePermMessage
        }
        alert.addButton(withTitle: L10n.dockAutohideRestartBtn)
        alert.addButton(withTitle: L10n.openAutomationSettingsBtn)
        alert.addButton(withTitle: L10n.cancelBtn)

        let choice = alert.runModal()
        if choice == .alertFirstButtonReturn {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            proc.arguments = ["write", "com.apple.dock", "autohide", "-bool", enabled ? "true" : "false"]
            do {
                try proc.run()
                proc.waitUntilExit()
                guard proc.terminationStatus == 0 else { return }
            } catch {
                return
            }

            let killProc = Process()
            killProc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            killProc.arguments = ["Dock"]
            try? killProc.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.onChange?()
            }
        } else if choice == .alertSecondButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Launch at Login (SMAppService on macOS 13+ with Legacy LaunchAgent Migration)

    private var legacyLaunchAgentURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(Self.launchAgentLabel).plist")
    }

    func migrateLegacyLaunchAgentIfNeeded() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyLaunchAgentURL.path) else { return }
        try? fm.removeItem(at: legacyLaunchAgentURL)
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
    }

    var launchAtLoginRequiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    var launchAtLogin: Bool {
        get {
            let status = SMAppService.mainApp.status
            return status == .enabled || status == .requiresApproval
        }
        set {
            let fm = FileManager.default
            if fm.fileExists(atPath: legacyLaunchAgentURL.path) {
                try? fm.removeItem(at: legacyLaunchAgentURL)
            }
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                    if SMAppService.mainApp.status == .requiresApproval {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSSound.beep()
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = L10n.loginItemErrorTitle
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: L10n.okBtn)
                alert.runModal()
            }
        }
    }
}
