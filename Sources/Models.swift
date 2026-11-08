import Cocoa

enum DockStackSortOrder: Int, Equatable {
    case name = 1
    case dateAdded = 2
    case dateModified = 3
    case dateCreated = 4
    case kind = 5
}

enum DockStackStyle: Int, Equatable {
    case automatic = 0
    case fan = 1
    case grid = 2
    case list = 3
}

struct DockFolderStackConfig: Equatable {
    let sortOrder: DockStackSortOrder
    let style: DockStackStyle
    let displayAsStack: Bool

    static func parse(from tileData: [String: Any], folderURL: URL) -> DockFolderStackConfig {
        let isDownloads = folderURL.standardizedFileURL.lastPathComponent.lowercased() == "downloads"
        let defaultSort: DockStackSortOrder = isDownloads ? .dateAdded : .name
        let rawSort = (tileData["arrangement"] as? Int) ?? defaultSort.rawValue
        let sortOrder = DockStackSortOrder(rawValue: rawSort) ?? defaultSort

        let rawStyle = (tileData["showas"] as? Int) ?? 0
        let style = DockStackStyle(rawValue: rawStyle) ?? .automatic

        let rawDisplayAs = (tileData["displayas"] as? Int) ?? (isDownloads ? 0 : 1)
        return DockFolderStackConfig(
            sortOrder: sortOrder,
            style: style,
            displayAsStack: rawDisplayAs == 0
        )
    }
}

enum DockItemKind: Equatable {
    case finder
    case application(bundleID: String?, url: URL)
    case directoryOrFile(url: URL, isDirectory: Bool, stackConfig: DockFolderStackConfig? = nil)
    case separator
    case trash(isFull: Bool)
}

struct DockItem: Equatable {
    let id: String
    let label: String
    let kind: DockItemKind
    let icon: NSImage
    let isRunning: Bool
    let isFrontmost: Bool

    static func == (lhs: DockItem, rhs: DockItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.label == rhs.label &&
        lhs.kind == rhs.kind &&
        lhs.isRunning == rhs.isRunning &&
        lhs.isFrontmost == rhs.isFrontmost
    }
}

enum AppInstanceMatcher {
    struct IndexedCandidate {
        let bundleID: String?
        let bundleURL: URL?
        let normalizedPath: String?
        let standardizedPath: String?
        let lastPathComponent: String?
    }

    static func normalizedPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func indexCandidates(_ candidates: [(bundleID: String?, bundleURL: URL?)]) -> [IndexedCandidate] {
        candidates.map { cand in
            guard let u = cand.bundleURL else {
                return IndexedCandidate(bundleID: cand.bundleID, bundleURL: nil, normalizedPath: nil, standardizedPath: nil, lastPathComponent: nil)
            }
            return IndexedCandidate(
                bundleID: cand.bundleID,
                bundleURL: u,
                normalizedPath: normalizedPath(u),
                standardizedPath: u.standardizedFileURL.path,
                lastPathComponent: u.lastPathComponent
            )
        }
    }

    /// Matches a running app instance by exact bundle path first. Falls back to bundleIdentifier only when
    /// macOS mounts a system app via Cryptex/System firmlinks (e.g. Safari) or Gatekeeper AppTranslocation
    /// with the same bundle filename, preventing two distinct copies of an app (e.g. Xcode vs Xcode-beta)
    /// from confusing Hide/Quit/dots.
    static func preferredIndex(
        targetBundleID: String?,
        targetURL: URL,
        indexedCandidates: [IndexedCandidate]
    ) -> Int? {
        let targetNorm = normalizedPath(targetURL)
        if let exactIdx = indexedCandidates.firstIndex(where: { $0.normalizedPath == targetNorm }) {
            return exactIdx
        }

        guard let bid = targetBundleID, !bid.isEmpty else { return nil }
        let targetName = targetURL.lastPathComponent
        return indexedCandidates.firstIndex(where: { cand in
            guard cand.bundleID == bid else { return false }
            guard let candPath = cand.standardizedPath, let candName = cand.lastPathComponent else { return true }
            guard candName == targetName else { return false }
            let isSystemAlias = candPath.hasPrefix("/System/") || targetNorm.hasPrefix("/System/")
            let isTranslocated = candPath.contains("/AppTranslocation/")
            return isSystemAlias || isTranslocated
        })
    }

