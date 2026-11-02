import Cocoa
import QuartzCore

// MARK: - Subtle Bottom Edge Hint Pill (for Auto-Hide Mode)

final class EdgeHintPanel: NSPanel {
    private static let winWidth: CGFloat = 156
    private static let winHeight: CGFloat = 16

    init(screen: NSScreen) {
        let rect = NSRect(
            x: round(screen.frame.midX - Self.winWidth / 2),
            y: round(screen.frame.minY + 3),
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

        // Cápsula exterior oscura con sombra para contraste sobre fondos blancos/claros
        let outerFrame = NSRect(x: 8, y: 4, width: Self.winWidth - 16, height: 7)
        let outerTrack = NSView(frame: outerFrame)
        outerTrack.wantsLayer = true
        outerTrack.layer?.cornerRadius = 3.5
        outerTrack.layer?.cornerCurve = .continuous
        outerTrack.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        outerTrack.layer?.shadowColor = NSColor.black.cgColor
        outerTrack.layer?.shadowOpacity = 0.50
        outerTrack.layer?.shadowRadius = 3.0
        outerTrack.layer?.shadowOffset = CGSize(width: 0, height: -1)
        root.addSubview(outerTrack)

        // Núcleo interior luminoso estilo Home Bar para contraste sobre fondos oscuros
        let innerPill = NSView(frame: NSRect(x: 1.25, y: 1.25, width: outerFrame.width - 2.5, height: outerFrame.height - 2.5))
        innerPill.wantsLayer = true
        innerPill.layer?.cornerRadius = 2.25
        innerPill.layer?.cornerCurve = .continuous
        innerPill.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.88).cgColor
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
            y: round(screen.frame.minY + 3),
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
    let item: DockItem
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
        imageView.frame = NSRect(x: tilePadX, y: 9, width: iconSize, height: iconSize)
        addSubview(imageView)

        dotLayer.bounds = CGRect(x: 0, y: 0, width: 4.5, height: 4.5)
        dotLayer.position = CGPoint(x: width / 2, y: 3.5)
        dotLayer.cornerRadius = 2.25
        updateRunningDot()
        layer?.addSublayer(dotLayer)

        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        switch item.kind {
        case .finder:
            openFinder()

        case .application(let bundleID, let url):
            if flags.contains(.command) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                return
            }
            if let bid = bundleID,
               let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bid && !$0.isTerminated }) {
                if running.isActive && flags.contains(.option) {
                    running.hide()
                    return
                }
            }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)

        case .directoryOrFile(let url, _):
            if flags.contains(.command) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                NSWorkspace.shared.open(url)
            }

        case .trash:
            openTrash()

        case .separator:
            break
        }
    }

    private func openFinder() {
        let script = """
        tell application "Finder"
            activate
            if (count of windows) is 0 then
                make new Finder window to home
            end if
        end tell
        """
        if let ascript = NSAppleScript(source: script) {
            var err: NSDictionary?
            ascript.executeAndReturnError(&err)
            if err == nil { return }
        }
        let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: finderURL, configuration: config, completionHandler: nil)
    }

    private func openTrash() {
        if let trashURL = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first {
            NSWorkspace.shared.open(trashURL)
        }
    }

    // MARK: - Context Menu

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu(title: item.label)

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

            if let bid = bundleID,
               let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bid && !$0.isTerminated }) {
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
            app.activate()
        } else {
            app.hide()
        }
    }

    @objc private func ctxQuitApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? NSRunningApplication else { return }
        app.terminate()
    }

    @objc private func ctxEmptyTrash() {
        let script = "tell application \"Finder\" to empty trash"
        if let ascript = NSAppleScript(source: script) {
            var err: NSDictionary?
            ascript.executeAndReturnError(&err)
        }
    }

    // MARK: - Drag & Drop Support

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        switch item.kind {
        case .application, .trash:
            animateHover(hovered: true)
            return .generic
        case .directoryOrFile(_, let isDir) where isDir:
            animateHover(hovered: true)
            return .move
        default:
            return []
        }
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        animateHover(hovered: false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        animateHover(hovered: false)
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else {
            return false
        }

        switch item.kind {
        case .application(_, let appURL):
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: config, completionHandler: nil)
            return true

        case .directoryOrFile(let folderURL, let isDir) where isDir:
            for fileURL in urls {
                let dest = folderURL.appendingPathComponent(fileURL.lastPathComponent)
                try? FileManager.default.moveItem(at: fileURL, to: dest)
            }
            return true

        case .trash:
            for fileURL in urls {
                try? FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
            }
            return true

        default:
            return false
        }
    }
}

