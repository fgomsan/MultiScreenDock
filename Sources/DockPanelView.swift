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
    private var lastShownText: String = ""
    private var cachedSize: NSSize = .zero

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

        let textChanged = (text != lastShownText) || cachedSize == .zero
        if textChanged {
            lastShownText = text
            labelField.stringValue = text
            labelField.sizeToFit()

            let padX: CGFloat = 11
            let padY: CGFloat = 4.5
            let width = min(max(ceil(labelField.frame.width) + padX * 2, 46), 300)
            let height = ceil(labelField.frame.height + padY * 2)
            cachedSize = NSSize(width: width, height: height)

            labelField.frame = NSRect(
                x: padX,
                y: padY,
                width: width - padX * 2,
                height: labelField.frame.height
            )
        }

        let width = cachedSize.width
        let height = cachedSize.height
        var originX = round(screenRect.midX - width / 2)
        if let screenFrame = screen?.frame {
            originX = max(screenFrame.minX + 8, min(originX, screenFrame.maxX - width - 8))
        }
        let originY = round(screenRect.maxY + 8)
        let targetFrame = NSRect(x: originX, y: originY, width: width, height: height)

        if panel.frame != targetFrame || textChanged {
            panel.setFrame(targetFrame, display: textChanged)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        if panel.isVisible {
            panel.orderOut(nil)
        }
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
        isHovered = true
        (window as? DockBarPanel)?.handlePointerInWindow(event.locationInWindow)
    }

    override func mouseMoved(with event: NSEvent) {
        (window as? DockBarPanel)?.handlePointerInWindow(event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        if let barPanel = window as? DockBarPanel {
            let winPt = barPanel.convertPoint(fromScreen: NSEvent.mouseLocation)
            barPanel.handlePointerInWindow(winPt)
        }
    }

    func resetHoverVisuals() {
        isHovered = false
        applyWaveState(
            slotOriginX: frame.origin.x,
            slotWidth: iconSize + tilePadX * 2,
            magIconSize: iconSize,
            liftY: 0
        )
    }

    var liveIconFrameInSuperview: NSRect {
        NSRect(
            x: frame.origin.x + imageView.frame.origin.x,
            y: frame.origin.y + imageView.frame.origin.y,
            width: imageView.frame.width,
            height: imageView.frame.height
        )
    }

    /// Updates tile & icon geometry directly on the GPU compositor with implicit CoreAnimation disabled (0 ms latency).
    func applyWaveState(
        slotOriginX: CGFloat,
        slotWidth: CGFloat,
        magIconSize: CGFloat,
        liftY: CGFloat
    ) {
        let targetFrame = NSRect(
            x: slotOriginX,
            y: 1,
            width: slotWidth,
            height: magIconSize + liftY + 14
        )
        let targetIconFrame = NSRect(
            x: (slotWidth - magIconSize) / 2.0,
            y: 9 + liftY,
            width: magIconSize,
            height: magIconSize
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if frame != targetFrame {
            frame = targetFrame
        }
        if imageView.frame != targetIconFrame {
            imageView.frame = targetIconFrame
        }
        dotLayer.position = CGPoint(x: slotWidth / 2.0, y: 3.5)
        CATransaction.commit()
    }

    private func animateClickBounce() {
        guard let layer = imageView.layer else { return }
        let bounce = CABasicAnimation(keyPath: "transform.translation.y")
        bounce.fromValue = 0.0
        bounce.toValue = 7.0
        bounce.duration = 0.075
        bounce.autoreverses = true
        bounce.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(bounce, forKey: "clickBounce")
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
            return
        }
        if FolderStackController.shared.isVisible {
            let barPanel = window as? DockBarPanel
            let isSameFolderTile: Bool
            if case .directoryOrFile(let url, let isDir, _) = item.kind, isDir {
                isSameFolderTile = FolderStackController.shared.isPresented(for: url, on: barPanel)
            } else {
                isSameFolderTile = false
            }
            if !isSameFolderTile {
                FolderStackController.shared.dismiss(animated: false)
            }
        }
        animateClickBounce()
        HoverBubbleController.shared.hide()
        activateItem(withModifiers: event.modifierFlags)
    }

    override func rightMouseDown(with event: NSEvent) {
        HoverBubbleController.shared.hide()
        FolderStackController.shared.dismiss(animated: false)
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

        case .directoryOrFile(let url, let isDir, let stackCfg):
            if cleanMods.contains(.command) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else if isDir && !cleanMods.contains(.option) {
                presentFolderStack(url: url, stackConfig: stackCfg)
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

        case .directoryOrFile(let url, let isDir, _):
            if isDir {
                let stackItem = NSMenuItem(title: L10n.openFolderStack, action: #selector(ctxOpenFolderStack), keyEquivalent: "")
                stackItem.target = self
                menu.addItem(stackItem)

                let openFinderItem = NSMenuItem(title: L10n.openInFinder, action: #selector(ctxOpenDirectoryInFinder(_:)), keyEquivalent: "")
                openFinderItem.representedObject = url
                openFinderItem.target = self
                menu.addItem(openFinderItem)

                let reveal = NSMenuItem(title: L10n.showContainerInFinder, action: #selector(ctxRevealInFinder), keyEquivalent: "")
                reveal.representedObject = url
                reveal.target = self
                menu.addItem(reveal)

                menu.addItem(.separator())
                let styleSubmenu = NSMenu()
                let styleChoices: [(String, FolderStackStylePreference)] = [
                    (L10n.stackStyleDockDefault, .dockDefault),
                    (L10n.stackStyleFan, .fan),
                    (L10n.stackStyleGrid, .grid),
                    (L10n.stackStyleList, .list)
                ]
                for (title, pref) in styleChoices {
                    let sItem = NSMenuItem(title: title, action: #selector(ctxSelectFolderStackStyle(_:)), keyEquivalent: "")
                    sItem.target = self
                    sItem.representedObject = pref.rawValue
                    sItem.state = (DockSettings.shared.folderStackStyle == pref) ? .on : .off
                    styleSubmenu.addItem(sItem)
                }
                let styleParent = NSMenuItem(title: L10n.stackStyleMenu, action: nil, keyEquivalent: "")
                styleParent.submenu = styleSubmenu
                menu.addItem(styleParent)
            } else {
                let openItem = NSMenuItem(title: L10n.openGeneric, action: #selector(ctxOpenPrimary), keyEquivalent: "")
                openItem.target = self
                menu.addItem(openItem)

                let reveal = NSMenuItem(title: L10n.showContainerInFinder, action: #selector(ctxRevealInFinder), keyEquivalent: "")
                reveal.representedObject = url
                reveal.target = self
                menu.addItem(reveal)
            }

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

    private func presentFolderStack(url: URL, stackConfig: DockFolderStackConfig?) {
        guard let barPanel = window as? DockBarPanel else {
            FolderStackController.shared.openInFinder(url)
            return
        }
        let rectInWin = convert(bounds, to: nil)
        let anchorScreenRect = barPanel.convertToScreen(rectInWin)
        FolderStackController.shared.toggleOrPresent(
            folderURL: url,
            title: item.label,
            dockConfig: stackConfig,
            anchorScreenRect: anchorScreenRect,
            on: barPanel.assignedScreen ?? barPanel.screen,
            barPanel: barPanel
        )
    }

    @objc private func ctxOpenPrimary() {
        activateItem(withModifiers: [])
    }

    @objc private func ctxOpenFolderStack() {
        if case .directoryOrFile(let url, let isDir, let stackCfg) = item.kind, isDir {
            presentFolderStack(url: url, stackConfig: stackCfg)
        }
    }

    @objc private func ctxOpenDirectoryInFinder(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL {
            FolderStackController.shared.openInFinder(url)
        }
    }

    @objc private func ctxSelectFolderStackStyle(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String,
           let pref = FolderStackStylePreference(rawValue: raw) {
            DockSettings.shared.folderStackStyle = pref
        }
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
            (window as? DockBarPanel)?.handlePointerInWindow(sender.draggingLocation)
            return .generic
        case .directoryOrFile(_, let isDir, _) where isDir:
            if mask.contains(.move) {
                (window as? DockBarPanel)?.handlePointerInWindow(sender.draggingLocation)
                return .move
            } else if mask.contains(.copy) {
                (window as? DockBarPanel)?.handlePointerInWindow(sender.draggingLocation)
                return .copy
            }
            return []
        default:
            return []
        }
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        (window as? DockBarPanel)?.handlePointerInWindow(sender.draggingLocation)
        return draggingEntered(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if let barPanel = window as? DockBarPanel {
            let winPt = barPanel.convertPoint(fromScreen: NSEvent.mouseLocation)
            barPanel.handlePointerInWindow(winPt)
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        (window as? DockBarPanel)?.handlePointerExitedBar()
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

        case .directoryOrFile(let folderURL, let isDir, _) where isDir:
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
        let barKeepWidth = min(screenFrame.width, max(maxTrigger.width + 16, barSize.width + 104))
        let barKeepHeight = max(maxTrigger.height + 12, bottomMargin + barSize.height + 38)
        let barKeep = NSRect(
            x: round(screenFrame.midX - barKeepWidth / 2),
            y: screenFrame.minY,
            width: barKeepWidth,
            height: barKeepHeight
        )
        return barKeep.union(maxTrigger)
    }

    /// Resting footprint of the Dock pill on `screenFrame` used by Smart Auto-Hide (`smartAutoHide`)
    /// to detect whether any standard user window overlaps the Dock area on that display.
    static func dockDodgeZone(screenFrame: NSRect, barSize: NSSize, bottomMargin: CGFloat) -> NSRect {
        let width = min(screenFrame.width - 8, max(60, barSize.width + 8))
        let height = max(24, bottomMargin + barSize.height + 4)
        return NSRect(
            x: round(screenFrame.midX - width / 2),
            y: screenFrame.minY,
            width: width,
            height: height
        )
    }

    /// Converts a CoreGraphics/Quartz global window rect (`kCGWindowBounds`, top-left origin on primary display)
    /// into AppKit global screen coordinates (`NSScreen.frame`, bottom-left origin on primary display).
    static func quartzRectToAppKit(_ quartzRect: CGRect, primaryScreenHeight: CGFloat) -> NSRect {
        NSRect(
            x: quartzRect.origin.x,
            y: primaryScreenHeight - (quartzRect.origin.y + quartzRect.size.height),
            width: quartzRect.size.width,
            height: quartzRect.size.height
        )
    }

    /// Returns true when any standard application window rect (in AppKit screen coordinates) intersects
    /// `dockZone` by at least 4×4 pt.
    static func doesAnyWindowOverlapDock(dockZone: NSRect, windowRectsInAppKit: [NSRect]) -> Bool {
        for winRect in windowRectsInAppKit {
            guard winRect.width >= 80, winRect.height >= 60 else { continue }
            let inter = dockZone.intersection(winRect)
            if !inter.isNull && inter.width >= 4.0 && inter.height >= 4.0 {
                return true
            }
        }
        return false
    }

    struct WaveSlotInput: Equatable {
        let isSeparator: Bool
    }

    struct WaveSlotFrame: Equatable {
        let tileOriginX: CGFloat
        let slotWidth: CGFloat
        let iconSize: CGFloat
        let liftY: CGFloat
        let weight: CGFloat
    }

    struct WaveLayoutResult: Equatable {
        let barOriginXInContainer: CGFloat
        let barWidth: CGFloat
        let slots: [WaveSlotFrame]
        let hoveredSlotIndex: Int?
    }

    /// Computes a continuous, real-time raised-cosine magnification wave matching Apple's macOS Dock.
    /// Uses piecewise-linear focal-point locking so the icon directly underneath `cursorXInContainer`
    /// never drifts sideways away from the pointer, even at the far left or right ends of the Dock.
    static func computeWaveLayout(
        slots: [WaveSlotInput],
        baseIconSize: CGFloat,
        containerWidth: CGFloat,
        cursorXInContainer: CGFloat?,
        envelope: CGFloat
    ) -> WaveLayoutResult {
        let padX: CGFloat = 9
        let pg = tilePadAndGap(for: baseIconSize)
        let baseTileW = baseIconSize + pg.pad * 2

        var restOrigins: [CGFloat] = []
        var restWidths: [CGFloat] = []
        restOrigins.reserveCapacity(slots.count)
        restWidths.reserveCapacity(slots.count)

        var rCursor: CGFloat = padX
        var rLastWasTile = false
        for s in slots {
            if s.isSeparator {
                if rLastWasTile { rCursor -= pg.gap }
                restOrigins.append(rCursor)
                restWidths.append(11)
                rCursor += 11
                rLastWasTile = false
            } else {
                restOrigins.append(rCursor)
                restWidths.append(baseTileW)
                rCursor += baseTileW + pg.gap
                rLastWasTile = true
            }
        }
        if rLastWasTile { rCursor -= pg.gap }
        let restBarWidth = max(60, rCursor + padX)
        let restBarOriginX = round((containerWidth - restBarWidth) / 2.0)

        let clampedEnv = min(max(envelope, 0.0), 1.0)
        guard let cursorX = cursorXInContainer else {
            let restSlots: [WaveSlotFrame] = slots.enumerated().map { idx, s in
                WaveSlotFrame(
                    tileOriginX: restOrigins[idx],
                    slotWidth: restWidths[idx],
                    iconSize: s.isSeparator ? 0 : baseIconSize,
                    liftY: 0,
                    weight: 0
                )
            }
            return WaveLayoutResult(
                barOriginXInContainer: restBarOriginX,
                barWidth: restBarWidth,
                slots: restSlots,
                hoveredSlotIndex: nil
            )
        }

        let relCursorX = cursorX - restBarOriginX
        let pitch = baseTileW + pg.gap
        let influenceRadius = max(72.0, pitch * 2.45)
        let maxExtraScale: CGFloat = 0.42

        var expOrigins: [CGFloat] = []
        var expFrames: [WaveSlotFrame] = []
        expOrigins.reserveCapacity(slots.count)
        expFrames.reserveCapacity(slots.count)

        var eCursor: CGFloat = padX
        var eLastWasTile = false

        for (idx, s) in slots.enumerated() {
            if s.isSeparator {
                if eLastWasTile { eCursor -= pg.gap }
                let frame = WaveSlotFrame(
                    tileOriginX: eCursor,
                    slotWidth: 11,
                    iconSize: 0,
                    liftY: 0,
                    weight: 0
                )
                expOrigins.append(eCursor)
                expFrames.append(frame)
                eCursor += 11
                eLastWasTile = false
            } else {
                let restCenter = restOrigins[idx] + restWidths[idx] * 0.5
                let dist = abs(relCursorX - restCenter) / influenceRadius
                let rawW: CGFloat = dist < 1.0 ? 0.5 * (1.0 + cos(.pi * dist)) : 0.0
                let w = rawW * clampedEnv
                let magIcon = min(76.0, baseIconSize * (1.0 + maxExtraScale * w))
                let slotW = magIcon + pg.pad * 2
                let lift = 3.5 * w
                let frame = WaveSlotFrame(
                    tileOriginX: eCursor,
                    slotWidth: slotW,
                    iconSize: magIcon,
                    liftY: lift,
                    weight: w
                )
                expOrigins.append(eCursor)
                expFrames.append(frame)
                eCursor += slotW + pg.gap
                eLastWasTile = true
            }
        }
        if eLastWasTile { eCursor -= pg.gap }
        let expandedBarWidth = max(60, eCursor + padX)

        // Piecewise-linear focal lock between rest landmarks and expanded landmarks
        let barOriginX: CGFloat
        if clampedEnv <= 0.0005 || slots.isEmpty {
            barOriginX = restBarOriginX
        } else {
            var restKnots: [CGFloat] = [0]
            var expKnots: [CGFloat] = [0]
            for idx in 0..<slots.count {
                restKnots.append(restOrigins[idx])
                expKnots.append(expOrigins[idx])
                restKnots.append(restOrigins[idx] + restWidths[idx])
                expKnots.append(expOrigins[idx] + expFrames[idx].slotWidth)
            }
            restKnots.append(restBarWidth)
            expKnots.append(expandedBarWidth)

            let c = min(max(relCursorX, 0), restBarWidth)
            var mappedExpX = c
            for k in 0..<(restKnots.count - 1) {
                let r0 = restKnots[k]
                let r1 = restKnots[k + 1]
                if c >= r0 && c <= r1 {
                    let span = r1 - r0
                    if span > 0.0001 {
                        let frac = (c - r0) / span
                        mappedExpX = expKnots[k] + frac * (expKnots[k + 1] - expKnots[k])
                    } else {
                        mappedExpX = expKnots[k]
                    }
                    break
                }
            }

            let rawBarOriginX = restBarOriginX + (c - mappedExpX)
            if expandedBarWidth <= containerWidth - 4 {
                barOriginX = min(max(rawBarOriginX, 2.0), containerWidth - expandedBarWidth - 2.0)
            } else {
                barOriginX = (containerWidth - expandedBarWidth) * 0.5
            }
        }

        // Determine hovered non-separator slot using rendered visual spans (eliminates 2 pt inter-tile flicker)
        var hoveredIdx: Int?
        let halfGap = max(1.5, pg.gap * 0.65)
        for (idx, s) in slots.enumerated() where !s.isSeparator {
            let f = expFrames[idx]
            let left = barOriginX + f.tileOriginX - halfGap
            let right = barOriginX + f.tileOriginX + f.slotWidth + halfGap
            if cursorX >= left && cursorX <= right {
                hoveredIdx = idx
                break
            }
        }

        return WaveLayoutResult(
            barOriginXInContainer: barOriginX,
            barWidth: expandedBarWidth,
            slots: expFrames,
            hoveredSlotIndex: hoveredIdx
        )
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
            case .directoryOrFile(let url, let isDir, _):
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
    private var barTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = barTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        barTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        (window as? DockBarPanel)?.handlePointerInWindow(event.locationInWindow)
    }

    override func mouseMoved(with event: NSEvent) {
        (window as? DockBarPanel)?.handlePointerInWindow(event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        if let barPanel = window as? DockBarPanel {
            let winPt = barPanel.convertPoint(fromScreen: NSEvent.mouseLocation)
            barPanel.handlePointerInWindow(winPt)
        }
    }

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
    private enum RenderedBarElement {
        case tile(DockTileView)
        case separator(NSView)
    }

    var isContextMenuOpen = false
    var isFolderStackOpen = false
    var hasActivePopup: Bool { isContextMenuOpen || isFolderStackOpen }
    private(set) weak var assignedScreen: NSScreen?
    private(set) var isRevealed = false
    private var animationToken: Int = 0

    private let maxWaveSideHeadroom: CGFloat = 58
    private let topHeadroom: CGFloat = 40

    private let slidingContainer = NSView()
    private let shadowCarrier = NSView()
    private let backgroundView = NSVisualEffectView()
    private let itemsContainer = NSView()

    private var currentItems: [DockItem] = []
    private var renderedElements: [RenderedBarElement] = []
    private var cachedWaveSlotInputs: [DockLayoutMath.WaveSlotInput] = []
    private var lastStructuralSignature: [String] = []
    private var lastEffectiveIconSize: CGFloat = 0
    private(set) var currentBarSize: NSSize = NSSize(width: 400, height: 52)

    private var waveEnvelope: CGFloat = 0.0
    private var targetWaveEnvelope: CGFloat = 0.0
    private var lastCursorXInContainer: CGFloat?
    private var envelopeTimer: Timer?
    private var lastEnvelopeTickTime: CFTimeInterval = 0
    private var activeHoverGlobalMonitor: Any?
    private var activeHoverLocalMonitor: Any?

    init(screen: NSScreen) {
        self.assignedScreen = screen
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
        assignedScreen = screen
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
        renderCurrentWaveFrame()

        if isRevealed {
            slidingContainer.frame.origin = NSPoint(x: 0, y: DockSettings.shared.bottomMargin)
            slidingContainer.alphaValue = 1.0
        }
    }

    private func updateTileStatesInPlace(items: [DockItem]) {
        let nonSeparatorItems = items.filter { $0.kind != .separator }
        let tiles = renderedElements.compactMap { elem -> DockTileView? in
            if case .tile(let t) = elem { return t }
            return nil
        }
        guard tiles.count == nonSeparatorItems.count else {
            rebuildSubviews(items: items, iconSize: lastEffectiveIconSize)
            return
        }
        for (tile, item) in zip(tiles, nonSeparatorItems) {
            tile.update(item: item)
        }
    }

    // MARK: - 120 Hz Real-Time Cosine Magnification Wave

    func handlePointerInWindow(_ winPoint: NSPoint) {
        guard isRevealed, !hasActivePopup else { return }
        let ptInSliding = slidingContainer.convert(winPoint, from: nil)

        let barMinX = backgroundView.frame.minX - 10
        let barMaxX = backgroundView.frame.maxX + 10
        let insideWaveZone = ptInSliding.x >= barMinX
            && ptInSliding.x <= barMaxX
            && ptInSliding.y >= -6
            && ptInSliding.y <= (currentBarSize.height + topHeadroom - 2)

        guard insideWaveZone else {
            handlePointerExitedBar()
            return
        }

        lastCursorXInContainer = ptInSliding.x
        targetWaveEnvelope = DockSettings.shared.hoverMagnification ? 1.0 : 0.0
        installActiveHoverMonitorsIfNeeded()
        renderCurrentWaveFrame()
        ensureEnvelopeTimerIfNeeded()
    }

    func handlePointerExitedBar() {
        removeActiveHoverMonitors()
        targetWaveEnvelope = 0.0
        HoverBubbleController.shared.hide()
        if waveEnvelope <= 0.001 {
            waveEnvelope = 0.0
            lastCursorXInContainer = nil
            stopEnvelopeTimer()
            renderCurrentWaveFrame()
        } else {
            ensureEnvelopeTimerIfNeeded()
        }
    }

    private func installActiveHoverMonitorsIfNeeded() {
        guard activeHoverGlobalMonitor == nil, activeHoverLocalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        activeHoverGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            guard let self = self else { return }
            let winPt = self.convertPoint(fromScreen: NSEvent.mouseLocation)
            self.handlePointerInWindow(winPt)
        }
        activeHoverLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            if let self = self {
                let winPt = self.convertPoint(fromScreen: NSEvent.mouseLocation)
                self.handlePointerInWindow(winPt)
            }
            return event
        }
    }

    private func removeActiveHoverMonitors() {
        if let g = activeHoverGlobalMonitor {
            NSEvent.removeMonitor(g)
            activeHoverGlobalMonitor = nil
        }
        if let l = activeHoverLocalMonitor {
            NSEvent.removeMonitor(l)
            activeHoverLocalMonitor = nil
        }
    }

    private func ensureEnvelopeTimerIfNeeded() {
        guard abs(waveEnvelope - targetWaveEnvelope) > 0.002 else {
            waveEnvelope = targetWaveEnvelope
            if targetWaveEnvelope == 0 {
                lastCursorXInContainer = nil
            }
            stopEnvelopeTimer()
            return
        }
        guard envelopeTimer == nil else { return }
        lastEnvelopeTickTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.tickWaveEnvelope()
        }
        RunLoop.main.add(timer, forMode: .common)
        envelopeTimer = timer
    }

    private func stopEnvelopeTimer() {
        envelopeTimer?.invalidate()
        envelopeTimer = nil
    }

    private func tickWaveEnvelope() {
        let now = CACurrentMediaTime()
        let dt = min(0.05, max(0.001, now - lastEnvelopeTickTime))
        lastEnvelopeTickTime = now

        // Verify pointer hasn't left the bar during fast cross-display flicks
        if targetWaveEnvelope > 0 {
            let liveWinPt = convertPoint(fromScreen: NSEvent.mouseLocation)
            let ptInSliding = slidingContainer.convert(liveWinPt, from: nil)
            let inside = ptInSliding.x >= backgroundView.frame.minX - 10
                && ptInSliding.x <= backgroundView.frame.maxX + 10
                && ptInSliding.y >= -6
                && ptInSliding.y <= (currentBarSize.height + topHeadroom - 2)
            if inside {
                lastCursorXInContainer = ptInSliding.x
            } else {
                targetWaveEnvelope = 0.0
                removeActiveHoverMonitors()
                HoverBubbleController.shared.hide()
            }
        }

        if waveEnvelope < targetWaveEnvelope {
            // Crisp 55 ms bloom on entry with exponential ease-out feel
            let step = CGFloat(dt / 0.055)
            waveEnvelope = min(targetWaveEnvelope, waveEnvelope + max(step, (targetWaveEnvelope - waveEnvelope) * 0.38))
        } else if waveEnvelope > targetWaveEnvelope {
            // Smooth 90 ms settle when leaving the bar
            let step = CGFloat(dt / 0.090)
            waveEnvelope = max(targetWaveEnvelope, waveEnvelope - max(step * 0.65, (waveEnvelope - targetWaveEnvelope) * 0.28))
        }

        if abs(waveEnvelope - targetWaveEnvelope) <= 0.003 {
            waveEnvelope = targetWaveEnvelope
            if targetWaveEnvelope == 0 {
                lastCursorXInContainer = nil
            }
            stopEnvelopeTimer()
        }

        renderCurrentWaveFrame()
    }

    private func renderCurrentWaveFrame() {
        guard !renderedElements.isEmpty, lastEffectiveIconSize > 0 else { return }
        let containerW = max(slidingContainer.frame.width, currentBarSize.width)
        let effectiveCursorX = (targetWaveEnvelope > 0 || waveEnvelope > 0.001 || activeHoverGlobalMonitor != nil)
            ? lastCursorXInContainer
            : nil

        let layout = DockLayoutMath.computeWaveLayout(
            slots: cachedWaveSlotInputs,
            baseIconSize: lastEffectiveIconSize,
            containerWidth: containerW,
            cursorXInContainer: effectiveCursorX,
            envelope: DockSettings.shared.hoverMagnification ? waveEnvelope : 0.0
        )

        let bgFrame = NSRect(
            x: layout.barOriginXInContainer,
            y: 0,
            width: layout.barWidth,
            height: currentBarSize.height
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if backgroundView.frame != bgFrame {
            backgroundView.frame = bgFrame
            shadowCarrier.frame = bgFrame
            shadowCarrier.layer?.shadowPath = CGPath(
                roundedRect: shadowCarrier.bounds,
                cornerWidth: 17,
                cornerHeight: 17,
                transform: nil
            )
        }

        for (idx, elem) in renderedElements.enumerated() where idx < layout.slots.count {
            let slot = layout.slots[idx]
            let x = layout.barOriginXInContainer + slot.tileOriginX
            switch elem {
            case .separator(let sepView):
                sepView.frame.origin.x = x + 5.0
            case .tile(let tileView):
                tileView.applyWaveState(
                    slotOriginX: x,
                    slotWidth: slot.slotWidth,
                    magIconSize: slot.iconSize,
                    liftY: slot.liftY
                )
            }
        }
        CATransaction.commit()

        if !hasActivePopup,
           !FolderStackController.shared.isVisible,
           activeHoverGlobalMonitor != nil,
           let hIdx = layout.hoveredSlotIndex,
           hIdx < renderedElements.count,
           case .tile(let hoveredTile) = renderedElements[hIdx] {
            let rectInWin = slidingContainer.convert(hoveredTile.liveIconFrameInSuperview, to: nil)
            let screenRect = convertToScreen(rectInWin)
            HoverBubbleController.shared.show(text: hoveredTile.item.label, above: screenRect, on: screen)
        } else if activeHoverGlobalMonitor == nil {
            HoverBubbleController.shared.hide()
        }
    }

    // MARK: - Animated Reveal & Conceal

    func reveal(animated: Bool, on screen: NSScreen) {
        animationToken &+= 1
        isRevealed = true
        ignoresMouseEvents = false

        positionWindowFrame(on: screen)
        renderCurrentWaveFrame()

        let targetY = DockSettings.shared.bottomMargin
        let hiddenY = -(currentBarSize.height + 10)

        // If concealed half-way, animate smoothly from current slidingContainer origin; if fully ordered out, start from hiddenY.
        if !isVisible {
            slidingContainer.frame.origin = NSPoint(x: 0, y: animated ? hiddenY : targetY)
            slidingContainer.alphaValue = animated ? 0.0 : 1.0
            orderFrontRegardless()
        }

        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.30, 1.0)
                slidingContainer.animator().frame.origin = NSPoint(x: 0, y: targetY)
                slidingContainer.animator().alphaValue = 1.0
            }, completionHandler: { [weak self] in
                guard let self = self, self.isRevealed else { return }
                let winPt = self.convertPoint(fromScreen: NSEvent.mouseLocation)
                self.handlePointerInWindow(winPt)
            })
        } else {
            slidingContainer.frame.origin = NSPoint(x: 0, y: targetY)
            slidingContainer.alphaValue = 1.0
        }
    }

    func conceal(animated: Bool, onConcealed: (() -> Void)? = nil) {
        if isFolderStackOpen && !FolderStackController.shared.isDraggingFile {
            FolderStackController.shared.dismiss(animated: false)
        }
        guard isRevealed || isVisible else {
            onConcealed?()
            return
        }
        animationToken &+= 1
        let token = animationToken
        isRevealed = false
        ignoresMouseEvents = true

        removeActiveHoverMonitors()
        stopEnvelopeTimer()
        waveEnvelope = 0.0
        targetWaveEnvelope = 0.0
        lastCursorXInContainer = nil
        renderCurrentWaveFrame()
        HoverBubbleController.shared.hide()

        let hiddenY = -(currentBarSize.height + 10)

        if !animated || !isVisible {
            slidingContainer.frame.origin = NSPoint(x: 0, y: hiddenY)
            slidingContainer.alphaValue = 0.0
            orderOut(nil)
            onConcealed?()
            return
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            slidingContainer.animator().frame.origin = NSPoint(x: 0, y: hiddenY)
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

    func dodgeZone(on screen: NSScreen) -> NSRect {
        DockLayoutMath.dockDodgeZone(
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
        renderedElements.removeAll(keepingCapacity: true)
        cachedWaveSlotInputs.removeAll(keepingCapacity: true)

        let barSz = barSize(for: items, iconSize: iconSize)
        currentBarSize = barSz
        let pg = DockLayoutMath.tilePadAndGap(for: iconSize)

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
                renderedElements.append(.separator(sepView))
                cachedWaveSlotInputs.append(.init(isSeparator: true))
                cursorX += 11
                lastWasTile = false
            } else {
                let tile = DockTileView(item: item, iconSize: iconSize, tilePadX: pg.pad)
                tile.frame.origin = NSPoint(x: cursorX, y: 1)
                itemsContainer.addSubview(tile)
                renderedElements.append(.tile(tile))
                cachedWaveSlotInputs.append(.init(isSeparator: false))
                cursorX += tile.frame.width + pg.gap
                lastWasTile = true
            }
        }
    }

    private func positionWindowFrame(on screen: NSScreen) {
        let winWidth = min(screen.frame.width, currentBarSize.width + maxWaveSideHeadroom * 2)
        let winHeight = DockSettings.shared.bottomMargin + currentBarSize.height + topHeadroom

        slidingContainer.frame.size = NSSize(width: winWidth, height: currentBarSize.height + topHeadroom)
        itemsContainer.frame = NSRect(x: 0, y: 0, width: winWidth, height: currentBarSize.height + topHeadroom)

        let originX = round(screen.frame.midX - winWidth / 2.0)
        let originY = round(screen.frame.minY)

        let targetFrame = NSRect(x: originX, y: originY, width: winWidth, height: winHeight)
        if frame != targetFrame {
            setFrame(targetFrame, display: true)
        }
    }
}
