import Cocoa

private var passedTests = 0
private var failedTests = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition() {
        passedTests += 1
    } else {
        failedTests += 1
        fputs("FAIL [\(URL(fileURLWithPath: file).lastPathComponent):\(line)] \(message)\n", stderr)
    }
}

private func makeMockItems(tileCount: Int, separatorCount: Int) -> [DockItem] {
    var items: [DockItem] = []
    let dummyIcon = NSImage(size: NSSize(width: 32, height: 32))
    let firstHalf = tileCount / 2
    for i in 0..<firstHalf {
        items.append(DockItem(
            id: "tile-\(i)",
            label: "App \(i)",
            kind: .application(bundleID: "com.example.app\(i)", url: URL(fileURLWithPath: "/Applications/App\(i).app")),
            icon: dummyIcon,
            isRunning: i % 2 == 0,
            isFrontmost: i == 0
        ))
    }
    for s in 0..<separatorCount {
        items.append(DockItem(
            id: "sep-\(s)",
            label: "",
            kind: .separator,
            icon: dummyIcon,
            isRunning: false,
            isFrontmost: false
        ))
    }
    for i in firstHalf..<tileCount {
        items.append(DockItem(
            id: "tile-\(i)",
            label: "App \(i)",
            kind: .application(bundleID: "com.example.app\(i)", url: URL(fileURLWithPath: "/Applications/App\(i).app")),
            icon: dummyIcon,
            isRunning: false,
            isFrontmost: false
        ))
    }
    return items
}

// 1. Regression test: 34 pt spacing threshold overflow (e.g. 1440 pt display, 30 tiles + 2 separators, preferred 44 pt)
func testIconSizingNeverOverflowsDisplay() {
    let reproItems = makeMockItems(tileCount: 30, separatorCount: 2)
    let screenWidth: CGFloat = 1440
    let maxBarWidth = screenWidth * 0.97 // 1396.8 pt
    let chosen = DockLayoutMath.computeEffectiveIconSize(items: reproItems, preferred: 44, maxWidth: maxBarWidth)
    let rendered = DockLayoutMath.barSize(for: reproItems, iconSize: chosen)

    expect(rendered.width <= maxBarWidth,
           "30 tiles + 2 separators on 1440pt screen must fit within \(maxBarWidth)pt (got iconSize=\(chosen), width=\(rendered.width))")
    expect(chosen >= 34 && chosen < 44,
           "Chosen size for 30 tiles on 1440pt should step down cleanly inside >=34 tier (got \(chosen))")

    // Sweep across narrow/wide displays, icon counts, separator counts, and preferred sizes
    for width in [CGFloat(1024), 1280, 1440, 1512, 1728, 1920, 2560, 3840] {
        let limit = width * 0.97
        for tiles in [1, 5, 14, 24, 30, 42] {
            for seps in [0, 1, 2] {
                let list = makeMockItems(tileCount: tiles, separatorCount: seps)
                for pref in [CGFloat(28), 36, 44, 52] {
                    let eff = DockLayoutMath.computeEffectiveIconSize(items: list, preferred: pref, maxWidth: limit)
                    let sz = DockLayoutMath.barSize(for: list, iconSize: eff)
                    if eff > 14 {
                        expect(sz.width <= limit,
                               "Overflow on screenWidth=\(width) tiles=\(tiles) seps=\(seps) pref=\(pref) -> eff=\(eff), barW=\(sz.width) > \(limit)")
                    }
                    expect(eff <= pref, "Effective size \(eff) must never exceed preferred \(pref)")
                }
            }
        }
    }
}

