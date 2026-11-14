import Cocoa

enum DockWindowOverlapDetector {
    private static let ignoredOwnerNames: Set<String> = [
        "Window Server",
        "Dock",
        "Control Center",
        "NotificationCenter",
        "Notification Center",
        "SystemUIServer",
        "Spotlight",
        "loginwindow",
        "Wallpaper"
    ]

    /// Queries on-screen standard application windows (layer 0) using public CoreGraphics metadata
    /// (`CGWindowListCopyWindowInfo`, which requires zero Accessibility or Screen Recording permissions)
    /// and converts their bounds into AppKit global screen coordinates.
    static func currentStandardWindowRectsInAppKit(screens: [NSScreen] = NSScreen.screens) -> [NSRect] {
        guard let primary = screens.first else { return [] }
        let primaryHeight = primary.frame.height
        let ownPID = ProcessInfo.processInfo.processIdentifier

        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        var rects: [NSRect] = []
        rects.reserveCapacity(16)

        for entry in infoList {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            if let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid == ownPID { continue }
            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha <= 0.05 { continue }
            if let onScreen = entry[kCGWindowIsOnscreen as String] as? Bool, !onScreen { continue }
            if let ownerName = entry[kCGWindowOwnerName as String] as? String,
               ignoredOwnerNames.contains(ownerName) {
                continue
            }
            guard let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict),
                  cgRect.width >= 80,
                  cgRect.height >= 60 else {
                continue
            }
            let appKitRect = DockLayoutMath.quartzRectToAppKit(cgRect, primaryScreenHeight: primaryHeight)
            rects.append(appKitRect)
        }

        return rects
    }
}

final class MultiScreenController {
    static let shared = MultiScreenController()

    private struct ScreenAutoHideContext {
        let screen: NSScreen
        let runtimeKey: String
        let hasBelow: Bool
    }

    private var panelsByScreenKey: [String: DockBarPanel] = [:]
    private var hintsByScreenKey: [String: EdgeHintPanel] = [:]
    private var cachedAutoHideScreens: [ScreenAutoHideContext] = []
    private var smartOverlappedScreenKeys: Set<String> = []

    private var revealWorkItems: [String: DispatchWorkItem] = [:]
    private var hideWorkItems: [String: DispatchWorkItem] = [:]
    private var trailingMouseEval: DispatchWorkItem?

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var pollTimer: Timer?
    private var lastNativeInsetsSignature: String = ""
    private var lastMouseEvalTime: CFAbsoluteTime = 0

    private init() {}

