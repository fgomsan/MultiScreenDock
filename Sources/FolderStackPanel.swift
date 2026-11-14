import Cocoa
import QuartzCore
import QuickLookThumbnailing

// MARK: - Pure Data Model & Testable Layout/Sort Engine

struct FolderStackEntry: Equatable {
    let url: URL
    let displayName: String
    let isSubfolder: Bool
    let dateAdded: Date
    let dateModified: Date
    let dateCreated: Date
    let kindDescription: String
    let fileSize: Int64?
}

enum FolderStackEngine {
    static let maxFanVisibleItems = 8
    static let maxPopoverRenderedItems = 200

    static func sortEntries(_ entries: [FolderStackEntry], by order: DockStackSortOrder) -> [FolderStackEntry] {
        entries.sorted { a, b in
            switch order {
            case .name:
                let cmp = a.displayName.localizedStandardCompare(b.displayName)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return a.url.path < b.url.path

            case .dateAdded:
                if a.dateAdded != b.dateAdded { return a.dateAdded > b.dateAdded }
                if a.dateModified != b.dateModified { return a.dateModified > b.dateModified }
                return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending

            case .dateModified:
                if a.dateModified != b.dateModified { return a.dateModified > b.dateModified }
                return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending

            case .dateCreated:
                if a.dateCreated != b.dateCreated { return a.dateCreated > b.dateCreated }
                return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending

            case .kind:
                let kindCmp = a.kindDescription.localizedStandardCompare(b.kindDescription)
                if kindCmp != .orderedSame { return kindCmp == .orderedAscending }
                return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
            }
        }
    }

    /// Resolves whether to display as `.fan`, `.grid`, or `.list`.
    static func resolveEffectiveStyle(
        preference: FolderStackStylePreference,
        dockConfig: DockFolderStackConfig?,
        itemCount: Int,
        isSubfolder: Bool
    ) -> DockStackStyle {
        let baseStyle: DockStackStyle
        switch preference {
        case .dockDefault:
            baseStyle = dockConfig?.style ?? .automatic
        case .fan:
            baseStyle = .fan
        case .grid:
            baseStyle = .grid
        case .list:
            baseStyle = .list
        }

        // Empty folders or subfolder drill-downs always use a card view (Grid or List) with header/back navigation
        if itemCount == 0 {
            return baseStyle == .list ? .list : .grid
        }
        if isSubfolder && (baseStyle == .fan || baseStyle == .automatic) {
            return .grid
        }

        switch baseStyle {
        case .automatic:
            return itemCount <= 7 ? .fan : .grid
        case .fan:
            return .fan
        case .grid:
            return .grid
        case .list:
            return .list
        }
    }

    /// Computes curved icon center X positions (in screen coordinates) and Y offsets for Fan mode,
    /// curving gently rightward when space permits and leftward near a display's right border so neither
    /// the icon nor its left-side label pill ever clips off-screen.
    static func computeFanIconCenters(
        rowCount: Int,
        anchorMidX: CGFloat,
        baseY: CGFloat,
        screenMinX: CGFloat,
        screenMaxX: CGFloat,
        iconSize: CGFloat = 50,
        maxLabelPillWidth: CGFloat = 224
    ) -> [NSPoint] {
        guard rowCount > 0 else { return [] }
        let halfIcon = iconSize / 2.0
        let minAllowedCenterX = screenMinX + maxLabelPillWidth + 18 + halfIcon
        let maxAllowedCenterX = screenMaxX - halfIcon - 14

        let clampedBaseX: CGFloat
        if minAllowedCenterX <= maxAllowedCenterX {
            clampedBaseX = min(max(anchorMidX, minAllowedCenterX), maxAllowedCenterX)
        } else {
            clampedBaseX = min(max(anchorMidX, screenMinX + halfIcon + 12), screenMaxX - halfIcon - 12)
        }

        let roomRight = screenMaxX - (clampedBaseX + halfIcon)
        let direction: CGFloat = (roomRight >= 46) ? 1.0 : -1.0
        let maxCurve: CGFloat = min(28.0, max(10.0, (direction > 0 ? roomRight - 14 : (clampedBaseX - screenMinX) - 40)))
        let stepY: CGFloat = 56.0

        return (0..<rowCount).map { idx in
            let t = rowCount > 1 ? CGFloat(idx) / CGFloat(rowCount - 1) : 0
            let dx = sin(t * .pi * 0.58) * maxCurve * direction
            let rawX = clampedBaseX + dx
            let finalX = min(max(rawX, screenMinX + halfIcon + 12), screenMaxX - halfIcon - 12)
            let finalY = baseY + CGFloat(idx) * stepY
            return NSPoint(x: round(finalX), y: round(finalY))
        }
    }

    static func readDirectoryEntries(at folderURL: URL, sortOrder: DockStackSortOrder) throws -> [FolderStackEntry] {
        let keys: [URLResourceKey] = [
            .localizedNameKey,
            .isDirectoryKey,
            .isPackageKey,
            .isHiddenKey,
            .addedToDirectoryDateKey,
            .contentModificationDateKey,
            .creationDateKey,
            .localizedTypeDescriptionKey,
            .fileSizeKey
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )

        var entries: [FolderStackEntry] = []
        entries.reserveCapacity(urls.count)

        for u in urls {
            let name = u.lastPathComponent
            if name.hasPrefix(".") { continue }
            let vals = try? u.resourceValues(forKeys: Set(keys))
            if vals?.isHidden == true { continue }

            let isDir = vals?.isDirectory ?? false
            let isPkg = vals?.isPackage ?? false
            let displayName = vals?.localizedName ?? name
            let modDate = vals?.contentModificationDate ?? .distantPast
            let createDate = vals?.creationDate ?? modDate
            let addedDate = vals?.addedToDirectoryDate ?? modDate
            let kindDesc = vals?.localizedTypeDescription ?? ""
            let size = vals?.fileSize.map { Int64($0) }

            entries.append(FolderStackEntry(
                url: u,
                displayName: displayName,
                isSubfolder: isDir && !isPkg,
                dateAdded: addedDate,
                dateModified: modDate,
                dateCreated: createDate,
                kindDescription: kindDesc,
                fileSize: size
            ))
        }

        return sortEntries(entries, by: sortOrder)
    }
}