// 2. Regression test: Stationary pointer inside triggerZone must ALWAYS be inside keepAliveZone (no reveal/hide pumping)
func testTriggerZoneStrictlyInsideKeepAliveZone() {
    let screenFrames: [NSRect] = [
        NSRect(x: 0, y: 0, width: 2560, height: 1440),
        NSRect(x: -1920, y: 1440, width: 1920, height: 1080), // Stacked upper display with negative X
        NSRect(x: 513, y: 1080, width: 1512, height: 982),    // Odd X origin Retina scaled
        NSRect(x: 0, y: 0, width: 1080, height: 1920),        // Portrait monitor
        NSRect(x: 2560, y: -420, width: 3840, height: 2160)
    ]

    for frame in screenFrames {
        for barWidth in [CGFloat(120), 340, 680, 1200, frame.width * 0.95] {
            let barSz = NSSize(width: barWidth, height: 52)
            for hasBelow in [false, true] {
                for margin in [CGFloat(0), 6, 12] {
                    let trigger = DockLayoutMath.triggerZone(screenFrame: frame, barSize: barSz, hasScreenBelow: hasBelow)
                    let keepAlive = DockLayoutMath.keepAliveZone(screenFrame: frame, barSize: barSz, bottomMargin: margin)

                    expect(keepAlive.contains(trigger),
                           "keepAlive \(keepAlive) must strictly contain trigger \(trigger) on frame \(frame)")

                    let leftEdgePt = NSPoint(x: trigger.minX + 0.1, y: trigger.minY + trigger.height - 0.1)
                    let rightEdgePt = NSPoint(x: trigger.maxX - 0.1, y: trigger.minY + 0.5)
                    expect(keepAlive.contains(leftEdgePt), "Left wing of trigger must stay inside keepAlive")
                    expect(keepAlive.contains(rightEdgePt), "Right wing of trigger must stay inside keepAlive")
                }
            }
        }
    }
}

// 3. Regression test: Multiple versions of the same app, Cryptex Safari, and Gatekeeper AppTranslocation (B5)
func testAppInstanceMatcherURLPriority() {
    let xcodeStable = URL(fileURLWithPath: "/Applications/Xcode.app")
    let xcodeBeta = URL(fileURLWithPath: "/Applications/Xcode-beta.app")

    // Case A: Both Xcode and Xcode-beta running -> each matches its exact path
    let bothRunning: [(bundleID: String?, bundleURL: URL?)] = [
        ("com.apple.dt.Xcode", xcodeBeta),
        ("com.apple.dt.Xcode", xcodeStable)
    ]
    expect(AppInstanceMatcher.preferredIndex(targetBundleID: "com.apple.dt.Xcode", targetURL: xcodeStable, candidates: bothRunning) == 1,
           "Pinned /Applications/Xcode.app must match index 1, not Xcode-beta at index 0")
    expect(AppInstanceMatcher.preferredIndex(targetBundleID: "com.apple.dt.Xcode", targetURL: xcodeBeta, candidates: bothRunning) == 0,
           "Xcode-beta must match index 0")

    // Case B: Only Xcode-beta is running while /Applications/Xcode.app is pinned -> must NOT hijack Xcode-beta
    let onlyBetaRunning: [(bundleID: String?, bundleURL: URL?)] = [
        ("com.apple.dt.Xcode", xcodeBeta)
    ]
    expect(AppInstanceMatcher.preferredIndex(targetBundleID: "com.apple.dt.Xcode", targetURL: xcodeStable, candidates: onlyBetaRunning) == nil,
           "Pinned /Applications/Xcode.app must not falsely claim running /Applications/Xcode-beta.app")

    // Case C: Safari pinned at /Applications/Safari.app while running from macOS Cryptex /System/Volumes/Preboot/...
    let safariPinned = URL(fileURLWithPath: "/Applications/Safari.app")
    let safariCryptex = URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app")
    let safariCandidates: [(bundleID: String?, bundleURL: URL?)] = [
        ("com.apple.Safari", safariCryptex)
    ]
    expect(AppInstanceMatcher.preferredIndex(targetBundleID: "com.apple.Safari", targetURL: safariPinned, candidates: safariCandidates) == 0,
           "Safari pinned at /Applications/Safari.app must still match Cryptex-mounted Safari.app")

    // Case D: App pinned from ~/Downloads running under Gatekeeper AppTranslocation
    let pinnedDownloaded = URL(fileURLWithPath: "/Users/alice/Downloads/MyTool.app")
    let translocated = URL(fileURLWithPath: "/private/var/folders/zz/abc123/T/AppTranslocation/9F1E-44AA/d/MyTool.app")
    let translocatedCandidates: [(bundleID: String?, bundleURL: URL?)] = [
        ("com.example.mytool", translocated)
    ]
    expect(AppInstanceMatcher.preferredIndex(targetBundleID: "com.example.mytool", targetURL: pinnedDownloaded, candidates: translocatedCandidates) == 0,
           "Translocated app with matching bundleID and bundle name must match its pinned tile")
}