    static func preferredIndex(
        targetBundleID: String?,
        targetURL: URL,
        candidates: [(bundleID: String?, bundleURL: URL?)]
    ) -> Int? {
        preferredIndex(
            targetBundleID: targetBundleID,
            targetURL: targetURL,
            indexedCandidates: indexCandidates(candidates)
        )
    }
}

final class DockModelReader {
    static let shared = DockModelReader()

    private var iconCache: [String: NSImage] = [:]
    private var lastPlistModDate: Date?
    private var lastTrashModDate: Date?
    private var cachedTrashNonEmpty: Bool?
    private var cachedPersistentApps: [(label: String, bundleID: String?, url: URL)] = []
    private var cachedPersistentOthers: [(label: String, url: URL, isDirectory: Bool, stackConfig: DockFolderStackConfig?)] = []
    private var cachedTrashFullFromPlist: Bool = false

    private let dockPlistURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.dock.plist")
    }()

    private init() {
        reloadPlistCache()
    }

    /// Parses a `file-data` dictionary from `com.apple.dock.plist`, supporting both `_CFURLStringType = 15`
    /// (`file:///...` URLs) and `_CFURLStringType = 0` (POSIX paths written by `defaults write` scripts).
    static func parseDockFileURL(from fileData: [String: Any]?) -> URL? {
        guard let raw = fileData?["_CFURLString"] as? String, !raw.isEmpty else { return nil }
        let urlType = fileData?["_CFURLStringType"] as? Int ?? (raw.hasPrefix("/") ? 0 : 15)
        if urlType == 0 || raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw)
        }
        guard let u = URL(string: raw), u.isFileURL else { return nil }
        return u
    }

    private static func resolveBookmarkAliasURL(from fileData: [String: Any]?) -> URL? {
        guard let aliasData = fileData?["_CFURLAliasData"] as? Data else { return nil }
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: aliasData,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), resolved.isFileURL, FileManager.default.fileExists(atPath: resolved.path) else {
            return nil
        }
        return resolved
    }

    @discardableResult
    func checkPlistChangedAndReloadIfNeeded() -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: dockPlistURL.path),
              let modDate = attrs[.modificationDate] as? Date else {
            return false
        }
        if lastPlistModDate != modDate {
            reloadPlistCache()
            return true
        }
        return false
    }

    func reloadPlistCache(clearIcons: Bool = false) {
        if clearIcons {
            iconCache.removeAll()
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: dockPlistURL.path),
           let modDate = attrs[.modificationDate] as? Date {
            lastPlistModDate = modDate
        }

        guard let data = try? Data(contentsOf: dockPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return
        }

        cachedTrashFullFromPlist = (plist["trash-full"] as? Bool) ?? false

        var appsResult: [(label: String, bundleID: String?, url: URL)] = []
        if let rawApps = plist["persistent-apps"] as? [[String: Any]] {
            for entry in rawApps {
                let tileType = entry["tile-type"] as? String ?? "file-tile"
                if tileType.contains("spacer") { continue }
                guard let tileData = entry["tile-data"] as? [String: Any] else { continue }

                let bundleID = tileData["bundle-identifier"] as? String
                let rawLabel = tileData["file-label"] as? String
                let fileData = tileData["file-data"] as? [String: Any]

                var resolvedURL: URL?
                if let candidate = Self.parseDockFileURL(from: fileData),
                   FileManager.default.fileExists(atPath: candidate.path) {
                    resolvedURL = candidate
                } else if let aliasCandidate = Self.resolveBookmarkAliasURL(from: fileData) {
                    resolvedURL = aliasCandidate
                } else if let bundleID = bundleID,
                          let candidate = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    resolvedURL = candidate
                }

                guard let finalURL = resolvedURL else { continue }
                let label = rawLabel ?? finalURL.deletingPathExtension().lastPathComponent
                appsResult.append((label: label, bundleID: bundleID, url: finalURL))
            }
        }
        cachedPersistentApps = appsResult

        var othersResult: [(label: String, url: URL, isDirectory: Bool, stackConfig: DockFolderStackConfig?)] = []
        if let rawOthers = plist["persistent-others"] as? [[String: Any]] {
            for entry in rawOthers {
                let tileType = entry["tile-type"] as? String ?? "file-tile"
                if tileType.contains("spacer") { continue }
                guard let tileData = entry["tile-data"] as? [String: Any] else { continue }
                let fileData = tileData["file-data"] as? [String: Any]

                let resolvedOtherURL: URL?
                if let candidate = Self.parseDockFileURL(from: fileData),
                   FileManager.default.fileExists(atPath: candidate.path) {
                    resolvedOtherURL = candidate
                } else {
                    resolvedOtherURL = Self.resolveBookmarkAliasURL(from: fileData)
                }

                guard let fileURL = resolvedOtherURL else { continue }
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir)
                // Treat macOS bundles (.app, .rtfd, .pages, etc.) as files rather than expandable folders
                let isPackage = (try? fileURL.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
                let isExpandableDirectory = isDir.boolValue && !isPackage
                let stackCfg = isExpandableDirectory
                    ? DockFolderStackConfig.parse(from: tileData, folderURL: fileURL)
                    : nil
                let label = (tileData["file-label"] as? String) ?? fileURL.lastPathComponent
                othersResult.append((label: label, url: fileURL, isDirectory: isExpandableDirectory, stackConfig: stackCfg))
            }
        }
        cachedPersistentOthers = othersResult

        if !clearIcons {
            var keepKeys: Set<String> = [
                "/System/Library/CoreServices/Finder.app",
                "__trash_full__",
                "__trash_empty__"
            ]
            for a in appsResult { keepKeys.insert(a.url.path) }
            for o in othersResult { keepKeys.insert(o.url.path) }
            iconCache = iconCache.filter { keepKeys.contains($0.key) }
        }
    }

    static func findRunningApplication(
        bundleID: String?,
        url: URL,
        among apps: [NSRunningApplication] = NSWorkspace.shared.runningApplications
    ) -> NSRunningApplication? {
        let live = apps.filter { !$0.isTerminated }
        let pairs = live.map { (bundleID: $0.bundleIdentifier, bundleURL: $0.bundleURL) }
        guard let idx = AppInstanceMatcher.preferredIndex(
            targetBundleID: bundleID,
            targetURL: url,
            candidates: pairs
        ) else {
            return nil
        }
        return live[idx]
    }

    func buildItems(includeUnpinnedRunning: Bool) -> [DockItem] {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications.filter { !$0.isTerminated }
        let indexedRunning = AppInstanceMatcher.indexCandidates(
            runningApps.map { (bundleID: $0.bundleIdentifier, bundleURL: $0.bundleURL) }
        )
        let frontmostPID = workspace.frontmostApplication?.processIdentifier
        let frontmostBundleID = workspace.frontmostApplication?.bundleIdentifier

        var items: [DockItem] = []
        var claimedPIDs = Set<pid_t>()

        // 1. Finder (siempre primero en macOS)
        let finderBundleID = "com.apple.finder"
        let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        if let finderApp = runningApps.first(where: { $0.bundleIdentifier == finderBundleID }) {
            claimedPIDs.insert(finderApp.processIdentifier)
        }
        items.append(DockItem(
            id: "finder",
            label: L10n.finderLabel,
            kind: .finder,
            icon: iconForFile(finderURL.path),
            isRunning: true,
            isFrontmost: frontmostBundleID == finderBundleID
        ))

        // 2. Apps ancladas en com.apple.dock (persistent-apps)
        for (idx, entry) in cachedPersistentApps.enumerated() {
            if entry.bundleID == finderBundleID { continue }

            let matchedIdx = AppInstanceMatcher.preferredIndex(
                targetBundleID: entry.bundleID,
                targetURL: entry.url,
                indexedCandidates: indexedRunning
            )
            let matchedApp = matchedIdx.map { runningApps[$0] }
            if let matched = matchedApp {
                claimedPIDs.insert(matched.processIdentifier)
            }
            let running = (matchedApp != nil)
            let front = (matchedApp != nil && matchedApp?.processIdentifier == frontmostPID)

            items.append(DockItem(
                id: "pinned-\(entry.bundleID ?? entry.url.path)-\(idx)",
                label: entry.label,
                kind: .application(bundleID: entry.bundleID, url: entry.url),
                icon: iconForFile(entry.url.path),
                isRunning: running,
                isFrontmost: front
            ))
        }

        // 3. Apps regulares abiertas que no están ancladas (incluye copias adicionales en otra ruta)
        if includeUnpinnedRunning {
            let ownBundleID = Bundle.main.bundleIdentifier ?? DockSettings.bundleIdentifier
            var extraItems: [DockItem] = []
            for app in runningApps {
                guard app.activationPolicy == .regular else { continue }
                if claimedPIDs.contains(app.processIdentifier) { continue }
                let bid = app.bundleIdentifier
                if bid == ownBundleID || bid == "com.apple.dock" || bid == finderBundleID { continue }
                guard let appURL = app.bundleURL else { continue }

                claimedPIDs.insert(app.processIdentifier)

                let name = app.localizedName ?? appURL.deletingPathExtension().lastPathComponent
                let front = (app.processIdentifier == frontmostPID)
                let icon = app.icon ?? iconForFile(appURL.path)

                extraItems.append(DockItem(
                    id: "running-\(app.processIdentifier)-\(appURL.path)",
                    label: name,
                    kind: .application(bundleID: bid, url: appURL),
                    icon: icon,
                    isRunning: true,
                    isFrontmost: front
                ))
            }

            if !extraItems.isEmpty {
                items.append(DockItem(
                    id: "sep-running",
                    label: "",
                    kind: .separator,
                    icon: NSImage(),
                    isRunning: false,
                    isFrontmost: false
                ))
                items.append(contentsOf: extraItems)
            }
        }

        // 4. Separador final + Carpetas/Archivos (persistent-others) + Papelera
        items.append(DockItem(
            id: "sep-others",
            label: "",
            kind: .separator,
            icon: NSImage(),
            isRunning: false,
            isFrontmost: false
        ))

        for (idx, other) in cachedPersistentOthers.enumerated() {
            items.append(DockItem(
                id: "other-\(other.url.path)-\(idx)",
                label: other.label,
                kind: .directoryOrFile(url: other.url, isDirectory: other.isDirectory, stackConfig: other.stackConfig),
                icon: iconForFile(other.url.path),
                isRunning: false,
                isFrontmost: false
            ))
        }

        let isTrashFull = isUserTrashNonEmpty() ?? cachedTrashFullFromPlist
        items.append(DockItem(
            id: "trash",
            label: L10n.trashLabel,
            kind: .trash(isFull: isTrashFull),
            icon: trashIcon(isFull: isTrashFull),
            isRunning: false,
            isFrontmost: false
        ))

        return items
    }

    private func iconForFile(_ path: String) -> NSImage {
        if let cached = iconCache[path] {
            return cached
        }
        let img = NSWorkspace.shared.icon(forFile: path)
        img.size = NSSize(width: 64, height: 64)
        iconCache[path] = img
        return img
    }

    private func isUserTrashNonEmpty() -> Bool? {
        guard let trashURL = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first else {
            return nil
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: trashURL.path),
           let modDate = attrs[.modificationDate] as? Date {
            if lastTrashModDate == modDate, let cached = cachedTrashNonEmpty {
                return cached
            }
            lastTrashModDate = modDate
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: trashURL.path) else {
            return nil
        }
        let nonEmpty = contents.contains { $0 != ".DS_Store" }
        cachedTrashNonEmpty = nonEmpty
        return nonEmpty
    }

    private func trashIcon(isFull: Bool) -> NSImage {
        let key = isFull ? "__trash_full__" : "__trash_empty__"
        if let cached = iconCache[key] {
            return cached
        }
        let dockRes = "/System/Library/CoreServices/Dock.app/Contents/Resources/"
        let candidates = isFull
            ? [dockRes + "trashfull@2x.png", dockRes + "trashfull.png", "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/FullTrashIcon.icns"]
            : [dockRes + "trashempty@2x.png", dockRes + "trashempty.png", "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/TrashIcon.icns"]

        for p in candidates {
            if let img = NSImage(contentsOfFile: p) {
                iconCache[key] = img
                return img
            }
        }
        return NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
    }
}