// MARK: - Fast Workspace Icon + Async QuickLook Thumbnail Cache

final class StackThumbnailProvider {
    static let shared = StackThumbnailProvider()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlight = Set<String>()
    private let lock = NSLock()

    private init() {
        cache.countLimit = 240
    }

    func immediateIcon(for entry: FolderStackEntry) -> NSImage {
        let key = cacheKey(for: entry)
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: entry.url.path)
        icon.size = NSSize(width: 64, height: 64)
        return icon
    }

    func requestThumbnailIfHelpful(
        for entry: FolderStackEntry,
        pixelSize: CGFloat = 64,
        scale: CGFloat = 2.0,
        completion: @escaping (NSImage) -> Void
    ) {
        guard !entry.isSubfolder else { return }
        let key = cacheKey(for: entry)
        if let cached = cache.object(forKey: key as NSString) {
            completion(cached)
            return
        }

        lock.lock()
        if inFlight.contains(key) {
            lock.unlock()
            return
        }
        inFlight.insert(key)
        lock.unlock()

        let req = QLThumbnailGenerator.Request(
            fileAt: entry.url,
            size: CGSize(width: pixelSize, height: pixelSize),
            scale: max(1.0, scale),
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            guard let self = self else { return }
            self.lock.lock()
            self.inFlight.remove(key)
            self.lock.unlock()

            guard let cgImg = rep?.cgImage else { return }
            let nsImg = NSImage(cgImage: cgImg, size: NSSize(width: pixelSize, height: pixelSize))
            self.cache.setObject(nsImg, forKey: key as NSString)
            DispatchQueue.main.async {
                completion(nsImg)
            }
        }
    }

    private func cacheKey(for entry: FolderStackEntry) -> String {
        let ts = Int64(entry.dateModified.timeIntervalSince1970)
        return "\(entry.url.path)#\(ts)"
    }
}

// MARK: - Interactive Item Tile / Row Supporting Click, ⌘-Click, and File Drag-Out

final class DraggableStackItemControl: NSView, NSDraggingSource {
    let entry: FolderStackEntry?
    var onActivate: ((NSEvent.ModifierFlags) -> Void)?

    private var mouseDownPoint: NSPoint?
    private var mouseDownEvent: NSEvent?
    private var didStartDrag = false
    private var trackingArea: NSTrackingArea?
    var onHoverChange: ((Bool) -> Void)?

    init(entry: FolderStackEntry?, frame: NSRect) {
        self.entry = entry
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    /// Always return `self` rather than internal `NSImageView` / `NSTextField` / `NSVisualEffectView` subviews,
    /// ensuring `acceptsFirstMouse == true` on non-activating panels and preventing `NSControl` cell tracking
    /// from swallowing `mouseDragged` events when dragging by the icon or filename pill.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01 else { return nil }
        return frame.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            super.mouseDown(with: event)
            return
        }
        guard let win = window else { return }

        let start = convert(event.locationInWindow, from: nil)
        mouseDownPoint = start
        mouseDownEvent = event
        didStartDrag = false

        while true {
            guard let next = win.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else { break }

            let cur = convert(next.locationInWindow, from: nil)

            if next.type == .leftMouseUp {
                if !didStartDrag && bounds.contains(cur) {
                    onActivate?(next.modifierFlags)
                }
                mouseDownPoint = nil
                mouseDownEvent = nil
                break
            }

            if next.type == .leftMouseDragged, let entry = entry {
                let dist = hypot(cur.x - start.x, cur.y - start.y)
                if dist >= 4.0 {
                    didStartDrag = true
                    mouseDownPoint = nil
                    mouseDownEvent = nil
                    initiateFileDragSession(for: entry, initialEvent: event, anchorInSelf: start)
                    break
                }
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag,
              let entry = entry,
              let start = mouseDownPoint else { return }
        let cur = convert(event.locationInWindow, from: nil)
        let dist = hypot(cur.x - start.x, cur.y - start.y)
        guard dist >= 4.0 else { return }

        didStartDrag = true
        let initial = mouseDownEvent ?? event
        mouseDownPoint = nil
        mouseDownEvent = nil
        initiateFileDragSession(for: entry, initialEvent: initial, anchorInSelf: start)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownPoint = nil
            mouseDownEvent = nil
        }
        guard !didStartDrag else { return }
        let pt = convert(event.locationInWindow, from: nil)
        if bounds.contains(pt) {
            onActivate?(event.modifierFlags)
        }
    }

