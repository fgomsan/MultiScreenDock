import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static weak var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private let statusMenu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bid = Bundle.main.bundleIdentifier ?? DockSettings.bundleIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let alreadyRunning = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
            .contains { $0.processIdentifier != ownPID && !$0.isTerminated }
        if alreadyRunning {
            NSApp.terminate(nil)
            return
        }

        Self.shared = self
        NSApp.setActivationPolicy(.accessory)

        if Bundle.main.bundleURL.pathExtension == "app" {
            DockSettings.shared.migrateLegacyLaunchAgentIfNeeded()
        }

        setupStatusItem()
        UpdateChecker.shared.onUpdateStateChange = { [weak self] in
            self?.refreshStatusItemIndicator()
        }
        UpdateChecker.shared.startAutomaticChecksIfEnabled()
        MultiScreenController.shared.start()
    }

    func buildFreshSettingsMenu(includeShortcuts: Bool = true) -> NSMenu {
        let m = NSMenu(title: "MultiScreenDock")
        populateSettingsMenu(m, includeShortcuts: includeShortcuts)
        return m
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "MultiScreenDock") {
                img.isTemplate = true
                button.image = img
                button.imagePosition = .imageLeading
            } else {
                button.title = "Dock+"
            }
            button.toolTip = L10n.tooltipStatus
        }
        refreshStatusItemIndicator()
        statusMenu.delegate = self
        statusItem.menu = statusMenu
    }

    private func refreshStatusItemIndicator() {
        guard let button = statusItem?.button else { return }
        let hasUpdate = (UpdateChecker.shared.availableUpdate != nil)
        if button.image != nil {
            button.title = hasUpdate ? " •" : ""
        } else {
            button.title = hasUpdate ? "Dock+ •" : "Dock+"
        }
    }

    // MARK: - Dynamic Menu Construction

    func menuNeedsUpdate(_ menu: NSMenu) {
        populateSettingsMenu(menu, includeShortcuts: true)
    }

    func populateSettingsMenu(_ menu: NSMenu, includeShortcuts: Bool = true) {
        menu.removeAllItems()
        statusItem?.button?.toolTip = L10n.tooltipStatus
        refreshStatusItemIndicator()
        let settings = DockSettings.shared
        let counts = MultiScreenController.shared.statusCounts()
        let nativeAutohide = settings.isNativeDockAutohideEnabled

        let headerTitle: String
        switch settings.visibilityMode {
        case .autoHide:
            headerTitle = L10n.headerAutoHide(enabledCount: counts.enabled, total: counts.total)
        case .smartAutoHide:
            headerTitle = L10n.headerSmartAutoHide(visible: counts.visibleNow, enabledCount: counts.enabled, total: counts.total)
        case .alwaysVisible:
            headerTitle = nativeAutohide
                ? L10n.headerAllPanels(visible: counts.visibleNow, total: counts.total)
                : L10n.headerHybrid(visible: counts.visibleNow, total: counts.total)
        }
        let header = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if let available = UpdateChecker.shared.availableUpdate {
            let updateBannerItem = NSMenuItem(
                title: L10n.updateAvailableMenu(available.version),
                action: #selector(showAvailableUpdate),
                keyEquivalent: ""
            )
            updateBannerItem.target = self
            menu.addItem(updateBannerItem)
        }

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

        let smartAutoHideModeItem = NSMenuItem(
            title: L10n.modeSmartAutoHide,
            action: #selector(selectModeSmartAutoHide),
            keyEquivalent: ""
        )
        smartAutoHideModeItem.target = self
        smartAutoHideModeItem.state = (settings.visibilityMode == .smartAutoHide) ? .on : .off
        menu.addItem(smartAutoHideModeItem)

        let fixedModeItem = NSMenuItem(
            title: L10n.modeAlwaysVisible,
            action: #selector(selectModeAlwaysVisible),
            keyEquivalent: ""
        )
        fixedModeItem.target = self
        fixedModeItem.state = (settings.visibilityMode == .alwaysVisible) ? .on : .off
        menu.addItem(fixedModeItem)

        if settings.visibilityMode == .autoHide || settings.visibilityMode == .smartAutoHide {
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
        var matchedPreset = false
        for (title, val) in sizes {
            let item = NSMenuItem(title: title, action: #selector(selectIconSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = val
            let isMatch = abs(settings.iconSize - val) < 1
            if isMatch { matchedPreset = true }
            item.state = isMatch ? .on : .off
            sizeSubmenu.addItem(item)
        }
        if let nativePts = DockSettings.readNativeTileSize(),
           !sizes.contains(where: { abs(CGFloat(nativePts) - $0.1) < 1 }) || !matchedPreset {
            let customPts = !matchedPreset ? settings.iconSize : CGFloat(nativePts)
            sizeSubmenu.addItem(.separator())
            let sysItem = NSMenuItem(
                title: L10n.sizeSystemDock(Int(round(customPts))),
                action: #selector(selectIconSize(_:)),
                keyEquivalent: ""
            )
            sysItem.target = self
            sysItem.representedObject = customPts
            sysItem.state = !matchedPreset ? .on : .off
            sizeSubmenu.addItem(sysItem)
        }
        let sizeParent = NSMenuItem(title: L10n.iconSizeMenu, action: nil, keyEquivalent: "")
        sizeParent.submenu = sizeSubmenu
        menu.addItem(sizeParent)

        // Folder Stack Style Submenu
        let stackStyleSubmenu = NSMenu()
        let stackChoices: [(String, FolderStackStylePreference)] = [
            (L10n.stackStyleDockDefault, .dockDefault),
            (L10n.stackStyleFan, .fan),
            (L10n.stackStyleGrid, .grid),
            (L10n.stackStyleList, .list)
        ]
        for (title, pref) in stackChoices {
            let stItem = NSMenuItem(title: title, action: #selector(selectFolderStackStyle(_:)), keyEquivalent: "")
            stItem.target = self
            stItem.representedObject = pref.rawValue
            stItem.state = (settings.folderStackStyle == pref) ? .on : .off
            stackStyleSubmenu.addItem(stItem)
        }
        let stackStyleParent = NSMenuItem(title: L10n.stackStyleMenu, action: nil, keyEquivalent: "")
        stackStyleParent.submenu = stackStyleSubmenu
        menu.addItem(stackStyleParent)

        // Displays Submenu
        let screensSubmenu = NSMenu()
        let screens = NSScreen.screens
        let allFrames = screens.map { $0.frame }
        for (idx, screen) in screens.enumerated() {
            let w = Int(screen.frame.width)
            let h = Int(screen.frame.height)
            let primaryTag = settings.isPrimaryDisplay(screen) ? ", \(L10n.primaryBadge)" : ""
            let hasBelow = DockLayoutMath.hasMonitorDirectlyBelow(targetFrame: screen.frame, among: allFrames)
            let hasAbove = DockLayoutMath.hasMonitorDirectlyAbove(targetFrame: screen.frame, among: allFrames)
            let suffix: String
            if hasBelow && !hasAbove {
                suffix = " — \(w)×\(h) (\(L10n.rowUpper)\(primaryTag))"
            } else if hasAbove && !hasBelow {
                suffix = " — \(w)×\(h) (\(L10n.rowLower)\(primaryTag))"
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
        let screensParent = NSMenuItem(title: L10n.activeScreensMenu(screens.count), action: nil, keyEquivalent: "")
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

        let reloadItem = NSMenuItem(title: L10n.syncNow, action: #selector(reloadNow), keyEquivalent: includeShortcuts ? "r" : "")
        reloadItem.target = self
        menu.addItem(reloadItem)

        let loginStatus = settings.launchAtLogin
        let loginTitle = settings.launchAtLoginRequiresApproval
            ? "\(L10n.launchAtLogin)\(L10n.loginItemRequiresApprovalBadge)"
            : L10n.launchAtLogin
        let loginItem = NSMenuItem(title: loginTitle, action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = loginStatus ? .on : .off
        menu.addItem(loginItem)

        let checkUpdatesItem = NSMenuItem(title: L10n.checkForUpdates, action: #selector(checkUpdatesNow), keyEquivalent: "")
        checkUpdatesItem.target = self
        if let badge = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil) {
            badge.isTemplate = true
            checkUpdatesItem.image = badge
        }
        menu.addItem(checkUpdatesItem)

        let autoUpdatesItem = NSMenuItem(title: L10n.autoCheckUpdates, action: #selector(toggleAutoCheckUpdates), keyEquivalent: "")
        autoUpdatesItem.target = self
        autoUpdatesItem.state = settings.autoCheckUpdates ? .on : .off
        menu.addItem(autoUpdatesItem)

        menu.addItem(.separator())

        let feedbackItem = NSMenuItem(title: L10n.suggestImprovement, action: #selector(openFeedbackPage), keyEquivalent: "")
        feedbackItem.target = self
        if let bulb = NSImage(systemSymbolName: "lightbulb", accessibilityDescription: nil) {
            bulb.isTemplate = true
            feedbackItem.image = bulb
        }
        menu.addItem(feedbackItem)

        let coffeeItem = NSMenuItem(title: L10n.buyMeACoffee, action: #selector(openBuyMeACoffee), keyEquivalent: "")
        coffeeItem.target = self
        if let cup = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: nil) {
            cup.isTemplate = true
            coffeeItem.image = cup
        }
        menu.addItem(coffeeItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L10n.quitApp, action: #selector(quitApp), keyEquivalent: includeShortcuts ? "q" : "")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Menu Actions

    @objc private func selectModeAutoHide() {
        DockSettings.shared.visibilityMode = .autoHide
    }

    @objc private func selectModeSmartAutoHide() {
        DockSettings.shared.visibilityMode = .smartAutoHide
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

    @objc private func selectFolderStackStyle(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String,
           let pref = FolderStackStylePreference(rawValue: raw) {
            DockSettings.shared.folderStackStyle = pref
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

    @objc private func openFeedbackPage() {
        UpdateChecker.shared.openFeedbackIssuePage()
    }

    @objc private func checkUpdatesNow() {
        UpdateChecker.shared.checkNow(userInitiated: true)
    }

    @objc private func showAvailableUpdate() {
        UpdateChecker.shared.presentAvailableUpdateOrCheck()
    }

    @objc private func toggleAutoCheckUpdates() {
        DockSettings.shared.autoCheckUpdates.toggle()
        if DockSettings.shared.autoCheckUpdates {
            UpdateChecker.shared.startAutomaticChecksIfEnabled()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
