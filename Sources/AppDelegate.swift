import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static weak var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private let statusMenu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        MultiScreenController.shared.start()
    }

    func buildFreshSettingsMenu() -> NSMenu {
        let m = NSMenu(title: "MultiScreenDock")
        populateSettingsMenu(m)
        return m
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
        populateSettingsMenu(menu)
    }

    func populateSettingsMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        statusItem?.button?.toolTip = L10n.tooltipStatus
        let settings = DockSettings.shared
        let counts = MultiScreenController.shared.statusCounts()
        let nativeAutohide = settings.isNativeDockAutohideEnabled

        let headerTitle: String
        switch settings.visibilityMode {
        case .autoHide:
            headerTitle = L10n.headerAutoHide(enabledCount: counts.enabled, total: counts.total)
        case .alwaysVisible:
            headerTitle = nativeAutohide
                ? L10n.headerAllPanels(visible: counts.visibleNow, total: counts.total)
                : L10n.headerHybrid(visible: counts.visibleNow, total: counts.total)
        }
        let header = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // Visibility Mode Radio Group
        let autoHideModeItem = NSMenuItem(
            title: L10n.modeAutoHide,
            action: #selector(selectModeAutoHide),
            keyEquivalent: ""
        )
        autoHideModeItem.target = self
        autoHideModeItem.state = (settings.visibilityMode == .autoHide) ? .on : .off
        menu.addItem(autoHideModeItem)

        let fixedModeItem = NSMenuItem(
            title: L10n.modeAlwaysVisible,
            action: #selector(selectModeAlwaysVisible),
            keyEquivalent: ""
        )
        fixedModeItem.target = self
        fixedModeItem.state = (settings.visibilityMode == .alwaysVisible) ? .on : .off
        menu.addItem(fixedModeItem)

        if settings.visibilityMode == .autoHide {
            let hintItem = NSMenuItem(
                title: L10n.showHintPill,
                action: #selector(toggleHintPill),
                keyEquivalent: ""
            )
            hintItem.target = self
            hintItem.state = settings.showHiddenHintPill ? .on : .off
            menu.addItem(hintItem)

            let respSubmenu = NSMenu()
            let respOptions: [(String, AutoHideResponsiveness)] = [
                (L10n.respFast, .fast),
                (L10n.respBalanced, .balanced),
                (L10n.respRelaxed, .relaxed)
            ]
            for (title, val) in respOptions {
                let rItem = NSMenuItem(title: title, action: #selector(selectResponsiveness(_:)), keyEquivalent: "")
                rItem.target = self
                rItem.representedObject = val.rawValue
                rItem.state = (settings.responsiveness == val) ? .on : .off
                respSubmenu.addItem(rItem)
            }
            let respParent = NSMenuItem(title: L10n.responsivenessMenu, action: nil, keyEquivalent: "")
            respParent.submenu = respSubmenu
            menu.addItem(respParent)
        }

        menu.addItem(.separator())

        let skipPrimaryItem = NSMenuItem(
            title: L10n.skipPrimaryDisplay,
            action: #selector(toggleSkipPrimary),
            keyEquivalent: ""
        )
        skipPrimaryItem.target = self
        skipPrimaryItem.state = settings.skipPrimaryDisplay ? .on : .off
        menu.addItem(skipPrimaryItem)

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
            let primaryTag = settings.isPrimaryDisplay(screen) ? ", \(L10n.primaryBadge)" : ""
            let suffix: String
            if hasStackedRows {
                let rowLabel = screen.frame.minY >= 600 ? L10n.rowUpper : L10n.rowLower
                suffix = " — \(w)×\(h) (\(rowLabel)\(primaryTag))"
            } else {
                suffix = primaryTag.isEmpty ? " — \(w)×\(h)" : " — \(w)×\(h) (\(L10n.primaryBadge))"
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

        // Language Submenu
        let langSubmenu = NSMenu()
        let autoTitle = L10n.languageSystemAuto(L10n.systemDetectedLanguage.nativeDisplayName)
        let autoItem = NSMenuItem(title: autoTitle, action: #selector(selectAppLanguage(_:)), keyEquivalent: "")
        autoItem.target = self
        autoItem.representedObject = AppLanguage.system.rawValue
        autoItem.state = (settings.appLanguage == .system) ? .on : .off
        langSubmenu.addItem(autoItem)
        langSubmenu.addItem(.separator())

        for lang in AppLanguage.allCases where lang != .system {
            let lItem = NSMenuItem(title: lang.nativeDisplayName, action: #selector(selectAppLanguage(_:)), keyEquivalent: "")
            lItem.target = self
            lItem.representedObject = lang.rawValue
            lItem.state = (settings.appLanguage == lang) ? .on : .off
            langSubmenu.addItem(lItem)
        }
        let langParent = NSMenuItem(title: L10n.languageMenu, action: nil, keyEquivalent: "")
        langParent.submenu = langSubmenu
        menu.addItem(langParent)

        menu.addItem(.separator())

        let reloadItem = NSMenuItem(title: L10n.syncNow, action: #selector(reloadNow), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)

        let loginTitle = settings.launchAtLoginRequiresApproval
            ? "\(L10n.launchAtLogin)\(L10n.loginItemRequiresApprovalBadge)"
            : L10n.launchAtLogin
        let loginItem = NSMenuItem(title: loginTitle, action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = settings.launchAtLogin ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let coffeeItem = NSMenuItem(title: L10n.buyMeACoffee, action: #selector(openBuyMeACoffee), keyEquivalent: "")
        coffeeItem.target = self
        if let cup = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: nil) {
            cup.isTemplate = true
            coffeeItem.image = cup
        }
        menu.addItem(coffeeItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L10n.quitApp, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Menu Actions

    @objc private func selectModeAutoHide() {
        DockSettings.shared.visibilityMode = .autoHide
    }

    @objc private func selectModeAlwaysVisible() {
        DockSettings.shared.visibilityMode = .alwaysVisible
    }

    @objc private func toggleHintPill() {
        DockSettings.shared.showHiddenHintPill.toggle()
    }

    @objc private func selectResponsiveness(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String,
           let val = AutoHideResponsiveness(rawValue: raw) {
            DockSettings.shared.responsiveness = val
        }
    }

    @objc private func toggleSkipPrimary() {
        DockSettings.shared.skipPrimaryDisplay.toggle()
    }

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
        DockModelReader.shared.reloadPlistCache(clearIcons: true)
        MultiScreenController.shared.refreshAll(forceLayout: true)
    }

    @objc private func toggleLaunchAtLogin() {
        DockSettings.shared.launchAtLogin.toggle()
    }

    @objc private func selectAppLanguage(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String,
           let lang = AppLanguage(rawValue: raw) {
            DockSettings.shared.appLanguage = lang
            statusItem?.button?.toolTip = L10n.tooltipStatus
        }
    }

    @objc private func openBuyMeACoffee() {
        NSWorkspace.shared.open(L10n.buyMeACoffeeURL)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
