import Cocoa
import QuartzCore

// MARK: - Subtle Bottom Edge Hint Pill (for Auto-Hide Mode)

final class EdgeHintPanel: NSPanel {
    private static let winWidth: CGFloat = 120
    private static let winHeight: CGFloat = 12

    init(screen: NSScreen) {
        let rect = NSRect(
            x: round(screen.frame.midX - Self.winWidth / 2),
            y: round(screen.frame.minY + 2),
            width: Self.winWidth,
            height: Self.winHeight
        )
        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        applyCollectionBehavior()

        let root = NSView(frame: NSRect(x: 0, y: 0, width: Self.winWidth, height: Self.winHeight))
        root.wantsLayer = true
        root.layer?.masksToBounds = false
        contentView = root

        // Cápsula exterior suave para mantener legibilidad discreta sobre fondos claros
        let outerFrame = NSRect(x: 6, y: 3, width: Self.winWidth - 12, height: 4.5)
        let outerTrack = NSView(frame: outerFrame)
        outerTrack.wantsLayer = true
        outerTrack.layer?.cornerRadius = 2.25
        outerTrack.layer?.cornerCurve = .continuous
        outerTrack.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.30).cgColor
        outerTrack.layer?.shadowColor = NSColor.black.cgColor
        outerTrack.layer?.shadowOpacity = 0.24
        outerTrack.layer?.shadowRadius = 2.0
        outerTrack.layer?.shadowOffset = CGSize(width: 0, height: -0.5)
        root.addSubview(outerTrack)

        // Núcleo interior translúcido equilibrado (visible pero discreto)
        let innerPill = NSView(frame: NSRect(x: 0.75, y: 0.75, width: outerFrame.width - 1.5, height: outerFrame.height - 1.5))
        innerPill.wantsLayer = true
        innerPill.layer?.cornerRadius = 1.5
        innerPill.layer?.cornerCurve = .continuous
        innerPill.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.54).cgColor
        outerTrack.addSubview(innerPill)
    }

    func applyCollectionBehavior() {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if DockSettings.shared.showOverFullScreen {
            behavior.insert(.fullScreenAuxiliary)
        }
        collectionBehavior = behavior
    }

    func updatePosition(on screen: NSScreen) {
        applyCollectionBehavior()
        let target = NSRect(
            x: round(screen.frame.midX - Self.winWidth / 2),
            y: round(screen.frame.minY + 2),
            width: Self.winWidth,
            height: Self.winHeight
        )
        if frame != target {
            setFrame(target, display: true)
        }
    }
}

// MARK: - Floating Label Bubble (macOS Dock Style)

final class HoverBubbleController {
    static let shared = HoverBubbleController()

    private let panel: NSPanel
    private let labelField: NSTextField
    private let effectView: NSVisualEffectView