// MARK: - Clipped Root View & Per-Screen Dock Bar Panel

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
                    return sub.hitTest(container.convert(ptInTiles, to: sub)) ?? sub
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
        shadowCarrier.layer?.shadowOpacity = 0.36
        shadowCarrier.layer?.shadowRadius = 10
        shadowCarrier.layer?.shadowOffset = CGSize(width: 0, height: -3)
        slidingContainer.addSubview(shadowCarrier)

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

        let needsRebuild = forceLayout || (items != currentItems) || (abs(effectiveSize - lastEffectiveIconSize) > 0.25)
        if needsRebuild {
            currentItems = items
            lastEffectiveIconSize = effectiveSize
            rebuildSubviews(items: items, iconSize: effectiveSize)
        } else {
            currentBarSize = barSize(for: items, iconSize: effectiveSize)
        }

        positionWindowFrame(on: screen)

        if isRevealed {
            slidingContainer.frame.origin = NSPoint(x: sideShadowPad, y: DockSettings.shared.bottomMargin)
            slidingContainer.alphaValue = 1.0
        }
    }

    // MARK: - Animated Reveal & Conceal

    func reveal(animated: Bool, on screen: NSScreen) {
        animationToken &+= 1
        let wasRevealed = isRevealed
        isRevealed = true
        ignoresMouseEvents = false

        positionWindowFrame(on: screen)

        let targetY = DockSettings.shared.bottomMargin
        let hiddenY = -(currentBarSize.height + 10)

        if !isVisible {
            slidingContainer.frame.origin = NSPoint(x: sideShadowPad, y: animated ? hiddenY : targetY)
            slidingContainer.alphaValue = animated ? 0.0 : 1.0
            orderFrontRegardless()
        } else if !wasRevealed && animated {
            // Estaba a mitad de ocultarse: continuamos suavemente desde su posición actual
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

    func conceal(animated: Bool) {
        guard isRevealed || isVisible else { return }
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
            }
        })
    }

    // MARK: - Trigger & Keep-Alive Zones on Screen

    func triggerZone(on screen: NSScreen, hasScreenBelow: Bool) -> NSRect {
        let minTriggerWidth = screen.frame.width * 0.55
        let width = min(screen.frame.width - 24, max(minTriggerWidth, currentBarSize.width + 80))
        let height: CGFloat = hasScreenBelow ? 26.0 : 20.0
        return NSRect(
            x: round(screen.frame.midX - width / 2),
            y: screen.frame.minY,
            width: width,
            height: height
        )
    }

    func keepAliveZone(on screen: NSScreen) -> NSRect {
        let width = min(screen.frame.width, currentBarSize.width + 56)
        let height = DockSettings.shared.bottomMargin + currentBarSize.height + 24
        return NSRect(
            x: round(screen.frame.midX - width / 2),
            y: screen.frame.minY,
            width: width,
            height: height
        )
    }

    // MARK: - Layout Calculations

    private func tilePadAndGap(for iconSize: CGFloat) -> (pad: CGFloat, gap: CGFloat) {
        if iconSize >= 34 {
            return (2.5, 2.0)
        } else {
            return (1.5, 1.0)
        }
    }

    private func computeEffectiveIconSize(items: [DockItem], preferred: CGFloat, maxWidth: CGFloat) -> CGFloat {
        let tileCount = CGFloat(items.filter { $0.kind != .separator }.count)
        let sepCount = CGFloat(items.filter { $0.kind == .separator }.count)
        guard tileCount > 0 else { return preferred }

        let sidePadding: CGFloat = 18
        let sepTotalWidth = sepCount * 11
        let fullPG = tilePadAndGap(for: preferred)
        let fullExtraPerTile = fullPG.pad * 2 + fullPG.gap

        let naturalWidth = sidePadding + sepTotalWidth + tileCount * (preferred + fullExtraPerTile) - fullPG.gap
        if naturalWidth <= maxWidth {
            return preferred
        }

        let compactPG = tilePadAndGap(for: 26)
        let compactExtraPerTile = compactPG.pad * 2 + compactPG.gap
        let availableForIcons = maxWidth - sidePadding - sepTotalWidth + compactPG.gap - (tileCount * compactExtraPerTile)
        return max(20, floor(availableForIcons / tileCount))
    }

    private func barSize(for items: [DockItem], iconSize: CGFloat) -> NSSize {
        let padX: CGFloat = 9
        let pg = tilePadAndGap(for: iconSize)
        var cursorX: CGFloat = padX
        for item in items {
            if item.kind == .separator {
                cursorX += 11
            } else {
                cursorX += (iconSize + pg.pad * 2) + pg.gap
            }
        }
        let barWidth = max(60, cursorX - pg.gap + padX)
        let barHeight = iconSize + 16
        return NSSize(width: barWidth, height: barHeight)
    }

    private func rebuildSubviews(items: [DockItem], iconSize: CGFloat) {
        itemsContainer.subviews.forEach { $0.removeFromSuperview() }

        let barSz = barSize(for: items, iconSize: iconSize)
        currentBarSize = barSz
        let pg = tilePadAndGap(for: iconSize)

        slidingContainer.frame.size = NSSize(width: barSz.width, height: barSz.height + topHeadroom)
        shadowCarrier.frame = NSRect(x: 0, y: 0, width: barSz.width, height: barSz.height)
        backgroundView.frame = NSRect(x: 0, y: 0, width: barSz.width, height: barSz.height)
        itemsContainer.frame = NSRect(x: 0, y: 0, width: barSz.width, height: barSz.height + topHeadroom)

        var cursorX: CGFloat = 9
        for item in items {
            if item.kind == .separator {
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
            } else {
                let tile = DockTileView(item: item, iconSize: iconSize, tilePadX: pg.pad)
                tile.frame.origin = NSPoint(x: cursorX, y: 1)
                itemsContainer.addSubview(tile)
                cursorX += tile.frame.width + pg.gap
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