// 4. Regression test (M1): Dock file-data URL parsing for _CFURLStringType = 0 (POSIX) and 15 (file://)
func testDockFileDataURLParsing() {
    let type0Simple: [String: Any] = [
        "_CFURLString": "/Applications/Safari.app",
        "_CFURLStringType": 0
    ]
    let u0 = DockModelReader.parseDockFileURL(from: type0Simple)
    expect(u0?.isFileURL == true && u0?.path == "/Applications/Safari.app",
           "Type 0 POSIX path must produce a valid file:// URL (got \(String(describing: u0)))")

    let type0WithSpaces: [String: Any] = [
        "_CFURLString": "/Applications/Visual Studio Code.app",
        "_CFURLStringType": 0
    ]
    let uSpaces = DockModelReader.parseDockFileURL(from: type0WithSpaces)
    expect(uSpaces?.isFileURL == true && uSpaces?.path == "/Applications/Visual Studio Code.app",
           "Type 0 POSIX path with spaces must produce a valid file:// URL (got \(String(describing: uSpaces)))")

    let type15URL: [String: Any] = [
        "_CFURLString": "file:///Applications/Visual%20Studio%20Code.app/",
        "_CFURLStringType": 15
    ]
    let u15 = DockModelReader.parseDockFileURL(from: type15URL)
    expect(u15?.isFileURL == true && u15?.path == "/Applications/Visual Studio Code.app",
           "Type 15 file:// URL must decode percent-encoding cleanly")

    let webTile: [String: Any] = [
        "_CFURLString": "https://multiscreendock.fgomsan.here.now/",
        "_CFURLStringType": 15
    ]
    expect(DockModelReader.parseDockFileURL(from: webTile) == nil,
           "Non-file URLs must not masquerade as local file tiles")
}

// 5. Regression test (M2): Identical monitors sharing EDID UUID must disambiguate runtime keys by CGDirectDisplayID
func testIdenticalMonitorsRuntimeKeyDisambiguation() {
    let sharedUUID = "uuid:00000000-0000-0000-0000-000000000000"
    let keyA = DockSettings.composeRuntimeScreenKey(persistentKey: sharedUUID, displayID: 3)
    let keyB = DockSettings.composeRuntimeScreenKey(persistentKey: sharedUUID, displayID: 7)
    expect(keyA != keyB, "Two identical displays with the same EDID UUID must receive distinct runtime keys (\(keyA) vs \(keyB))")
    expect(keyA == "\(sharedUUID)#3" && keyB == "\(sharedUUID)#7", "Runtime key format must suffix #displayID")
}

