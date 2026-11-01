import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let statusMenu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        MultiScreenController.shared.start()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "MultiScreenDock") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "Dock+"
            }
            button.toolTip = L10n.tooltipStatus
        }
        statusMenu.delegate = self
        statusItem.menu = statusMenu
    }

    // MARK: - Dynamic Menu Construction

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = DockSettings.shared
        let counts = MultiScreenController.shared.activePanelCount()
        let nativeAutohide = settings.isNativeDockAutohideEnabled

        let headerTitle = nativeAutohide
            ? L10n.headerAllPanels(visible: counts.visible, total: counts.total)
            : L10n.headerHybrid(visible: counts.visible, total: counts.total)
        let header = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let replaceNativeItem = NSMenuItem(
            title: L10n.hideNativeDock,
            action: #selector(toggleNativeDockAutohide),
            keyEquivalent: ""
        )
        replaceNativeItem.target = self
        replaceNativeItem.state = nativeAutohide ? .on : .off
        menu.addItem(replaceNativeItem)

        let avoidOverlapItem = NSMenuItem(
            title: L10n.avoidOverlap,
            action: #selector(toggleAvoidOverlap),
            keyEquivalent: ""
        )
        avoidOverlapItem.target = self
        avoidOverlapItem.state = settings.avoidNativeDockOverlap ? .on : .off
        menu.addItem(avoidOverlapItem)

        let fullScreenItem = NSMenuItem(
            title: L10n.keepOverFullScreen,
            action: #selector(toggleFullScreen),
            keyEquivalent: ""
        )
        fullScreenItem.target = self
        fullScreenItem.state = settings.showOverFullScreen ? .on : .off
        menu.addItem(fullScreenItem)

        let hoverItem = NSMenuItem(
            title: L10n.hoverMagnification,
            action: #selector(toggleHoverMagnification),
            keyEquivalent: ""
        )
        hoverItem.target = self
        hoverItem.state = settings.hoverMagnification ? .on : .off
        menu.addItem(hoverItem)

        let unpinnedItem = NSMenuItem(
            title: L10n.showUnpinnedApps,
            action: #selector(toggleShowUnpinned),
            keyEquivalent: ""
        )
        unpinnedItem.target = self
        unpinnedItem.state = settings.showRunningUnpinned ? .on : .off
        menu.addItem(unpinnedItem)

        menu.addItem(.separator())

        // Icon Size Submenu
        let sizeSubmenu = NSMenu()
        let sizes: [(String, CGFloat)] = [
            (L10n.sizeCompact, 28),
            (L10n.sizeDefault, 36),
            (L10n.sizeMedium, 44),
            (L10n.sizeLarge, 52)
        ]
        for (title, val) in sizes {
            let item = NSMenuItem(title: title, action: #selector(selectIconSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = val
            item.state = abs(settings.iconSize - val) < 1 ? .on : .off
            sizeSubmenu.addItem(item)
        }
        let sizeParent = NSMenuItem(title: L10n.iconSizeMenu, action: nil, keyEquivalent: "")
        sizeParent.submenu = sizeSubmenu
        menu.addItem(sizeParent)

        // Displays Submenu
        let screensSubmenu = NSMenu()
        let hasStackedRows = NSScreen.screens.contains(where: { $0.frame.minY >= 600 })
        for (idx, screen) in NSScreen.screens.enumerated() {
            let w = Int(screen.frame.width)
            let h = Int(screen.frame.height)
            let suffix: String
            if hasStackedRows {
                let rowLabel = screen.frame.minY >= 600 ? L10n.rowUpper : L10n.rowLower
                suffix = " — \(w)×\(h) (\(rowLabel))"
            } else {
                suffix = " — \(w)×\(h)"
            }
            let title = "\(idx + 1). \(screen.localizedName)\(suffix)"
            let sItem = NSMenuItem(title: title, action: #selector(toggleScreenEnabled(_:)), keyEquivalent: "")
            sItem.target = self
            sItem.representedObject = screen
            sItem.state = settings.isScreenEnabled(screen) ? .on : .off
            screensSubmenu.addItem(sItem)
        }
        let screensParent = NSMenuItem(title: L10n.activeScreensMenu(NSScreen.screens.count), action: nil, keyEquivalent: "")
        screensParent.submenu = screensSubmenu
        menu.addItem(screensParent)

        menu.addItem(.separator())

        let reloadItem = NSMenuItem(title: L10n.syncNow, action: #selector(reloadNow), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)

        let loginItem = NSMenuItem(title: L10n.launchAtLogin, action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = settings.launchAtLogin ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L10n.quitApp, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Menu Actions

    @objc private func toggleNativeDockAutohide() {
        let next = !DockSettings.shared.isNativeDockAutohideEnabled
        DockSettings.shared.setNativeDockAutohide(next)
    }

    @objc private func toggleAvoidOverlap() {
        DockSettings.shared.avoidNativeDockOverlap.toggle()
    }

    @objc private func toggleFullScreen() {
        DockSettings.shared.showOverFullScreen.toggle()
    }

    @objc private func toggleHoverMagnification() {
        DockSettings.shared.hoverMagnification.toggle()
    }

    @objc private func toggleShowUnpinned() {
        DockSettings.shared.showRunningUnpinned.toggle()
    }

    @objc private func selectIconSize(_ sender: NSMenuItem) {
        if let val = sender.representedObject as? CGFloat {
            DockSettings.shared.iconSize = val
        }
    }

    @objc private func toggleScreenEnabled(_ sender: NSMenuItem) {
        if let screen = sender.representedObject as? NSScreen {
            DockSettings.shared.toggleScreen(screen)
        }
    }

    @objc private func reloadNow() {
        DockModelReader.shared.reloadPlistCache()
        MultiScreenController.shared.refreshAll(forceLayout: true)
    }

    @objc private func toggleLaunchAtLogin() {
        DockSettings.shared.launchAtLogin.toggle()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