    func start() {
        DockSettings.shared.onChange = { [weak self] in
            self?.cancelAllPendingTransitions()
            self?.refreshAll(forceLayout: true)
        }

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleScreenChange), name: NSApplication.didChangeScreenParametersNotification, object: nil)

        let wsnc = NSWorkspace.shared.notificationCenter
        let wsEvents: [NSNotification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification
        ]
        for name in wsEvents {
            wsnc.addObserver(self, selector: #selector(handleWorkspaceEvent), name: name, object: nil)
        }

        refreshAll(forceLayout: true)

        let timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.periodicTick()
        }
        timer.tolerance = 0.25
        pollTimer = timer
    }

    private func syncMouseMonitors(shouldListen: Bool) {
        if shouldListen {
            guard globalMouseMonitor == nil, localMouseMonitor == nil else { return }
            let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]

            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
                self?.throttledMouseCheck()
            }

            localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                self?.throttledMouseCheck()
                return event
            }
        } else {
            trailingMouseEval?.cancel()
            trailingMouseEval = nil
            if let g = globalMouseMonitor {
                NSEvent.removeMonitor(g)
                globalMouseMonitor = nil
            }
            if let l = localMouseMonitor {
                NSEvent.removeMonitor(l)
                localMouseMonitor = nil
            }
        }
    }

    private func isScreenAutoHiding(key: String) -> Bool {
        switch DockSettings.shared.visibilityMode {
        case .alwaysVisible:
            return false
        case .autoHide:
            return true
        case .smartAutoHide:
            return smartOverlappedScreenKeys.contains(key)
        }
    }

    private func throttledMouseCheck() {
        guard !cachedAutoHideScreens.isEmpty else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastMouseEvalTime
        if elapsed < 0.016 {
            trailingMouseEval?.cancel()
            let remaining = max(0.004, 0.016 - elapsed)
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.trailingMouseEval = nil
                self.lastMouseEvalTime = CFAbsoluteTimeGetCurrent()
                self.evaluateAutoHideState(at: NSEvent.mouseLocation)
            }
            trailingMouseEval = work
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: work)
            return
        }
        trailingMouseEval?.cancel()
        trailingMouseEval = nil
        lastMouseEvalTime = now
        evaluateAutoHideState(at: NSEvent.mouseLocation)
    }

    @objc private func handleScreenChange() {
        HoverBubbleController.shared.hide()
        cancelAllPendingTransitions()
        refreshAll(forceLayout: true)
    }

    @objc private func handleWorkspaceEvent() {
        refreshAll(forceLayout: false)
    }

    private func periodicTick() {
        let plistChanged = DockModelReader.shared.checkPlistChangedAndReloadIfNeeded()
        let sig = computeNativeInsetsSignature()
        if plistChanged || sig != lastNativeInsetsSignature {
            lastNativeInsetsSignature = sig
            refreshAll(forceLayout: plistChanged)
            return
        }

        let mode = DockSettings.shared.visibilityMode
        if mode == .smartAutoHide {
            let currentOverlapped = computeCurrentSmartOverlappedKeys()
            if currentOverlapped != smartOverlappedScreenKeys {
                refreshAll(forceLayout: false)
                return
            }
        }

        if !cachedAutoHideScreens.isEmpty {
            evaluateAutoHideState(at: NSEvent.mouseLocation)
        }
    }

    private func computeCurrentSmartOverlappedKeys(screens: [NSScreen] = NSScreen.screens) -> Set<String> {
        let settings = DockSettings.shared
        let windowRects = DockWindowOverlapDetector.currentStandardWindowRectsInAppKit(screens: screens)
        guard !windowRects.isEmpty else { return [] }
        var overlapped = Set<String>()
        for screen in screens where settings.isScreenEnabled(screen) {
            let key = settings.runtimeScreenKey(for: screen)
            guard let panel = panelsByScreenKey[key] else { continue }
            if DockLayoutMath.doesAnyWindowOverlapDock(dockZone: panel.dodgeZone(on: screen), windowRectsInAppKit: windowRects) {
                overlapped.insert(key)
            }
        }
        return overlapped
    }

    private func computeNativeInsetsSignature() -> String {
        NSScreen.screens.map { s in
            let insetBottom = Int(round(s.visibleFrame.minY - s.frame.minY))
            return "\(DockSettings.shared.runtimeScreenKey(for: s)):\(insetBottom)"
        }.joined(separator: "|")
    }

    func statusCounts() -> (enabled: Int, visibleNow: Int, total: Int) {
        let screens = NSScreen.screens
        let enabled = screens.filter { DockSettings.shared.isScreenEnabled($0) }.count
        let visibleNow = panelsByScreenKey.values.filter { $0.isRevealed }.count
        return (enabled, visibleNow, screens.count)
    }

    private func cancelPendingTransitions(for key: String) {
        revealWorkItems[key]?.cancel()
        revealWorkItems.removeValue(forKey: key)
        hideWorkItems[key]?.cancel()
        hideWorkItems.removeValue(forKey: key)
    }

    private func cancelAllPendingTransitions() {
        trailingMouseEval?.cancel()
        trailingMouseEval = nil
        revealWorkItems.values.forEach { $0.cancel() }
        revealWorkItems.removeAll()
        hideWorkItems.values.forEach { $0.cancel() }
        hideWorkItems.removeAll()
    }

    // MARK: - Main Layout & Visibility Refresh

    func refreshAll(forceLayout: Bool) {
        let screens = NSScreen.screens
        let allFrames = screens.map { $0.frame }
        let settings = DockSettings.shared
        let mode = settings.visibilityMode
        let avoidOverlap = settings.avoidNativeDockOverlap

        struct ScreenPlan {
            let screen: NSScreen
            let key: String
            let eligible: Bool
            let hasBelow: Bool
        }

        let plans: [ScreenPlan] = screens.map { screen in
            let key = settings.runtimeScreenKey(for: screen)
            let enabled = settings.isScreenEnabled(screen)
            let nativeDockBottomInset = screen.visibleFrame.minY - screen.frame.minY
            let suppressed = avoidOverlap && (nativeDockBottomInset > 10.0)
            let hasBelow = DockLayoutMath.hasMonitorDirectlyBelow(targetFrame: screen.frame, among: allFrames)
            return ScreenPlan(screen: screen, key: key, eligible: enabled && !suppressed, hasBelow: hasBelow)
        }

        let activeKeys = Set(plans.map { $0.key })
        let eligiblePlans = plans.filter { $0.eligible }

        // Only enumerate Dock items & running apps when at least one display will actually render a bar
        let items: [DockItem] = eligiblePlans.isEmpty
            ? []
            : DockModelReader.shared.buildItems(includeUnpinnedRunning: settings.showRunningUnpinned)
        let mousePos = NSEvent.mouseLocation

        for plan in plans {
            let screen = plan.screen
            let key = plan.key

            if !plan.eligible {
                cancelPendingTransitions(for: key)
                panelsByScreenKey[key]?.conceal(animated: false)
                hintsByScreenKey[key]?.orderOut(nil)
                continue
            }

            let panel: DockBarPanel
            if let existing = panelsByScreenKey[key] {
                panel = existing
            } else {
                panel = DockBarPanel(screen: screen)
                panelsByScreenKey[key] = panel
            }
            panel.updateContentAndGeometry(items: items, on: screen, forceLayout: forceLayout)
        }

        if mode == .smartAutoHide && !eligiblePlans.isEmpty {
            smartOverlappedScreenKeys = computeCurrentSmartOverlappedKeys(screens: screens)
        } else {
            smartOverlappedScreenKeys.removeAll()
        }

        cachedAutoHideScreens = eligiblePlans
            .filter { plan in
                mode == .autoHide || (mode == .smartAutoHide && smartOverlappedScreenKeys.contains(plan.key))
            }
            .map { ScreenAutoHideContext(screen: $0.screen, runtimeKey: $0.key, hasBelow: $0.hasBelow) }

        syncMouseMonitors(shouldListen: !cachedAutoHideScreens.isEmpty)

        for plan in eligiblePlans {
            let screen = plan.screen
            let key = plan.key
            guard let panel = panelsByScreenKey[key] else { continue }

            if !isScreenAutoHiding(key: key) {
                cancelPendingTransitions(for: key)
                hintsByScreenKey[key]?.orderOut(nil)
                if !panel.isRevealed {
                    panel.reveal(animated: true, on: screen)
                }
            } else {
                updateHintVisibility(for: screen, key: key, dockRevealed: panel.isRevealed)
                let inKeepAlive = panel.keepAliveZone(on: screen).contains(mousePos)
                let inTrigger = panel.triggerZone(on: screen, hasScreenBelow: plan.hasBelow).contains(mousePos)

                if panel.isRevealed {
                    if !inKeepAlive && !panel.hasActivePopup {
                        scheduleHideIfNeeded(for: key, screen: screen, panel: panel)
                    }
                } else if inTrigger {
                    scheduleRevealIfNeeded(for: key, screen: screen, panel: panel, hasBelow: plan.hasBelow)
                }
            }
        }

        // Limpiar monitores desconectados
        for (key, panel) in panelsByScreenKey where !activeKeys.contains(key) {
            cancelPendingTransitions(for: key)
            panel.orderOut(nil)
            panel.close()
            panelsByScreenKey.removeValue(forKey: key)
        }
        for (key, hint) in hintsByScreenKey where !activeKeys.contains(key) {
            hint.orderOut(nil)
            hint.close()
            hintsByScreenKey.removeValue(forKey: key)
        }

        lastNativeInsetsSignature = computeNativeInsetsSignature()
    }

    // MARK: - Real-Time Auto-Hide State Machine

    func evaluateAutoHideNow() {
        guard !cachedAutoHideScreens.isEmpty else { return }
        evaluateAutoHideState(at: NSEvent.mouseLocation)
    }

    private func evaluateAutoHideState(at mousePos: NSPoint) {
        guard !cachedAutoHideScreens.isEmpty else { return }

        for ctx in cachedAutoHideScreens {
            let key = ctx.runtimeKey
            let screen = ctx.screen
            guard let panel = panelsByScreenKey[key] else { continue }

            if panel.isRevealed {
                revealWorkItems[key]?.cancel()
                revealWorkItems.removeValue(forKey: key)

                let insideKeepAlive = panel.keepAliveZone(on: screen).contains(mousePos) || panel.hasActivePopup
                if insideKeepAlive {
                    if let pendingHide = hideWorkItems[key] {
                        pendingHide.cancel()
                        hideWorkItems.removeValue(forKey: key)
                    }
                } else {
                    scheduleHideIfNeeded(for: key, screen: screen, panel: panel)
                }
            } else {
                hideWorkItems[key]?.cancel()
                hideWorkItems.removeValue(forKey: key)

                let insideTrigger = panel.triggerZone(on: screen, hasScreenBelow: ctx.hasBelow).contains(mousePos)
                if insideTrigger {
                    scheduleRevealIfNeeded(for: key, screen: screen, panel: panel, hasBelow: ctx.hasBelow)
                } else if let pendingReveal = revealWorkItems[key] {
                    pendingReveal.cancel()
                    revealWorkItems.removeValue(forKey: key)
                }
            }
        }
    }

    private func scheduleRevealIfNeeded(for key: String, screen: NSScreen, panel: DockBarPanel, hasBelow: Bool) {
        guard revealWorkItems[key] == nil else { return }

        let resp = DockSettings.shared.responsiveness
        let dwell = hasBelow ? resp.stackedEdgeDwell : resp.bottomEdgeDwell

        let work = DispatchWorkItem { [weak self, weak panel] in
            guard let self = self, let panel = panel else { return }
            self.revealWorkItems.removeValue(forKey: key)

            guard self.isScreenAutoHiding(key: key),
                  DockSettings.shared.isScreenEnabled(screen) else { return }

            let currentMouse = NSEvent.mouseLocation
            let stillInTrigger = panel.triggerZone(on: screen, hasScreenBelow: hasBelow).contains(currentMouse)
            guard stillInTrigger else { return }

            self.updateHintVisibility(for: screen, key: key, dockRevealed: true)
            panel.reveal(animated: true, on: screen)
        }

        revealWorkItems[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + dwell, execute: work)
    }

    private func scheduleHideIfNeeded(for key: String, screen: NSScreen, panel: DockBarPanel) {
        guard hideWorkItems[key] == nil else { return }

        let delay = DockSettings.shared.responsiveness.hideDelay

        let work = DispatchWorkItem { [weak self, weak panel] in
            guard let self = self, let panel = panel else { return }
            self.hideWorkItems.removeValue(forKey: key)

            guard self.isScreenAutoHiding(key: key) else { return }

            let currentMouse = NSEvent.mouseLocation
            if panel.keepAliveZone(on: screen).contains(currentMouse) || panel.hasActivePopup {
                return
            }

            panel.conceal(animated: true) { [weak self] in
                self?.updateHintVisibility(for: screen, key: key, dockRevealed: false)
            }
        }

        hideWorkItems[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func updateHintVisibility(for screen: NSScreen, key: String, dockRevealed: Bool) {
        let shouldShowHint = isScreenAutoHiding(key: key)
            && DockSettings.shared.showHiddenHintPill
            && !dockRevealed
            && DockSettings.shared.isScreenEnabled(screen)

        if shouldShowHint {
            let hint: EdgeHintPanel
            if let existing = hintsByScreenKey[key] {
                hint = existing
            } else {
                hint = EdgeHintPanel(screen: screen)
                hintsByScreenKey[key] = hint
            }
            hint.updatePosition(on: screen)
            if !hint.isVisible {
                hint.alphaValue = 0.0
                hint.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.20
                    hint.animator().alphaValue = 1.0
                }
            }
        } else {
            hintsByScreenKey[key]?.orderOut(nil)
        }
    }
}