// 6. Regression test (M4): Structural signature ignores running/frontmost dot state and Trash empty/full state
func testStructuralSignatureInPlaceStateChanges() {
    let dummy = NSImage(size: NSSize(width: 32, height: 32))
    let base: [DockItem] = [
        DockItem(id: "finder", label: "Finder", kind: .finder, icon: dummy, isRunning: true, isFrontmost: true),
        DockItem(id: "pinned-safari-0", label: "Safari", kind: .application(bundleID: "com.apple.Safari", url: URL(fileURLWithPath: "/Applications/Safari.app")), icon: dummy, isRunning: true, isFrontmost: false),
        DockItem(id: "sep-others", label: "", kind: .separator, icon: dummy, isRunning: false, isFrontmost: false),
        DockItem(id: "trash", label: "Trash", kind: .trash(isFull: false), icon: dummy, isRunning: false, isFrontmost: false)
    ]
    let activatedSafariAndFilledTrash: [DockItem] = [
        DockItem(id: "finder", label: "Finder", kind: .finder, icon: dummy, isRunning: true, isFrontmost: false),
        DockItem(id: "pinned-safari-0", label: "Safari", kind: .application(bundleID: "com.apple.Safari", url: URL(fileURLWithPath: "/Applications/Safari.app")), icon: dummy, isRunning: true, isFrontmost: true),
        DockItem(id: "sep-others", label: "", kind: .separator, icon: dummy, isRunning: false, isFrontmost: false),
        DockItem(id: "trash", label: "Trash", kind: .trash(isFull: true), icon: dummy, isRunning: false, isFrontmost: false)
    ]
    expect(DockLayoutMath.structuralSignature(for: base) == DockLayoutMath.structuralSignature(for: activatedSafariAndFilledTrash),
           "Focus switch and Trash icon swap must NOT trigger full DockTileView teardown")

    var addedApp = activatedSafariAndFilledTrash
    addedApp.insert(
        DockItem(id: "running-999", label: "Terminal", kind: .application(bundleID: "com.apple.Terminal", url: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")), icon: dummy, isRunning: true, isFrontmost: false),
        at: 2
    )
    expect(DockLayoutMath.structuralSignature(for: base) != DockLayoutMath.structuralSignature(for: addedApp),
           "Adding a new tile MUST change structuralSignature to trigger layout rebuild")
}

// 7. Regression test (B12): Stacked display detection works with negative minY when upper monitor is primary (0,0)
func testStackedDisplayGeometryDetection() {
    let upperPrimary = NSRect(x: 0, y: 0, width: 2560, height: 1440)
    let lowerNegative = NSRect(x: 0, y: -1440, width: 2560, height: 1440)
    let sideOffset = NSRect(x: 2560, y: 700, width: 1920, height: 1080)
    let all = [upperPrimary, lowerNegative, sideOffset]

    expect(DockLayoutMath.hasMonitorDirectlyBelow(targetFrame: upperPrimary, among: all),
           "Upper primary monitor at (0,0) must detect lower monitor at y=-1440")
    expect(DockLayoutMath.hasMonitorDirectlyAbove(targetFrame: lowerNegative, among: all),
           "Lower monitor at y=-1440 must detect upper primary monitor above it")
    expect(!DockLayoutMath.hasMonitorDirectlyBelow(targetFrame: sideOffset, among: all) &&
           !DockLayoutMath.hasMonitorDirectlyAbove(targetFrame: sideOffset, among: all),
           "Side-by-side monitor offset vertically by 700pt without X overlap must NOT be labeled Upper/Lower")
}

// 8. Regression test (B18, B25): Settings bounds clamping in an isolated UserDefaults suite (leaves zero files behind)
func testSettingsBoundsValidationInIsolatedSuite() {
    let suiteName = "io.github.fgomsan.MultiScreenDock.tests.\(UUID().uuidString)"
    guard let suite = UserDefaults(suiteName: suiteName) else {
        expect(false, "Could not create isolated UserDefaults suite")
        return
    }
    defer { suite.removePersistentDomain(forName: suiteName) }

    let settings = DockSettings(defaults: suite)

    suite.set("corrupt", forKey: "iconSize")
    expect((20...80).contains(settings.iconSize), "Corrupt iconSize string must fall back within 20...80 (got \(settings.iconSize))")

    suite.set(0.0, forKey: "iconSize")
    expect((20...80).contains(settings.iconSize), "Zero iconSize must fall back within 20...80")

    settings.iconSize = 500
    expect(settings.iconSize == 80, "iconSize setter must clamp upper bound to 80")

    suite.set(-15.0, forKey: "bottomMargin")
    expect(settings.bottomMargin == 6.0, "Negative bottomMargin must fall back to 6.0")

    settings.bottomMargin = 120
    expect(settings.bottomMargin == 40.0, "bottomMargin setter must clamp to 40.0")
}

// 9. Regression test (B19-B26): Side-effect-free localization & language detection checks
func testLocalizationAndLanguageDetectionSideEffectFree() {
    defer { L10n.overrideLanguageForTesting = nil }

    expect(L10n.detectLanguage(from: ["zh-Hans-CN", "en-US"]) == .zhHans, "zh-Hans-CN must map to .zhHans")
    expect(L10n.detectLanguage(from: ["zh-SG"]) == .zhHans, "zh-SG must map to .zhHans")
    expect(L10n.detectLanguage(from: ["zh-Hant-TW", "en-US"]) == .en, "Traditional Chinese zh-Hant-TW must fall back to English")
    expect(L10n.detectLanguage(from: ["zh-Hant-HK", "es-ES"]) == .es, "zh-Hant-HK followed by es-ES must pick Spanish")

    L10n.overrideLanguageForTesting = .pt
    expect(L10n.showContainerInFinder == "Mostrar na Pasta", "Portuguese enclosing folder mistranslation regression")

    L10n.overrideLanguageForTesting = .ja
    expect(L10n.hideSingle == "隠す", "Japanese Hide verb must match macOS Dock standard 隠す")

    L10n.overrideLanguageForTesting = .zhHans
    expect(L10n.finderLabel == "访达", "Simplified Chinese Finder label must be 访达")

    L10n.overrideLanguageForTesting = .es
    expect(L10n.modeAlwaysVisible.contains("fijo y visible"), "Spanish modeAlwaysVisible grammar check")
    expect(L10n.headerAutoHide(enabledCount: 1, total: 1).hasSuffix("1 pantalla"), "Spanish singular display header")

    L10n.overrideLanguageForTesting = .fr
    let frHeader = L10n.headerAutoHide(enabledCount: 1, total: 2)
    expect(!frHeader.contains("actif sur 1 écran(s) sur"), "French header must not repeat 'sur ... sur'")

    for lang in AppLanguage.allCases where lang != .system {
        L10n.overrideLanguageForTesting = lang
        expect(!L10n.tooltipStatus.isEmpty, "tooltipStatus empty for \(lang)")
        expect(!L10n.finderLabel.isEmpty, "finderLabel empty for \(lang)")
        expect(!L10n.runningAccessibilityState.isEmpty, "runningAccessibilityState empty for \(lang)")
        expect(!L10n.trashLabel.isEmpty, "trashLabel empty for \(lang)")
        expect(!L10n.emptyTrashConfirmTitle.isEmpty, "emptyTrashConfirmTitle empty for \(lang)")
        expect(!L10n.dragCopyErrorTitle.isEmpty, "dragCopyErrorTitle empty for \(lang)")
        expect(!L10n.dockAutohideScriptErrorTitle.isEmpty, "dockAutohideScriptErrorTitle empty for \(lang)")
    }
}

// 10. Regression test: Hidden (⌘H), minimized (⌘M), and closed-window (⌘W) running apps must route through LaunchServices reopen
func testApplicationClickReopenAndHiddenSemantics() {
    let plistURL = URL(fileURLWithPath: "/Applications/Safari.app")
    let translocatedURL = URL(fileURLWithPath: "/private/var/folders/xx/AppTranslocation/ABC/d/Safari.app")

    // Hidden running app clicked -> must unhide first AND reopen via LaunchServices
    let hiddenClick = DockLayoutMath.planApplicationClick(
        plistURL: plistURL,
        runningBundleURL: nil,
        isRunning: true,
        isActive: false,
        isHidden: true,
        modifiers: []
    )
    expect(
        hiddenClick == .reopenAndActivate(url: plistURL, unhideFirst: true, hidesOthers: false),
        "Clicking a hidden running app must unhide first and reopen via LaunchServices"
    )

    // Running app with closed (⌘W) or minimized (⌘M) window -> must still reopen via LaunchServices (even if already active!)
    let activeWindowlessClick = DockLayoutMath.planApplicationClick(
        plistURL: plistURL,
        runningBundleURL: translocatedURL,
        isRunning: true,
        isActive: true,
        isHidden: false,
        modifiers: []
    )
    expect(
        activeWindowlessClick == .reopenAndActivate(url: translocatedURL, unhideFirst: false, hidesOthers: false),
        "Clicking an already-running app must still dispatch reopenAndActivate (using runningBundleURL when present)"
    )

    // Option-click on visible frontmost app -> hides it
    let optActiveClick = DockLayoutMath.planApplicationClick(
        plistURL: plistURL,
        runningBundleURL: nil,
        isRunning: true,
        isActive: true,
        isHidden: false,
        modifiers: [.option]
    )
    expect(optActiveClick == .hideRunningApp, "Option-clicking active visible app must hide it")

    // Option-click on hidden app -> must NOT re-hide; must unhide, reopen, and hide others
    let optHiddenClick = DockLayoutMath.planApplicationClick(
        plistURL: plistURL,
        runningBundleURL: nil,
        isRunning: true,
        isActive: true,
        isHidden: true,
        modifiers: [.option]
    )
    expect(
        optHiddenClick == .reopenAndActivate(url: plistURL, unhideFirst: true, hidesOthers: true),
        "Option-clicking a hidden app must unhide it and hide others"
    )

    // Command-click -> reveals in Finder
    let cmdClick = DockLayoutMath.planApplicationClick(
        plistURL: plistURL,
        runningBundleURL: translocatedURL,
        isRunning: true,
        isActive: false,
        isHidden: false,
        modifiers: [.command]
    )
    expect(cmdClick == .revealInFinder(translocatedURL), "Command-click must reveal running bundle in Finder")
}

@main
struct TestRunner {
    static func main() {
        testIconSizingNeverOverflowsDisplay()
        testTriggerZoneStrictlyInsideKeepAliveZone()
        testAppInstanceMatcherURLPriority()
        testDockFileDataURLParsing()
        testIdenticalMonitorsRuntimeKeyDisambiguation()
        testStructuralSignatureInPlaceStateChanges()
        testStackedDisplayGeometryDetection()
        testSettingsBoundsValidationInIsolatedSuite()
        testLocalizationAndLanguageDetectionSideEffectFree()
        testApplicationClickReopenAndHiddenSemantics()

        print("MultiScreenDock Tests: \(passedTests) passed, \(failedTests) failed.")
        if failedTests > 0 {
            Foundation.exit(1)
        }
    }
}
