import Cocoa

final class MultiScreenController {
    static let shared = MultiScreenController()

    private var panelsByScreenKey: [String: DockBarPanel] = [:]
    private var pollTimer: Timer?
    private var lastNativeInsetsSignature: String = ""

    private init() {}

    func start() {
        DockSettings.shared.onChange = { [weak self] in
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

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            self?.periodicTick()
        }
    }

    @objc private func handleScreenChange() {
        HoverBubbleController.shared.hide()
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
        }
    }

    private func computeNativeInsetsSignature() -> String {
        NSScreen.screens.map { s in
            let insetBottom = Int(round(s.visibleFrame.minY - s.frame.minY))
            return "\(DockSettings.shared.screenKey(for: s)):\(insetBottom)"
        }.joined(separator: "|")
    }

    func activePanelCount() -> (visible: Int, total: Int) {
        let total = NSScreen.screens.count
        let visible = panelsByScreenKey.values.filter { $0.isVisible }.count
        return (visible, total)
    }

    func refreshAll(forceLayout: Bool) {
        let screens = NSScreen.screens
        let settings = DockSettings.shared
        let items = DockModelReader.shared.buildItems(includeUnpinnedRunning: settings.showRunningUnpinned)

        var activeKeys = Set<String>()

        for screen in screens {
            let key = settings.screenKey(for: screen)
            activeKeys.insert(key)

            let enabledOnThisScreen = settings.isScreenEnabled(screen)
            let nativeDockBottomInset = screen.visibleFrame.minY - screen.frame.minY
            let nativeDockVisibleHere = nativeDockBottomInset > 10.0

            let shouldShow = enabledOnThisScreen && !(settings.avoidNativeDockOverlap && nativeDockVisibleHere)

            if shouldShow {
                let panel: DockBarPanel
                if let existing = panelsByScreenKey[key] {
                    panel = existing
                } else {
                    panel = DockBarPanel(screen: screen)
                    panelsByScreenKey[key] = panel
                }
                panel.update(items: items, on: screen, forceLayout: forceLayout)
                if !panel.isVisible {
                    panel.orderFrontRegardless()
                }
            } else {
                panelsByScreenKey[key]?.orderOut(nil)
            }
        }

        // Limpiar paneles de monitores desconectados
        for (key, panel) in panelsByScreenKey where !activeKeys.contains(key) {
            panel.orderOut(nil)
            panel.close()
            panelsByScreenKey.removeValue(forKey: key)
        }

        lastNativeInsetsSignature = computeNativeInsetsSignature()
    }
}