    private init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 28),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 2)
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        effectView = NSVisualEffectView(frame: panel.contentView!.bounds)
        effectView.autoresizingMask = [.width, .height]
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 8
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 0.75
        effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor

        labelField = NSTextField(labelWithString: "")
        labelField.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        labelField.textColor = .labelColor
        labelField.alignment = .center
        labelField.lineBreakMode = .byTruncatingTail

        effectView.addSubview(labelField)
        panel.contentView?.addSubview(effectView)
    }

    func show(text: String, above screenRect: NSRect, on screen: NSScreen?) {
        guard !text.isEmpty else {
            hide()
            return
        }
        labelField.stringValue = text
        labelField.sizeToFit()

        let padX: CGFloat = 11
        let padY: CGFloat = 4.5
        let width = min(max(labelField.frame.width + padX * 2, 46), 300)
        let height = labelField.frame.height + padY * 2

        labelField.frame = NSRect(
            x: padX,
            y: padY,
            width: width - padX * 2,
            height: labelField.frame.height
        )

        var originX = screenRect.midX - width / 2
        if let screenFrame = screen?.frame {
            originX = max(screenFrame.minX + 8, min(originX, screenFrame.maxX - width - 8))
        }
        let originY = screenRect.maxY + 10

        panel.setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

// MARK: - Individual Dock Tile View

final class DockTileView: NSView {
    private(set) var item: DockItem
    private let iconSize: CGFloat
    private let tilePadX: CGFloat
    private let imageView = NSImageView()
    private let dotLayer = CALayer()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(item: DockItem, iconSize: CGFloat, tilePadX: CGFloat = 2.5) {
        self.item = item
        self.iconSize = iconSize
        self.tilePadX = tilePadX
        let width = iconSize + tilePadX * 2
        let height = iconSize + 14
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        wantsLayer = true
        layer?.masksToBounds = false

        imageView.image = item.icon
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.setAccessibilityElement(false)
        imageView.frame = NSRect(x: tilePadX, y: 9, width: iconSize, height: iconSize)
        addSubview(imageView)

        dotLayer.bounds = CGRect(x: 0, y: 0, width: 4.5, height: 4.5)
        dotLayer.position = CGPoint(x: width / 2, y: 3.5)
        dotLayer.cornerRadius = 2.25
        updateRunningDot()
        layer?.addSublayer(dotLayer)

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        updateAccessibilityAttributes()

        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Updates running/frontmost state or Trash icon in-place without tearing down animations or hover tracking.
    func update(item newItem: DockItem) {
        let oldKind = self.item.kind
        self.item = newItem
        if oldKind != newItem.kind {
            imageView.image = newItem.icon
        }
        updateRunningDot()
        updateAccessibilityAttributes()
    }

    private func updateAccessibilityAttributes() {
        setAccessibilityLabel(item.label)
        setAccessibilityValue(item.isRunning ? L10n.runningAccessibilityState : nil)
    }

    override func accessibilityPerformPress() -> Bool {
        activateItem(withModifiers: [])
        return true
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

    private func updateRunningDot() {
        if item.isRunning {
            dotLayer.isHidden = false
            dotLayer.backgroundColor = (item.isFrontmost
                ? NSColor.white.withAlphaComponent(0.96)
                : NSColor.white.withAlphaComponent(0.62)).cgColor
        } else {
            dotLayer.isHidden = true
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard let barPanel = window as? DockBarPanel, barPanel.isRevealed else { return }
        isHovered = true
        if DockSettings.shared.hoverMagnification {
            animateHover(hovered: true)
        }
        let rectInWin = convert(imageView.frame, to: nil)
        let screenRect = barPanel.convertToScreen(rectInWin)
        HoverBubbleController.shared.show(text: item.label, above: screenRect, on: barPanel.screen)
    }

    override func mouseExited(with event: NSEvent) {
        resetHoverVisuals()
    }

    func resetHoverVisuals() {
        isHovered = false
        animateHover(hovered: false)
        HoverBubbleController.shared.hide()
    }

    private func animateHover(hovered: Bool) {
        let scale: CGFloat = hovered ? 1.18 : 1.0
        let lift: CGFloat = hovered ? 4.0 : 0.0

        let baseFrame = NSRect(x: tilePadX, y: 9, width: iconSize, height: iconSize)
        let newSize = iconSize * scale
        let dx = (newSize - iconSize) / 2.0

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            imageView.animator().frame = NSRect(
                x: baseFrame.minX - dx,
                y: baseFrame.minY + lift,
                width: newSize,
                height: newSize
            )
        }
    }

    private func animateClickBounce() {
        let current = imageView.frame
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            imageView.animator().frame = current.offsetBy(dx: 0, dy: 6)
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                let scale: CGFloat = (self.isHovered && DockSettings.shared.hoverMagnification) ? 1.18 : 1.0
                let lift: CGFloat = (self.isHovered && DockSettings.shared.hoverMagnification) ? 4.0 : 0.0
                let newSize = self.iconSize * scale
                let dx = (newSize - self.iconSize) / 2.0
                self.imageView.animator().frame = NSRect(
                    x: self.tilePadX - dx,
                    y: 9 + lift,
                    width: newSize,
                    height: newSize
                )
            }
        })
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
            return
        }
        animateClickBounce()
        HoverBubbleController.shared.hide()
        activateItem(withModifiers: event.modifierFlags)
    }

    override func rightMouseDown(with event: NSEvent) {
        HoverBubbleController.shared.hide()
        let barPanel = window as? DockBarPanel
        barPanel?.isContextMenuOpen = true
        defer { barPanel?.isContextMenuOpen = false }
        let menu = buildContextMenu()
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    // MARK: - Actions

    private func activateItem(withModifiers flags: NSEvent.ModifierFlags) {
        let cleanMods = flags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])

        switch item.kind {
        case .finder:
            openFinder(withModifiers: cleanMods)

        case .application(let bundleID, let url):
            let running = DockModelReader.findRunningApplication(bundleID: bundleID, url: url)
            let action = DockLayoutMath.planApplicationClick(
                plistURL: url,
                runningBundleURL: running?.bundleURL,
                isRunning: running != nil,
                isActive: running?.isActive ?? false,
                isHidden: running?.isHidden ?? false,
                modifiers: cleanMods
            )

            switch action {
            case .revealInFinder(let targetURL):
                NSWorkspace.shared.activateFileViewerSelecting([targetURL])

            case .hideRunningApp:
                running?.hide()

            case .reopenAndActivate(let targetURL, let unhideFirst, let hidesOthers):
                if unhideFirst {
                    running?.unhide()
                }
                // Always route through LaunchServices (`openApplication`) with `createsNewApplicationInstance = false`
                // rather than bare `NSRunningApplication.activate()`:
                // 1) Sends `kAEReopenApplication` ('rapp') so apps that are running with closed (⌘W) or
                //    minimized (⌘M) windows reopen/deminiaturize their window just like Apple's native Dock.
                // 2) Grants full WindowServer foreground handoff from a `.nonactivatingPanel` LSUIElement on
                //    macOS 14+, where cooperative `running.activate()` silently fails to unhide/foreground.
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                config.createsNewApplicationInstance = false
                config.hidesOthers = hidesOthers
                NSWorkspace.shared.openApplication(at: targetURL, configuration: config) { [weak running] _, err in
                    guard err != nil else { return }
                    DispatchQueue.main.async {
                        if let running = running, !running.isTerminated {
                            running.unhide()
                            _ = running.activate(options: [.activateAllWindows])
                        } else if !FileManager.default.fileExists(atPath: url.path) {
                            DockModelReader.shared.reloadPlistCache()
                            MultiScreenController.shared.refreshAll(forceLayout: true)
                        }
                    }
                }
            }

        case .directoryOrFile(let url, _):
            if cleanMods.contains(.command) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.open(url, configuration: config, completionHandler: nil)
            }

        case .trash:
            openTrash()

        case .separator:
            break
        }
    }

    private func openFinder(withModifiers cleanMods: NSEvent.ModifierFlags = []) {
        let finderApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        if let finderApp = finderApp, finderApp.isActive && !finderApp.isHidden && cleanMods.contains(.option) {
            finderApp.hide()
            return
        }
        if finderApp?.isHidden == true {
            finderApp?.unhide()
        }
        let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = false
        config.hidesOthers = cleanMods.contains(.option)
        NSWorkspace.shared.openApplication(at: finderURL, configuration: config, completionHandler: nil)
    }

    private func openTrash() {
        if let trashURL = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open(trashURL, configuration: config, completionHandler: nil)
        }
    }

    // MARK: - Context Menu

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu(title: item.label)
        menu.autoenablesItems = false

        switch item.kind {
        case .finder:
            let newWin = NSMenuItem(title: L10n.newFinderWindow, action: #selector(ctxNewFinderWindow), keyEquivalent: "")
            newWin.target = self
            menu.addItem(newWin)

        case .application(let bundleID, let url):
            let openItem = NSMenuItem(title: item.isRunning ? L10n.showApp(item.label) : L10n.openApp(item.label), action: #selector(ctxOpenPrimary), keyEquivalent: "")
            openItem.target = self
            menu.addItem(openItem)

            let reveal = NSMenuItem(title: L10n.showInFinder, action: #selector(ctxRevealInFinder), keyEquivalent: "")
            reveal.representedObject = url
            reveal.target = self
            menu.addItem(reveal)

            if let running = DockModelReader.findRunningApplication(bundleID: bundleID, url: url) {
                menu.addItem(.separator())
                let hideItem = NSMenuItem(title: running.isHidden ? L10n.showSingle : L10n.hideSingle, action: #selector(ctxToggleHideApp(_:)), keyEquivalent: "")
                hideItem.representedObject = running
                hideItem.target = self
                menu.addItem(hideItem)

                let quitItem = NSMenuItem(title: L10n.quitTargetApp(item.label), action: #selector(ctxQuitApp(_:)), keyEquivalent: "")
                quitItem.representedObject = running
                quitItem.target = self
                menu.addItem(quitItem)
            }

        case .directoryOrFile(let url, let isDir):
            let openTitle = isDir ? L10n.openInFinder : L10n.openGeneric
            let openItem = NSMenuItem(title: openTitle, action: #selector(ctxOpenPrimary), keyEquivalent: "")
            openItem.target = self
            menu.addItem(openItem)

            let reveal = NSMenuItem(title: L10n.showContainerInFinder, action: #selector(ctxRevealInFinder), keyEquivalent: "")
            reveal.representedObject = url
            reveal.target = self
            menu.addItem(reveal)

        case .trash(let isFull):
            let openItem = NSMenuItem(title: L10n.openTrash, action: #selector(ctxOpenPrimary), keyEquivalent: "")
            openItem.target = self
            menu.addItem(openItem)

            let emptyItem = NSMenuItem(title: L10n.emptyTrash, action: #selector(ctxEmptyTrash), keyEquivalent: "")
            emptyItem.target = self
            emptyItem.isEnabled = isFull
            menu.addItem(emptyItem)

        case .separator:
            break
        }

        if let settingsMenu = AppDelegate.shared?.buildFreshSettingsMenu(includeShortcuts: false) {
            menu.addItem(.separator())
            let subItem = NSMenuItem(title: L10n.dockSettingsSubmenu, action: nil, keyEquivalent: "")
            subItem.submenu = settingsMenu
            menu.addItem(subItem)
        }

        return menu
    }

    @objc private func ctxOpenPrimary() {
        activateItem(withModifiers: [])
    }

    @objc private func ctxNewFinderWindow() {
        let script = "tell application \"Finder\" to make new Finder window to home\ntell application \"Finder\" to activate"
        if let ascript = NSAppleScript(source: script) {
            var err: NSDictionary?
            ascript.executeAndReturnError(&err)
        }
    }

    @objc private func ctxRevealInFinder(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc private func ctxToggleHideApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? NSRunningApplication else { return }
        if app.isHidden {
            app.unhide()
            if let appURL = app.bundleURL {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                config.createsNewApplicationInstance = false
                NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
            } else {
                _ = app.activate(options: [.activateAllWindows])
            }
        } else {
            app.hide()
        }
    }

    @objc private func ctxQuitApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? NSRunningApplication else { return }
        app.terminate()
    }

    @objc private func ctxEmptyTrash() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.emptyTrashConfirmTitle
        alert.informativeText = L10n.emptyTrashConfirmMessage
        let emptyBtn = alert.addButton(withTitle: L10n.emptyTrashConfirmBtn)
        emptyBtn.hasDestructiveAction = true
        let cancelBtn = alert.addButton(withTitle: L10n.cancelBtn)
        cancelBtn.keyEquivalent = "\u{1b}"
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let script = "tell application \"Finder\" to empty trash"
        if let ascript = NSAppleScript(source: script) {
            var err: NSDictionary?
            ascript.executeAndReturnError(&err)
        }
    }

    // MARK: - Drag & Drop Support

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let mask = sender.draggingSourceOperationMask
        switch item.kind {
        case .application, .trash:
            guard !mask.isEmpty else { return [] }
            animateHover(hovered: true)
            return .generic
        case .directoryOrFile(_, let isDir) where isDir:
            if mask.contains(.move) {
                animateHover(hovered: true)
                return .move
            } else if mask.contains(.copy) {
                animateHover(hovered: true)
                return .copy
            }
            return []
        default:
            return []
        }
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        animateHover(hovered: false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        animateHover(hovered: false)
        let mask = sender.draggingSourceOperationMask
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else {
            return false
        }

        switch item.kind {
        case .application(_, let appURL):
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: config) { _, err in
                if let err = err {
                    DispatchQueue.main.async {
                        Self.presentDragErrorAlert(title: L10n.dragOpenErrorTitle, details: [err.localizedDescription])
                    }
                }
            }
            return true

        case .directoryOrFile(let folderURL, let isDir) where isDir:
            let folderStd = folderURL.standardizedFileURL
            let actionable = urls.filter { fileURL in
                let srcStd = fileURL.standardizedFileURL
                return srcStd != folderStd && srcStd.deletingLastPathComponent() != folderStd
            }
            guard !actionable.isEmpty else { return false }

            let forceCopy = !mask.contains(.move) && mask.contains(.copy)
            let destVol = try? folderURL.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject

            DispatchQueue.global(qos: .userInitiated).async {
                var failures: [String] = []
                var anyCopied = false
                for fileURL in actionable {
                    let dest = folderURL.appendingPathComponent(fileURL.lastPathComponent)
                    let srcVol = try? fileURL.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
                    let crossVolume = (destVol != nil && srcVol != nil && destVol != srcVol)
                    let shouldCopy = forceCopy || crossVolume
                    if shouldCopy { anyCopied = true }
                    do {
                        if shouldCopy {
                            try FileManager.default.copyItem(at: fileURL, to: dest)
                        } else {
                            try FileManager.default.moveItem(at: fileURL, to: dest)
                        }
                    } catch {
                        failures.append("• \(fileURL.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                if !failures.isEmpty {
                    let title = anyCopied ? L10n.dragCopyErrorTitle : L10n.dragMoveErrorTitle
                    DispatchQueue.main.async {
                        Self.presentDragErrorAlert(title: title, details: failures)
                    }
                }
            }
            return true

        case .trash:
            DispatchQueue.global(qos: .userInitiated).async {
                var failures: [String] = []
                for fileURL in urls {
                    do {
                        try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
                    } catch {
                        failures.append("• \(fileURL.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                if !failures.isEmpty {
                    DispatchQueue.main.async {
                        Self.presentDragErrorAlert(title: L10n.dragTrashErrorTitle, details: failures)
                    }
                }
            }
            return true

        default:
            return false
        }
    }

    private static func presentDragErrorAlert(title: String, details: [String]) {
        NSSound.beep()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = details.prefix(6).joined(separator: "\n")
        alert.addButton(withTitle: L10n.okBtn)
        alert.runModal()
    }
}

// MARK: - Pure Dock Layout & Auto-Hide Geometry Engine

enum DockLayoutMath {
    static func tilePadAndGap(for iconSize: CGFloat) -> (pad: CGFloat, gap: CGFloat) {
        if iconSize >= 34 {
            return (2.5, 2.0)
        } else {
            return (1.5, 1.0)
        }
    }

    static func barSize(for items: [DockItem], iconSize: CGFloat) -> NSSize {
        let padX: CGFloat = 9
        let pg = tilePadAndGap(for: iconSize)
        var cursorX: CGFloat = padX
        var lastWasTile = false
        for item in items {
            if item.kind == .separator {
                if lastWasTile {
                    cursorX -= pg.gap
                }
                cursorX += 11
                lastWasTile = false
            } else {
                cursorX += (iconSize + pg.pad * 2) + pg.gap
                lastWasTile = true
            }
        }
        if lastWasTile {
            cursorX -= pg.gap
        }
        let barWidth = max(60, cursorX + padX)
        let barHeight = iconSize + 16
        return NSSize(width: barWidth, height: barHeight)
    }

    /// Computes the largest icon size <= preferred whose rendered bar width fits within maxWidth,
    /// using the exact same `barSize(for:iconSize:)` calculation used during layout.
    static func computeEffectiveIconSize(items: [DockItem], preferred: CGFloat, maxWidth: CGFloat) -> CGFloat {
        guard items.contains(where: { $0.kind != .separator }) else { return preferred }
        if barSize(for: items, iconSize: preferred).width <= maxWidth {
            return preferred
        }

        var candidate = floor(preferred)
        while candidate > 20 {
            if barSize(for: items, iconSize: candidate).width <= maxWidth {
                return candidate
            }
            candidate -= 1
        }
        // Preserve 20 pt floor unless even 20 pt would overflow the display width
        if barSize(for: items, iconSize: 20).width <= maxWidth {
            return 20
        }
        candidate = 19
        while candidate > 14 {
            if barSize(for: items, iconSize: candidate).width <= maxWidth {
                return candidate
            }
            candidate -= 1
        }
        return 14
    }

    static func triggerZone(screenFrame: NSRect, barSize: NSSize, hasScreenBelow: Bool) -> NSRect {
        let minTriggerWidth = min(screenFrame.width - 24, screenFrame.width * 0.45)
        let width = max(60, min(screenFrame.width - 24, max(minTriggerWidth, barSize.width + 64)))
        let height: CGFloat = hasScreenBelow ? 26.0 : 20.0
        return NSRect(
            x: round(screenFrame.midX - width / 2),
            y: screenFrame.minY,
            width: width,
            height: height
        )
    }

    /// Always forms a strict geometric superset of `triggerZone` so resting the pointer anywhere inside
    /// the bottom trigger strip can never oscillate between reveal and hide.
    static func keepAliveZone(screenFrame: NSRect, barSize: NSSize, bottomMargin: CGFloat) -> NSRect {
        let maxTrigger = triggerZone(screenFrame: screenFrame, barSize: barSize, hasScreenBelow: true)
        let barKeepWidth = min(screenFrame.width, max(maxTrigger.width + 16, barSize.width + 80))
        let barKeepHeight = max(maxTrigger.height + 12, bottomMargin + barSize.height + 24)
        let barKeep = NSRect(
            x: round(screenFrame.midX - barKeepWidth / 2),
            y: screenFrame.minY,
            width: barKeepWidth,
            height: barKeepHeight
        )
        return barKeep.union(maxTrigger)
    }

    /// Structural identity of the Dock bar layout (excluding transient running/frontmost dots or empty/full Trash icon).
    /// Allows `DockBarPanel` to update running indicators in-place without destroying views or interrupting animations.
    static func structuralSignature(for items: [DockItem]) -> [String] {
        items.map { item in
            switch item.kind {
            case .finder:
                return "finder|\(item.id)|\(item.label)"
            case .application(let bid, let url):
                return "app|\(item.id)|\(item.label)|\(bid ?? "")|\(url.path)"
            case .directoryOrFile(let url, let isDir):
                return "item|\(item.id)|\(item.label)|\(url.path)|\(isDir)"
            case .separator:
                return "sep|\(item.id)"
            case .trash:
                return "trash|\(item.id)|\(item.label)"
            }
        }
    }

    static func hasMonitorDirectlyBelow(targetFrame: NSRect, among screenFrames: [NSRect]) -> Bool {
        for other in screenFrames where other != targetFrame {
            let verticalTouch = abs(other.maxY - targetFrame.minY) <= 14.0
            let overlapX = min(targetFrame.maxX, other.maxX) - max(targetFrame.minX, other.minX)
            if verticalTouch && overlapX > 40.0 {
                return true
            }
        }
        return false
    }

    enum ApplicationClickAction: Equatable {
        case revealInFinder(URL)
        case hideRunningApp
        case reopenAndActivate(url: URL, unhideFirst: Bool, hidesOthers: Bool)
    }

    /// Plans how clicking an application tile should dispatch to Finder / NSRunningApplication / LaunchServices
    /// so hidden (`⌘H`), minimized (`⌘M`), and closed-window (`⌘W`) running apps always reopen and foreground
    /// identically to Apple's native macOS Dock.
    static func planApplicationClick(
        plistURL: URL,
        runningBundleURL: URL?,
        isRunning: Bool,
        isActive: Bool,
        isHidden: Bool,
        modifiers: NSEvent.ModifierFlags
    ) -> ApplicationClickAction {
        let resolvedURL = runningBundleURL ?? plistURL
        if modifiers.contains(.command) {
            return .revealInFinder(resolvedURL)
        }
        let optionHeld = modifiers.contains(.option)
        if isRunning && isActive && !isHidden && optionHeld {
            return .hideRunningApp
        }
        return .reopenAndActivate(
            url: resolvedURL,
            unhideFirst: isRunning && isHidden,
            hidesOthers: optionHeld
        )
    }

    static func hasMonitorDirectlyAbove(targetFrame: NSRect, among screenFrames: [NSRect]) -> Bool {
        for other in screenFrames where other != targetFrame {
            let verticalTouch = abs(other.minY - targetFrame.maxY) <= 14.0
            let overlapX = min(targetFrame.maxX, other.maxX) - max(targetFrame.minX, other.minX)
            if verticalTouch && overlapX > 40.0 {
                return true
            }
        }
        return false
    }
}

final class ClippedPassthroughRootView: NSView {
    weak var slidingContainer: NSView?
    weak var barBackgroundView: NSView?
    weak var tilesContainerView: NSView?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let sliding = slidingContainer else { return nil }
        let ptInSliding = convert(point, to: sliding)

        if let container = tilesContainerView {
            let ptInTiles = sliding.convert(ptInSliding, to: container)
            for sub in container.subviews {
                if sub is DockTileView, sub.frame.contains(ptInTiles) {
                    return sub
                }
            }
        }
        if let bg = barBackgroundView, bg.frame.contains(ptInSliding) {
            return bg
        }
        return nil
    }
}

final class DockBarPanel: NSPanel {
    var isContextMenuOpen = false
    private(set) var isRevealed = false
    private var animationToken: Int = 0

    private let sideShadowPad: CGFloat = 14
    private let topHeadroom: CGFloat = 20

    private let slidingContainer = NSView()
    private let shadowCarrier = NSView()
    private let backgroundView = NSVisualEffectView()
    private let itemsContainer = NSView()

    private var currentItems: [DockItem] = []
    private var lastStructuralSignature: [String] = []
    private var lastEffectiveIconSize: CGFloat = 0
    private(set) var currentBarSize: NSSize = NSSize(width: 400, height: 52)

    init(screen: NSScreen) {
        super.init(
            contentRect: NSRect(x: screen.frame.midX - 200, y: screen.frame.minY, width: 400, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // Sombra gestionada por CALayer dentro de slidingContainer para recortar limpio en monitores apilados
        hidesOnDeactivate = false
        isMovable = false
        acceptsMouseMovedEvents = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        applyCollectionBehavior()

        let root = ClippedPassthroughRootView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
        root.wantsLayer = true
        root.layer?.masksToBounds = true // Evita que la animación invada jamás el monitor inferior
        root.slidingContainer = slidingContainer
        root.barBackgroundView = backgroundView
        root.tilesContainerView = itemsContainer
        contentView = root

        slidingContainer.wantsLayer = true
        slidingContainer.layer?.masksToBounds = false
        root.addSubview(slidingContainer)

        shadowCarrier.wantsLayer = true
        shadowCarrier.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.01).cgColor
        shadowCarrier.layer?.cornerRadius = 17
        shadowCarrier.layer?.cornerCurve = .continuous
        shadowCarrier.layer?.shadowColor = NSColor.black.cgColor
        shadowCarrier.layer?.shadowOpacity = 0.24
        shadowCarrier.layer?.shadowRadius = 10
        shadowCarrier.layer?.shadowOffset = CGSize(width: 0, height: -3)
        slidingContainer.addSubview(shadowCarrier)

        backgroundView.appearance = NSAppearance(named: .darkAqua)
        backgroundView.material = .hudWindow
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 17
        backgroundView.layer?.cornerCurve = .continuous
        backgroundView.layer?.masksToBounds = true
        backgroundView.layer?.borderWidth = 0.8
        backgroundView.layer?.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
        slidingContainer.addSubview(backgroundView)

        itemsContainer.wantsLayer = true
        itemsContainer.layer?.masksToBounds = false
        slidingContainer.addSubview(itemsContainer)
    }

    override func rightMouseDown(with event: NSEvent) {
        presentDockSettingsMenu(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            presentDockSettingsMenu(with: event)
            return
        }
        super.mouseDown(with: event)
    }

    private func presentDockSettingsMenu(with event: NSEvent) {
        guard let settingsMenu = AppDelegate.shared?.buildFreshSettingsMenu(includeShortcuts: true),
              let targetView = contentView else { return }
        HoverBubbleController.shared.hide()
        isContextMenuOpen = true
        defer { isContextMenuOpen = false }
        NSMenu.popUpContextMenu(settingsMenu, with: event, for: targetView)
    }

    func applyCollectionBehavior() {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if DockSettings.shared.showOverFullScreen {
            behavior.insert(.fullScreenAuxiliary)
        }
        collectionBehavior = behavior
    }

    func updateContentAndGeometry(items: [DockItem], on screen: NSScreen, forceLayout: Bool = false) {
        applyCollectionBehavior()

        let preferredSize = DockSettings.shared.iconSize
        let maxBarWidth = screen.frame.width * 0.97
        let effectiveSize = computeEffectiveIconSize(items: items, preferred: preferredSize, maxWidth: maxBarWidth)
        let signature = DockLayoutMath.structuralSignature(for: items)

        let needsStructuralRebuild = forceLayout
            || signature != lastStructuralSignature
            || abs(effectiveSize - lastEffectiveIconSize) > 0.25

        if needsStructuralRebuild {
            currentItems = items
            lastStructuralSignature = signature
            lastEffectiveIconSize = effectiveSize
            rebuildSubviews(items: items, iconSize: effectiveSize)
        } else if items != currentItems {
            currentItems = items
            updateTileStatesInPlace(items: items)
        }

        positionWindowFrame(on: screen)

        if isRevealed {
            slidingContainer.frame.origin = NSPoint(x: sideShadowPad, y: DockSettings.shared.bottomMargin)
            slidingContainer.alphaValue = 1.0
        }
    }

    private func updateTileStatesInPlace(items: [DockItem]) {
        let nonSeparatorItems = items.filter { $0.kind != .separator }
        let tiles = itemsContainer.subviews.compactMap { $0 as? DockTileView }
        guard tiles.count == nonSeparatorItems.count else {
            rebuildSubviews(items: items, iconSize: lastEffectiveIconSize)
            return
        }
        for (tile, item) in zip(tiles, nonSeparatorItems) {
            tile.update(item: item)
        }
    }

    // MARK: - Animated Reveal & Conceal

    func reveal(animated: Bool, on screen: NSScreen) {
        animationToken &+= 1
        isRevealed = true
        ignoresMouseEvents = false

        positionWindowFrame(on: screen)

        let targetY = DockSettings.shared.bottomMargin
        let hiddenY = -(currentBarSize.height + 10)

        // If concealed half-way, animate smoothly from current slidingContainer origin; if fully ordered out, start from hiddenY.
        if !isVisible {
            slidingContainer.frame.origin = NSPoint(x: sideShadowPad, y: animated ? hiddenY : targetY)
            slidingContainer.alphaValue = animated ? 0.0 : 1.0
            orderFrontRegardless()
        }

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.19
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.20, 0.92, 0.25, 1.0)
                slidingContainer.animator().frame.origin = NSPoint(x: sideShadowPad, y: targetY)
                slidingContainer.animator().alphaValue = 1.0
            }
        } else {
            slidingContainer.frame.origin = NSPoint(x: sideShadowPad, y: targetY)
            slidingContainer.alphaValue = 1.0
        }
    }

    func conceal(animated: Bool, onConcealed: (() -> Void)? = nil) {
        guard isRevealed || isVisible else {
            onConcealed?()
            return
        }
        animationToken &+= 1
        let token = animationToken
        isRevealed = false
        ignoresMouseEvents = true

        for case let tile as DockTileView in itemsContainer.subviews {
            tile.resetHoverVisuals()
        }
        HoverBubbleController.shared.hide()

        let hiddenY = -(currentBarSize.height + 10)

        if !animated || !isVisible {
            slidingContainer.frame.origin = NSPoint(x: sideShadowPad, y: hiddenY)
            slidingContainer.alphaValue = 0.0
            orderOut(nil)
            onConcealed?()
            return
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.17
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            slidingContainer.animator().frame.origin = NSPoint(x: sideShadowPad, y: hiddenY)
            slidingContainer.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            if self.animationToken == token && !self.isRevealed {
                self.orderOut(nil)
                onConcealed?()
            }
        })
    }

    // MARK: - Trigger & Keep-Alive Zones on Screen

    func triggerZone(on screen: NSScreen, hasScreenBelow: Bool) -> NSRect {
        DockLayoutMath.triggerZone(
            screenFrame: screen.frame,
            barSize: currentBarSize,
            hasScreenBelow: hasScreenBelow
        )
    }

    func keepAliveZone(on screen: NSScreen) -> NSRect {
        DockLayoutMath.keepAliveZone(
            screenFrame: screen.frame,
            barSize: currentBarSize,
            bottomMargin: DockSettings.shared.bottomMargin
        )
    }

    // MARK: - Layout Calculations

    private func computeEffectiveIconSize(items: [DockItem], preferred: CGFloat, maxWidth: CGFloat) -> CGFloat {
        DockLayoutMath.computeEffectiveIconSize(items: items, preferred: preferred, maxWidth: maxWidth)
    }

    private func barSize(for items: [DockItem], iconSize: CGFloat) -> NSSize {
        DockLayoutMath.barSize(for: items, iconSize: iconSize)
    }

    private func rebuildSubviews(items: [DockItem], iconSize: CGFloat) {
        itemsContainer.subviews.forEach { $0.removeFromSuperview() }

        let barSz = barSize(for: items, iconSize: iconSize)
        currentBarSize = barSz
        let pg = DockLayoutMath.tilePadAndGap(for: iconSize)

        slidingContainer.frame.size = NSSize(width: barSz.width, height: barSz.height + topHeadroom)
        shadowCarrier.frame = NSRect(x: 0, y: 0, width: barSz.width, height: barSz.height)
        shadowCarrier.layer?.shadowPath = CGPath(roundedRect: shadowCarrier.bounds, cornerWidth: 17, cornerHeight: 17, transform: nil)
        backgroundView.frame = NSRect(x: 0, y: 0, width: barSz.width, height: barSz.height)
        itemsContainer.frame = NSRect(x: 0, y: 0, width: barSz.width, height: barSz.height + topHeadroom)

        var cursorX: CGFloat = 9
        var lastWasTile = false
        for item in items {
            if item.kind == .separator {
                if lastWasTile {
                    cursorX -= pg.gap
                }
                let sepView = NSView(frame: NSRect(
                    x: cursorX + 5.0,
                    y: 10,
                    width: 1,
                    height: max(18, iconSize - 4)
                ))
                sepView.wantsLayer = true
                sepView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.24).cgColor
                itemsContainer.addSubview(sepView)
                cursorX += 11
                lastWasTile = false
            } else {
                let tile = DockTileView(item: item, iconSize: iconSize, tilePadX: pg.pad)
                tile.frame.origin = NSPoint(x: cursorX, y: 1)
                itemsContainer.addSubview(tile)
                cursorX += tile.frame.width + pg.gap
                lastWasTile = true
            }
        }
    }

    private func positionWindowFrame(on screen: NSScreen) {
        let winWidth = currentBarSize.width + sideShadowPad * 2
        let winHeight = DockSettings.shared.bottomMargin + currentBarSize.height + topHeadroom

        let originX = round(screen.frame.midX - winWidth / 2.0)
        let originY = round(screen.frame.minY)

        let targetFrame = NSRect(x: originX, y: originY, width: winWidth, height: winHeight)
        if frame != targetFrame {
            setFrame(targetFrame, display: true)
        }
    }
}