    private func initiateFileDragSession(for entry: FolderStackEntry, initialEvent: NSEvent, anchorInSelf: NSPoint) {
        let fileURL = entry.url.standardizedFileURL
        let dragItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        let icon = StackThumbnailProvider.shared.immediateIcon(for: entry)
        let side = max(16.0, min(48.0, min(bounds.width, bounds.height)))
        let clampedX = min(max(0.0, anchorInSelf.x - side * 0.5), max(0.0, bounds.width - side))
        let clampedY = min(max(0.0, anchorInSelf.y - side * 0.5), max(0.0, bounds.height - side))
        let dragFrame = NSRect(x: clampedX, y: clampedY, width: side, height: side)
        dragItem.setDraggingFrame(dragFrame, contents: icon)

        onHoverChange?(false)
        FolderStackController.shared.prepareForOutgoingFileDrag()
        let session = beginDraggingSession(with: [dragItem], event: initialEvent, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .generic : [.copy, .move, .link, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        FolderStackController.shared.didBeginOutgoingFileDrag()
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        FolderStackController.shared.didEndOutgoingFileDrag()
    }
}

// MARK: - Fan Pass-Through Root View (Clicks on Empty Space Dismiss Cleanly)

final class FanPassthroughRootView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = superview != nil ? convert(point, from: superview) : point
        guard bounds.contains(localPoint) else { return nil }
        for sub in subviews.reversed() {
            if let hit = sub.hitTest(localPoint) {
                return hit
            }
        }
        return nil
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Non-Activating Key-Capable Panel (Supports Escape Without Stealing Active App)

final class FolderStackPanel: NSPanel {
    var onEscapePressed: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        acceptsMouseMovedEvents = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 3)
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if DockSettings.shared.showOverFullScreen {
            behavior.insert(.fullScreenAuxiliary)
        }
        collectionBehavior = behavior
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func hitInteractiveView(atWindowPoint winPt: NSPoint) -> NSView? {
        guard let root = contentView else { return nil }
        let ptInRootSuper = root.superview != nil ? root.superview!.convert(winPt, from: nil) : winPt
        return root.hitTest(ptInRootSuper)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscapePressed?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onEscapePressed?()
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - Central Folder Stack Controller

final class FolderStackController {
    static let shared = FolderStackController()

    private var panel: FolderStackPanel?
    private weak var activeBarPanel: DockBarPanel?
    private(set) var rootFolderURL: URL?
    private var navigationStack: [(url: URL, title: String)] = []
    private var currentDockConfig: DockFolderStackConfig?
    private var currentAnchorScreenRect: NSRect = .zero
    private weak var currentScreen: NSScreen?
    private var sessionStyleOverride: DockStackStyle?
    private(set) var isDraggingFile = false
    private var didConfirmDragSessionStart = false

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var workspaceObserversInstalled = false

    private init() {}

    var isVisible: Bool {
        panel?.isVisible == true && !isDraggingFile
    }

    func isPresented(for folderURL: URL, on barPanel: DockBarPanel?) -> Bool {
        guard isVisible else { return false }
        return rootFolderURL?.standardizedFileURL == folderURL.standardizedFileURL && activeBarPanel === barPanel
    }

    /// Keeps `panel` and its `DraggableStackItemControl` (`NSDraggingSource`) alive in memory and attached
    /// to a valid `NSWindow` for the full duration of a cross-monitor drag, while fading the stack out
    /// and making it mouse-transparent so any window underneath can accept the drop.
    func prepareForOutgoingFileDrag() {
        isDraggingFile = true
        didConfirmDragSessionStart = false
        removeClickOutsideMonitors()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self = self, self.isDraggingFile, !self.didConfirmDragSessionStart else { return }
            // Safety recovery if AppKit aborted drag startup before `willBeginAt`
            self.isDraggingFile = false
            self.dismiss(animated: false)
        }
    }

    func didBeginOutgoingFileDrag() {
        isDraggingFile = true
        didConfirmDragSessionStart = true
        guard let stackWin = panel else { return }
        stackWin.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            stackWin.animator().alphaValue = 0.0
        }
    }

    func didEndOutgoingFileDrag() {
        isDraggingFile = false
        didConfirmDragSessionStart = false
        DispatchQueue.main.async { [weak self] in
            self?.dismiss(animated: false)
        }
    }

    func toggleOrPresent(
        folderURL: URL,
        title: String,
        dockConfig: DockFolderStackConfig?,
        anchorScreenRect: NSRect,
        on screen: NSScreen?,
        barPanel: DockBarPanel?
    ) {
        if isPresented(for: folderURL, on: barPanel) {
            dismiss(animated: true)
            return
        }

        // Probe read access upfront; if TCC denies ~/Downloads, fall back seamlessly to opening in Finder
        let cfg = dockConfig ?? DockFolderStackConfig.parse(from: [:], folderURL: folderURL)
        let entries: [FolderStackEntry]
        do {
            entries = try FolderStackEngine.readDirectoryEntries(at: folderURL, sortOrder: cfg.sortOrder)
        } catch {
            dismiss(animated: false)
            openInFinder(folderURL)
            return
        }

        dismiss(animated: false)
        installWorkspaceObserversIfNeeded()

        activeBarPanel = barPanel
        barPanel?.isFolderStackOpen = true
        rootFolderURL = folderURL
        navigationStack = [(url: folderURL, title: title)]
        currentDockConfig = cfg
        currentAnchorScreenRect = anchorScreenRect
        currentScreen = screen ?? NSScreen.main
        sessionStyleOverride = nil

        renderCurrentFolder(preloadedEntries: entries, animated: true)
        installClickOutsideMonitors()
    }

    func dismiss(animated: Bool) {
        guard !isDraggingFile else { return }
        removeClickOutsideMonitors()
        if let bar = activeBarPanel {
            bar.isFolderStackOpen = false
        }
        activeBarPanel = nil
        rootFolderURL = nil
        navigationStack.removeAll()
        sessionStyleOverride = nil

        guard let existing = panel else {
            MultiScreenController.shared.evaluateAutoHideNow()
            return
        }
        panel = nil

        if animated && existing.isVisible {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.13
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                existing.animator().alphaValue = 0.0
            }, completionHandler: {
                existing.orderOut(nil)
                existing.close()
                MultiScreenController.shared.evaluateAutoHideNow()
            })
        } else {
            existing.orderOut(nil)
            existing.close()
            MultiScreenController.shared.evaluateAutoHideNow()
        }
    }

    // MARK: - Rendering Modes (Fan / Grid / List)

    private func renderCurrentFolder(preloadedEntries: [FolderStackEntry]? = nil, animated: Bool) {
        guard let current = navigationStack.last,
              let screen = currentScreen ?? NSScreen.main else {
            dismiss(animated: false)
            return
        }

        let sortOrder = currentDockConfig?.sortOrder ?? .name
        let entries: [FolderStackEntry]
        if let preloaded = preloadedEntries {
            entries = preloaded
        } else {
            do {
                entries = try FolderStackEngine.readDirectoryEntries(at: current.url, sortOrder: sortOrder)
            } catch {
                let target = current.url
                dismiss(animated: false)
                openInFinder(target)
                return
            }
        }

        let isSubfolder = navigationStack.count > 1
        let effectiveStyle: DockStackStyle
        if let override = sessionStyleOverride {
            effectiveStyle = (entries.isEmpty && override == .fan) ? .grid : override
        } else {
            effectiveStyle = FolderStackEngine.resolveEffectiveStyle(
                preference: DockSettings.shared.folderStackStyle,
                dockConfig: currentDockConfig,
                itemCount: entries.count,
                isSubfolder: isSubfolder
            )
        }

        switch effectiveStyle {
        case .fan:
            presentFanWindow(entries: entries, folderURL: current.url, on: screen, animated: animated)
        case .grid, .automatic:
            presentCardWindow(entries: entries, folderTitle: current.title, folderURL: current.url, style: .grid, on: screen, animated: animated)
        case .list:
            presentCardWindow(entries: entries, folderTitle: current.title, folderURL: current.url, style: .list, on: screen, animated: animated)
        }
    }

    // MARK: - 1. Fan Mode Presentation

    private func presentFanWindow(
        entries: [FolderStackEntry],
        folderURL: URL,
        on screen: NSScreen,
        animated: Bool
    ) {
        let visibleSlice = Array(entries.prefix(FolderStackEngine.maxFanVisibleItems))
        let remainingCount = max(0, entries.count - visibleSlice.count)
        let totalRows = visibleSlice.count + 1 // +1 top cap ("Open in Finder" / "N More in Finder…")

        let baseY = currentAnchorScreenRect.maxY + 14
        let iconSize: CGFloat = 50
        let centers = FolderStackEngine.computeFanIconCenters(
            rowCount: totalRows,
            anchorMidX: currentAnchorScreenRect.midX,
            baseY: baseY,
            screenMinX: screen.frame.minX,
            screenMaxX: screen.frame.maxX,
            iconSize: iconSize
        )

        // Compute bounding rect of all fan rows
        var unionRect = NSRect.null
        let maxPillW: CGFloat = 230
        let rowHeight: CGFloat = 54
        for c in centers {
            let rowRect = NSRect(
                x: c.x - iconSize / 2 - maxPillW - 16,
                y: c.y - rowHeight / 2,
                width: maxPillW + 16 + iconSize + 16,
                height: rowHeight
            )
            unionRect = unionRect.union(rowRect)
        }
        unionRect = unionRect.insetBy(dx: -12, dy: -12)
        unionRect.origin.x = max(screen.frame.minX + 4, unionRect.origin.x)

        let root = FanPassthroughRootView(frame: NSRect(origin: .zero, size: unionRect.size))
        root.wantsLayer = true

        let backingScale = screen.backingScaleFactor

        for (idx, center) in centers.enumerated() {
            let isCapRow = (idx == visibleSlice.count)
            let localCenter = NSPoint(x: center.x - unionRect.minX, y: center.y - unionRect.minY)

            if !isCapRow {
                let entry = visibleSlice[idx]
                let rowView = buildFanItemRow(
                    entry: entry,
                    localIconCenter: localCenter,
                    iconSize: iconSize,
                    backingScale: backingScale
                )
                root.addSubview(rowView)
            } else {
                let capTitle = remainingCount > 0 ? L10n.stackMoreInFinder(remainingCount) : L10n.openInFinder
                let capView = buildFanCapRow(
                    title: capTitle,
                    folderURL: folderURL,
                    hasOverflow: remainingCount > 0,
                    localIconCenter: localCenter,
                    iconSize: iconSize
                )
                root.addSubview(capView)
            }
        }

        showInPanel(rootView: root, frame: unionRect, animated: animated)
    }

    private func buildFanItemRow(
        entry: FolderStackEntry,
        localIconCenter: NSPoint,
        iconSize: CGFloat,
        backingScale: CGFloat
    ) -> NSView {
        let labelField = NSTextField(labelWithString: entry.displayName)
        labelField.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        labelField.textColor = .white
        labelField.lineBreakMode = .byTruncatingMiddle
        labelField.sizeToFit()

        let pillPadX: CGFloat = 11
        let pillWidth = min(220, max(44, ceil(labelField.frame.width) + pillPadX * 2))
        let pillHeight: CGFloat = 24
        let gap: CGFloat = 10
        let totalW = pillWidth + gap + iconSize + 8
        let totalH = iconSize + 8

        let rowOrigin = NSPoint(
            x: round(localIconCenter.x - iconSize / 2 - gap - pillWidth),
            y: round(localIconCenter.y - totalH / 2)
        )
        let control = DraggableStackItemControl(
            entry: entry,
            frame: NSRect(origin: rowOrigin, size: NSSize(width: totalW, height: totalH))
        )

        let pill = NSVisualEffectView(frame: NSRect(
            x: 0,
            y: round((totalH - pillHeight) / 2),
            width: pillWidth,
            height: pillHeight
        ))
        pill.appearance = NSAppearance(named: .darkAqua)
        pill.material = .hudWindow
        pill.blendingMode = .behindWindow
        pill.state = .active
        pill.wantsLayer = true
        pill.layer?.cornerRadius = pillHeight / 2
        pill.layer?.cornerCurve = .continuous
        pill.layer?.masksToBounds = true
        pill.layer?.borderWidth = 0.75
        pill.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor

        labelField.frame = NSRect(
            x: pillPadX,
            y: round((pillHeight - labelField.frame.height) / 2),
            width: pillWidth - pillPadX * 2,
            height: labelField.frame.height
        )
        pill.addSubview(labelField)
        control.addSubview(pill)

        let iconOrigin = NSPoint(x: pillWidth + gap, y: round((totalH - iconSize) / 2))
        let imgView = NSImageView(frame: NSRect(origin: iconOrigin, size: NSSize(width: iconSize, height: iconSize)))
        imgView.imageScaling = .scaleProportionallyUpOrDown
        imgView.wantsLayer = true
        imgView.layer?.shadowColor = NSColor.black.cgColor
        imgView.layer?.shadowOpacity = 0.35
        imgView.layer?.shadowRadius = 4
        imgView.layer?.shadowOffset = CGSize(width: 0, height: -1.5)
        imgView.image = StackThumbnailProvider.shared.immediateIcon(for: entry)
        control.addSubview(imgView)

        StackThumbnailProvider.shared.requestThumbnailIfHelpful(for: entry, pixelSize: 64, scale: backingScale) { [weak imgView] thumb in
            imgView?.image = thumb
        }

        control.onHoverChange = { [weak imgView, weak pill] hovered in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.10
                let s: CGFloat = hovered ? 1.12 : 1.0
                let newSz = iconSize * s
                let d = (newSz - iconSize) / 2
                imgView?.animator().frame = NSRect(
                    x: iconOrigin.x - d,
                    y: iconOrigin.y - d,
                    width: newSz,
                    height: newSz
                )
                pill?.layer?.borderColor = NSColor.white.withAlphaComponent(hovered ? 0.48 : 0.22).cgColor
            }
        }

        control.onActivate = { [weak self] flags in
            self?.handleEntryClick(entry, modifiers: flags)
        }

        return control
    }

    private func buildFanCapRow(
        title: String,
        folderURL: URL,
        hasOverflow: Bool,
        localIconCenter: NSPoint,
        iconSize: CGFloat
    ) -> NSView {
        let labelField = NSTextField(labelWithString: title)
        labelField.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        labelField.textColor = .white
        labelField.sizeToFit()

        let pillPadX: CGFloat = 12
        let pillWidth = min(230, ceil(labelField.frame.width) + pillPadX * 2)
        let pillHeight: CGFloat = 25
        let discSize: CGFloat = 42
        let gap: CGFloat = 10
        let totalW = pillWidth + gap + iconSize + 8
        let totalH = iconSize + 8

        let rowOrigin = NSPoint(
            x: round(localIconCenter.x - iconSize / 2 - gap - pillWidth),
            y: round(localIconCenter.y - totalH / 2)
        )
        let control = DraggableStackItemControl(
            entry: nil,
            frame: NSRect(origin: rowOrigin, size: NSSize(width: totalW, height: totalH))
        )

        let pill = NSVisualEffectView(frame: NSRect(
            x: 0,
            y: round((totalH - pillHeight) / 2),
            width: pillWidth,
            height: pillHeight
        ))
        pill.appearance = NSAppearance(named: .darkAqua)
        pill.material = .hudWindow
        pill.blendingMode = .behindWindow
        pill.state = .active
        pill.wantsLayer = true
        pill.layer?.cornerRadius = pillHeight / 2
        pill.layer?.cornerCurve = .continuous
        pill.layer?.masksToBounds = true
        pill.layer?.borderWidth = 0.75
        pill.layer?.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor

        labelField.frame = NSRect(
            x: pillPadX,
            y: round((pillHeight - labelField.frame.height) / 2),
            width: pillWidth - pillPadX * 2,
            height: labelField.frame.height
        )
        pill.addSubview(labelField)
        control.addSubview(pill)

        let discOrigin = NSPoint(
            x: pillWidth + gap + round((iconSize - discSize) / 2),
            y: round((totalH - discSize) / 2)
        )
        let disc = NSVisualEffectView(frame: NSRect(origin: discOrigin, size: NSSize(width: discSize, height: discSize)))
        disc.appearance = NSAppearance(named: .darkAqua)
        disc.material = .hudWindow
        disc.blendingMode = .behindWindow
        disc.state = .active
        disc.wantsLayer = true
        disc.layer?.cornerRadius = discSize / 2
        disc.layer?.masksToBounds = true
        disc.layer?.borderWidth = 0.85
        disc.layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor

        let symName = hasOverflow ? "square.grid.2x2" : "arrow.up.forward"
        if let sym = NSImage(systemSymbolName: symName, accessibilityDescription: title) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            let symView = NSImageView(frame: NSRect(x: 9, y: 9, width: 24, height: 24))
            symView.image = sym.withSymbolConfiguration(cfg)
            symView.contentTintColor = .white
            disc.addSubview(symView)
        }
        control.addSubview(disc)

        control.onHoverChange = { [weak disc, weak pill] hovered in
            disc?.layer?.borderColor = NSColor.white.withAlphaComponent(hovered ? 0.55 : 0.28).cgColor
            pill?.layer?.borderColor = NSColor.white.withAlphaComponent(hovered ? 0.55 : 0.24).cgColor
        }

        control.onActivate = { [weak self] flags in
            guard let self = self else { return }
            if hasOverflow && !flags.contains(.option) && !flags.contains(.command) {
                // Smoothly expand right into the scrollable Grid view when clicking "N More…" (⌥-click opens Finder directly)
                self.sessionStyleOverride = .grid
                self.renderCurrentFolder(animated: false)
            } else {
                self.dismiss(animated: true)
                self.openInFinder(folderURL)
            }
        }

        return control
    }

    // MARK: - 2. Grid & List HUD Card Presentation

    private func presentCardWindow(
        entries: [FolderStackEntry],
        folderTitle: String,
        folderURL: URL,
        style: DockStackStyle,
        on screen: NSScreen,
        animated: Bool
    ) {
        let shadowPad: CGFloat = 14
        let headerH: CGFloat = 40
        let renderedEntries = Array(entries.prefix(FolderStackEngine.maxPopoverRenderedItems))
        let overflowCount = max(0, entries.count - renderedEntries.count)
        let footerH: CGFloat = overflowCount > 0 ? 34 : 0
        let maxBodyHeight = min(430, max(200, floor(screen.frame.height * 0.54)))

        let cardWidth: CGFloat
        let contentHeight: CGFloat

        let documentView = FlippedDocumentView()
        let backingScale = screen.backingScaleFactor

        if entries.isEmpty {
            cardWidth = 300
            contentHeight = 96
            documentView.frame = NSRect(x: 0, y: 0, width: cardWidth, height: contentHeight)
            let emptyLabel = NSTextField(labelWithString: L10n.stackEmptyFolder)
            emptyLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
            emptyLabel.textColor = NSColor.white.withAlphaComponent(0.65)
            emptyLabel.alignment = .center
            emptyLabel.frame = NSRect(x: 16, y: 36, width: cardWidth - 32, height: 22)
            documentView.addSubview(emptyLabel)
        } else if style == .list {
            cardWidth = 336
            let rowH: CGFloat = 34
            let padY: CGFloat = 6
            contentHeight = padY * 2 + CGFloat(renderedEntries.count) * rowH
            documentView.frame = NSRect(x: 0, y: 0, width: cardWidth, height: contentHeight)

            for (idx, entry) in renderedEntries.enumerated() {
                let rowFrame = NSRect(x: 8, y: padY + CGFloat(idx) * rowH, width: cardWidth - 16, height: rowH)
                let row = buildListRow(entry: entry, frame: rowFrame, requestThumb: idx < 45, backingScale: backingScale)
                documentView.addSubview(row)
            }
        } else {
            let cols = renderedEntries.count <= 3 ? max(2, renderedEntries.count) : (renderedEntries.count <= 6 ? 3 : 4)
            let cellW: CGFloat = 104
            let cellH: CGFloat = 94
            let padX: CGFloat = 12
            let padY: CGFloat = 10
            cardWidth = padX * 2 + CGFloat(cols) * cellW
            let rows = Int(ceil(Double(renderedEntries.count) / Double(cols)))
            contentHeight = padY * 2 + CGFloat(rows) * cellH
            documentView.frame = NSRect(x: 0, y: 0, width: cardWidth, height: contentHeight)

            for (idx, entry) in renderedEntries.enumerated() {
                let col = idx % cols
                let row = idx / cols
                let cellFrame = NSRect(
                    x: padX + CGFloat(col) * cellW,
                    y: padY + CGFloat(row) * cellH,
                    width: cellW,
                    height: cellH
                )
                let cell = buildGridCell(entry: entry, frame: cellFrame, requestThumb: idx < 40, backingScale: backingScale)
                documentView.addSubview(cell)
            }
        }

        let visibleBodyH = min(contentHeight, maxBodyHeight)
        let cardHeight = headerH + visibleBodyH + footerH
        let totalW = cardWidth + shadowPad * 2
        let totalH = cardHeight + shadowPad * 2

        var winOriginX = round(currentAnchorScreenRect.midX - totalW / 2)
        winOriginX = max(screen.frame.minX + 6, min(winOriginX, screen.frame.maxX - totalW - 6))
        let winOriginY = round(currentAnchorScreenRect.maxY + 8 - shadowPad)
        let winFrame = NSRect(x: winOriginX, y: winOriginY, width: totalW, height: totalH)

        let outerRoot = NSView(frame: NSRect(origin: .zero, size: winFrame.size))
        outerRoot.wantsLayer = true

        let shadowCarrier = NSView(frame: NSRect(x: shadowPad, y: shadowPad, width: cardWidth, height: cardHeight))
        shadowCarrier.wantsLayer = true
        shadowCarrier.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.01).cgColor
        shadowCarrier.layer?.cornerRadius = 18
        shadowCarrier.layer?.cornerCurve = .continuous
        shadowCarrier.layer?.shadowColor = NSColor.black.cgColor
        shadowCarrier.layer?.shadowOpacity = 0.34
        shadowCarrier.layer?.shadowRadius = 12
        shadowCarrier.layer?.shadowOffset = CGSize(width: 0, height: -4)
        shadowCarrier.layer?.shadowPath = CGPath(roundedRect: shadowCarrier.bounds, cornerWidth: 18, cornerHeight: 18, transform: nil)
        outerRoot.addSubview(shadowCarrier)

        let card = NSVisualEffectView(frame: NSRect(x: shadowPad, y: shadowPad, width: cardWidth, height: cardHeight))
        card.appearance = NSAppearance(named: .darkAqua)
        card.material = .hudWindow
        card.blendingMode = .behindWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 18
        card.layer?.cornerCurve = .continuous
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 0.85
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
        outerRoot.addSubview(card)

        // Header Bar (top of card)
        let headerY = cardHeight - headerH
        let headerView = buildCardHeader(
            title: folderTitle,
            totalCount: entries.count,
            folderURL: folderURL,
            activeStyle: style,
            width: cardWidth,
            height: headerH
        )
        headerView.frame.origin = NSPoint(x: 0, y: headerY)
        card.addSubview(headerView)

        let divider = NSView(frame: NSRect(x: 12, y: headerY, width: cardWidth - 24, height: 0.75))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        card.addSubview(divider)

        // Scrollable Body
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: footerH, width: cardWidth, height: visibleBodyH))
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = contentHeight > visibleBodyH
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = documentView
        card.addSubview(scrollView)
        documentView.scroll(.zero)

        // Optional Overflow Footer ("N More in Finder…")
        if overflowCount > 0 {
            let footDiv = NSView(frame: NSRect(x: 12, y: footerH - 0.75, width: cardWidth - 24, height: 0.75))
            footDiv.wantsLayer = true
            footDiv.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
            card.addSubview(footDiv)

            let moreBtn = NSButton(title: L10n.stackMoreInFinder(overflowCount), target: self, action: #selector(openActiveFolderInFinder))
            moreBtn.isBordered = false
            moreBtn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            moreBtn.contentTintColor = NSColor.white.withAlphaComponent(0.88)
            moreBtn.frame = NSRect(x: 12, y: 4, width: cardWidth - 24, height: footerH - 8)
            card.addSubview(moreBtn)
        }

        showInPanel(rootView: outerRoot, frame: winFrame, animated: animated)
    }

    private func buildCardHeader(
        title: String,
        totalCount: Int,
        folderURL: URL,
        activeStyle: DockStackStyle,
        width: CGFloat,
        height: CGFloat
    ) -> NSView {
        let header = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        var leftX: CGFloat = 12

        if navigationStack.count > 1 {
            let backBtn = NSButton(frame: NSRect(x: 8, y: 7, width: 28, height: 26))
            backBtn.bezelStyle = .recessed
            backBtn.isBordered = false
            backBtn.toolTip = L10n.stackBackBtn
            if let chev = NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: L10n.stackBackBtn) {
                backBtn.image = chev.withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
                backBtn.contentTintColor = .white
            } else {
                backBtn.title = "‹"
            }
            backBtn.target = self
            backBtn.action = #selector(navigateBackInStack)
            header.addSubview(backBtn)
            leftX = 36
        }

        // Right controls: Grid | List | Open in Finder
        let openBtn = NSButton(frame: NSRect(x: width - 36, y: 7, width: 26, height: 26))
        openBtn.isBordered = false
        openBtn.toolTip = L10n.openInFinder
        if let sym = NSImage(systemSymbolName: "arrow.up.forward.square", accessibilityDescription: L10n.openInFinder) {
            openBtn.image = sym.withSymbolConfiguration(.init(pointSize: 13.5, weight: .medium))
            openBtn.contentTintColor = NSColor.white.withAlphaComponent(0.88)
        }
        openBtn.target = self
        openBtn.action = #selector(openActiveFolderInFinder)
        header.addSubview(openBtn)

        let listBtn = NSButton(frame: NSRect(x: width - 64, y: 7, width: 26, height: 26))
        listBtn.isBordered = false
        listBtn.toolTip = L10n.stackStyleList
        if let sym = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: L10n.stackStyleList) {
            listBtn.image = sym.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
            listBtn.contentTintColor = NSColor.white.withAlphaComponent(activeStyle == .list ? 1.0 : 0.48)
        }
        listBtn.target = self
        listBtn.action = #selector(switchSessionToList)
        header.addSubview(listBtn)

        let gridBtn = NSButton(frame: NSRect(x: width - 90, y: 7, width: 26, height: 26))
        gridBtn.isBordered = false
        gridBtn.toolTip = L10n.stackStyleGrid
        if let sym = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: L10n.stackStyleGrid) {
            gridBtn.image = sym.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
            gridBtn.contentTintColor = NSColor.white.withAlphaComponent(activeStyle == .grid ? 1.0 : 0.48)
        }
        gridBtn.target = self
        gridBtn.action = #selector(switchSessionToGrid)
        header.addSubview(gridBtn)

        let titleField = NSTextField(labelWithString: "\(title) (\(totalCount))")
        titleField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleField.textColor = .white
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.frame = NSRect(x: leftX, y: 10, width: max(60, (width - 96) - leftX), height: 19)
        header.addSubview(titleField)

        return header
    }

    private func buildGridCell(
        entry: FolderStackEntry,
        frame: NSRect,
        requestThumb: Bool,
        backingScale: CGFloat
    ) -> NSView {
        let cell = DraggableStackItemControl(entry: entry, frame: frame)
        cell.layer?.cornerRadius = 10
        cell.layer?.cornerCurve = .continuous

        let iconSz: CGFloat = 50
        let imgView = NSImageView(frame: NSRect(
            x: round((frame.width - iconSz) / 2),
            y: 8,
            width: iconSz,
            height: iconSz
        ))
        imgView.imageScaling = .scaleProportionallyUpOrDown
        imgView.image = StackThumbnailProvider.shared.immediateIcon(for: entry)
        cell.addSubview(imgView)

        if requestThumb {
            StackThumbnailProvider.shared.requestThumbnailIfHelpful(for: entry, pixelSize: 64, scale: backingScale) { [weak imgView] thumb in
                imgView?.image = thumb
            }
        }

        let nameField = NSTextField(wrappingLabelWithString: entry.displayName)
        nameField.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        nameField.textColor = .white
        nameField.alignment = .center
        nameField.maximumNumberOfLines = 2
        nameField.cell?.truncatesLastVisibleLine = true
        nameField.cell?.lineBreakMode = .byTruncatingMiddle
        nameField.frame = NSRect(x: 5, y: 61, width: frame.width - 10, height: 29)
        cell.addSubview(nameField)
        cell.toolTip = entry.displayName

        cell.onHoverChange = { [weak cell] hovered in
            cell?.layer?.backgroundColor = hovered
                ? NSColor.white.withAlphaComponent(0.14).cgColor
                : NSColor.clear.cgColor
        }
        cell.onActivate = { [weak self] flags in
            self?.handleEntryClick(entry, modifiers: flags)
        }
        return cell
    }

    private func buildListRow(
        entry: FolderStackEntry,
        frame: NSRect,
        requestThumb: Bool,
        backingScale: CGFloat
    ) -> NSView {
        let row = DraggableStackItemControl(entry: entry, frame: frame)
        row.layer?.cornerRadius = 7
        row.layer?.cornerCurve = .continuous

        let imgView = NSImageView(frame: NSRect(x: 8, y: 5, width: 24, height: 24))
        imgView.imageScaling = .scaleProportionallyUpOrDown
        imgView.image = StackThumbnailProvider.shared.immediateIcon(for: entry)
        row.addSubview(imgView)

        if requestThumb {
            StackThumbnailProvider.shared.requestThumbnailIfHelpful(for: entry, pixelSize: 32, scale: backingScale) { [weak imgView] thumb in
                imgView?.image = thumb
            }
        }

        let rightMargin: CGFloat = entry.isSubfolder ? 26 : 10
        let nameField = NSTextField(labelWithString: entry.displayName)
        nameField.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        nameField.textColor = .white
        nameField.lineBreakMode = .byTruncatingMiddle
        nameField.frame = NSRect(x: 40, y: 8, width: frame.width - 40 - rightMargin, height: 18)
        row.addSubview(nameField)

        if entry.isSubfolder,
           let chev = NSImage(systemSymbolName: "chevron.forward", accessibilityDescription: nil) {
            let chevView = NSImageView(frame: NSRect(x: frame.width - 20, y: 10, width: 12, height: 14))
            chevView.image = chev.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
            chevView.contentTintColor = NSColor.white.withAlphaComponent(0.55)
            row.addSubview(chevView)
        }

        row.onHoverChange = { [weak row] hovered in
            row?.layer?.backgroundColor = hovered
                ? NSColor.white.withAlphaComponent(0.15).cgColor
                : NSColor.clear.cgColor
        }
        row.onActivate = { [weak self] flags in
            self?.handleEntryClick(entry, modifiers: flags)
        }
        return row
    }

    // MARK: - Window Hosting & Actions

    private func showInPanel(rootView: NSView, frame: NSRect, animated: Bool) {
        if let existing = panel {
            existing.ignoresMouseEvents = false
            existing.contentView = rootView
            existing.setFrame(frame, display: true, animate: false)
            existing.alphaValue = 1.0
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let newPanel = FolderStackPanel(contentRect: frame)
        newPanel.contentView = rootView
        newPanel.onEscapePressed = { [weak self] in
            self?.dismiss(animated: true)
        }
        panel = newPanel

        if animated {
            let startFrame = frame.offsetBy(dx: 0, dy: -8)
            newPanel.setFrame(startFrame, display: false)
            newPanel.alphaValue = 0.0
            newPanel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.20, 0.92, 0.25, 1.0)
                newPanel.animator().setFrame(frame, display: true)
                newPanel.animator().alphaValue = 1.0
            }
        } else {
            newPanel.alphaValue = 1.0
            newPanel.makeKeyAndOrderFront(nil)
        }
    }

    private func handleEntryClick(_ entry: FolderStackEntry, modifiers: NSEvent.ModifierFlags) {
        let clean = modifiers.intersection(.deviceIndependentFlagsMask)
        if clean.contains(.command) {
            dismiss(animated: true)
            NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            return
        }

        if entry.isSubfolder && !clean.contains(.option) {
            // Drill into subfolder inside the popover (⌥-click opens the subfolder directly in Finder)
            navigationStack.append((url: entry.url, title: entry.displayName))
            renderCurrentFolder(animated: false)
            return
        }

        dismiss(animated: true)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(entry.url, configuration: config, completionHandler: nil)
    }

    @objc private func navigateBackInStack() {
        guard navigationStack.count > 1 else { return }
        navigationStack.removeLast()
        renderCurrentFolder(animated: false)
    }

    @objc private func switchSessionToGrid() {
        sessionStyleOverride = .grid
        renderCurrentFolder(animated: false)
    }

    @objc private func switchSessionToList() {
        sessionStyleOverride = .list
        renderCurrentFolder(animated: false)
    }

    @objc private func openActiveFolderInFinder() {
        guard let target = navigationStack.last?.url ?? rootFolderURL else { return }
        dismiss(animated: true)
        openInFinder(target)
    }

    func openInFinder(_ url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(url, configuration: config, completionHandler: nil)
    }

    // MARK: - Click-Outside & Workspace Dismissal Monitors

    private func installClickOutsideMonitors() {
        removeClickOutsideMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.handlePotentialOutsideClick()
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self = self, !self.isDraggingFile, let stackWin = self.panel else { return event }
            if event.window === stackWin {
                // In Fan mode, clicking transparent empty area where hitTest == nil should dismiss immediately
                if stackWin.hitInteractiveView(atWindowPoint: event.locationInWindow) == nil {
                    self.dismiss(animated: true)
                }
                return event
            }
            // If clicking the exact folder tile that opened this stack, let DockTileView.mouseDown handle toggling
            if let barWin = self.activeBarPanel, event.window === barWin {
                return event
            }
            self.dismiss(animated: true)
            return event
        }
    }

    private func handlePotentialOutsideClick() {
        guard !isDraggingFile, let stackWin = panel, stackWin.isVisible else { return }
        let pt = NSEvent.mouseLocation
        if stackWin.frame.contains(pt) {
            let winPt = stackWin.convertPoint(fromScreen: pt)
            if stackWin.hitInteractiveView(atWindowPoint: winPt) != nil {
                return
            }
        }
        dismiss(animated: true)
    }

    private func removeClickOutsideMonitors() {
        if let g = globalMouseMonitor {
            NSEvent.removeMonitor(g)
            globalMouseMonitor = nil
        }
        if let l = localMouseMonitor {
            NSEvent.removeMonitor(l)
            localMouseMonitor = nil
        }
    }

    private func installWorkspaceObserversIfNeeded() {
        guard !workspaceObserversInstalled else { return }
        workspaceObserversInstalled = true

        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(self, selector: #selector(dismissFromSystemEvent), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(dismissFromSystemEvent), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(dismissFromSystemEvent), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func dismissFromSystemEvent() {
        if isVisible {
            dismiss(animated: false)
        }
    }
}
