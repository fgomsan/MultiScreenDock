import Cocoa

final class MultiScreenController {
    static let shared = MultiScreenController()

    private var panelsByScreenKey: [String: DockBarPanel] = [:]
    private var hintsByScreenKey: [String: EdgeHintPanel] = [:]

    private var revealWorkItems: [String: DispatchWorkItem] = [:]
    private var hideWorkItems: [String: DispatchWorkItem] = [:]

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

        installMouseMonitors()
        refreshAll(forceLayout: true)

        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.periodicTick()
        }
    }

    private func installMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.throttledMouseCheck()
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.throttledMouseCheck()
            return event
        }
    }

    private func throttledMouseCheck() {
        guard DockSettings.shared.visibilityMode == .autoHide else { return }
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastMouseEvalTime < 0.016 { return } // ~60 Hz max
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
        } else if DockSettings.shared.visibilityMode == .autoHide {
            evaluateAutoHideState(at: NSEvent.mouseLocation)
        }
    }

    private func computeNativeInsetsSignature() -> String {
        NSScreen.screens.map { s in
            let insetBottom = Int(round(s.visibleFrame.minY - s.frame.minY))
            return "\(DockSettings.shared.screenKey(for: s)):\(insetBottom)"
        }.joined(separator: "|")
    }

    func statusCounts() -> (enabled: Int, visibleNow: Int, total: Int) {
        let screens = NSScreen.screens
        let enabled = screens.filter { DockSettings.shared.isScreenEnabled($0) }.count
        let visibleNow = panelsByScreenKey.values.filter { $0.isRevealed }.count
        return (enabled, visibleNow, screens.count)
    }

    private func hasMonitorDirectlyBelow(_ target: NSScreen, among screens: [NSScreen]) -> Bool {
        for other in screens where other !== target {
            let verticalTouch = abs(other.frame.maxY - target.frame.minY) <= 14.0
            let overlapX = min(target.frame.maxX, other.frame.maxX) - max(target.frame.minX, other.frame.minX)
            if verticalTouch && overlapX > 40.0 {
                return true
            }
        }
        return false
    }

    private func cancelPendingTransitions(for key: String) {
        revealWorkItems[key]?.cancel()
        revealWorkItems.removeValue(forKey: key)
        hideWorkItems[key]?.cancel()
        hideWorkItems.removeValue(forKey: key)
    }

    private func cancelAllPendingTransitions() {
        revealWorkItems.values.forEach { $0.cancel() }
        revealWorkItems.removeAll()
        hideWorkItems.values.forEach { $0.cancel() }
        hideWorkItems.removeAll()
    }

    // MARK: - Main Layout & Visibility Refresh

    func refreshAll(forceLayout: Bool) {
        let screens = NSScreen.screens
        let settings = DockSettings.shared
        let items = DockModelReader.shared.buildItems(includeUnpinnedRunning: settings.showRunningUnpinned)
        let mousePos = NSEvent.mouseLocation

        var activeKeys = Set<String>()

        for screen in screens {
            let key = settings.screenKey(for: screen)
            activeKeys.insert(key)

            let enabledOnThisScreen = settings.isScreenEnabled(screen)
            let nativeDockBottomInset = screen.visibleFrame.minY - screen.frame.minY
            let nativeDockVisibleHere = nativeDockBottomInset > 10.0
            let suppressedByNative = settings.avoidNativeDockOverlap && nativeDockVisibleHere

            if !enabledOnThisScreen || suppressedByNative {
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

            switch settings.visibilityMode {
            case .alwaysVisible:
                cancelPendingTransitions(for: key)
                hintsByScreenKey[key]?.orderOut(nil)
                if !panel.isRevealed {
                    panel.reveal(animated: true, on: screen)
                }

            case .autoHide:
                updateHintVisibility(for: screen, key: key, dockRevealed: panel.isRevealed)
                let hasBelow = hasMonitorDirectlyBelow(screen, among: screens)
                let inKeepAlive = panel.keepAliveZone(on: screen).contains(mousePos)
                let inTrigger = panel.triggerZone(on: screen, hasScreenBelow: hasBelow).contains(mousePos)

                if panel.isRevealed {
                    if !inKeepAlive && !panel.isContextMenuOpen {
                        scheduleHideIfNeeded(for: key, screen: screen, panel: panel)
                    }
                } else if inTrigger {
                    scheduleRevealIfNeeded(for: key, screen: screen, panel: panel, hasBelow: hasBelow)
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

    private func evaluateAutoHideState(at mousePos: NSPoint) {
        let screens = NSScreen.screens
        let settings = DockSettings.shared
        guard settings.visibilityMode == .autoHide else { return }

        for screen in screens {
            let key = settings.screenKey(for: screen)
            guard settings.isScreenEnabled(screen),
                  let panel = panelsByScreenKey[key] else {
                continue
            }

            let nativeDockVisibleHere = (screen.visibleFrame.minY - screen.frame.minY) > 10.0
            if settings.avoidNativeDockOverlap && nativeDockVisibleHere {
                cancelPendingTransitions(for: key)
                if panel.isRevealed { panel.conceal(animated: false) }
                hintsByScreenKey[key]?.orderOut(nil)
                continue
            }

            let hasBelow = hasMonitorDirectlyBelow(screen, among: screens)

            if panel.isRevealed {
                revealWorkItems[key]?.cancel()
                revealWorkItems.removeValue(forKey: key)

                let insideKeepAlive = panel.keepAliveZone(on: screen).contains(mousePos) || panel.isContextMenuOpen
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

                let insideTrigger = panel.triggerZone(on: screen, hasScreenBelow: hasBelow).contains(mousePos)
                if insideTrigger {
                    scheduleRevealIfNeeded(for: key, screen: screen, panel: panel, hasBelow: hasBelow)
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

            guard DockSettings.shared.visibilityMode == .autoHide,
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

            guard DockSettings.shared.visibilityMode == .autoHide else { return }

            let currentMouse = NSEvent.mouseLocation
            if panel.keepAliveZone(on: screen).contains(currentMouse) || panel.isContextMenuOpen {
                return
            }

            panel.conceal(animated: true)
            self.updateHintVisibility(for: screen, key: key, dockRevealed: false)
        }

        hideWorkItems[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func updateHintVisibility(for screen: NSScreen, key: String, dockRevealed: Bool) {
        let shouldShowHint = DockSettings.shared.visibilityMode == .autoHide
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
