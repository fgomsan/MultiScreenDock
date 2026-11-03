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

                    // Sample boundary points along left/right edges of triggerZone
                    let leftEdgePt = NSPoint(x: trigger.minX + 0.1, y: trigger.minY + trigger.height - 0.1)
                    let rightEdgePt = NSPoint(x: trigger.maxX - 0.1, y: trigger.minY + 0.5)
                    expect(keepAlive.contains(leftEdgePt), "Left wing of trigger must stay inside keepAlive")
                    expect(keepAlive.contains(rightEdgePt), "Right wing of trigger must stay inside keepAlive")
                }
            }
        }
    }
}

// 3. Regression test: Multiple versions of the same app (URL-first matching vs Cryptex Safari fallback)
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
}

// 4. Localization completeness across all 8 supported languages
func testLocalizationAllLanguagesNonEmpty() {
    let original = DockSettings.shared.appLanguage
    defer { DockSettings.shared.appLanguage = original }

    for lang in AppLanguage.allCases where lang != .system {
        DockSettings.shared.appLanguage = lang
        expect(!L10n.tooltipStatus.isEmpty, "tooltipStatus empty for \(lang)")
        expect(!L10n.trashLabel.isEmpty, "trashLabel empty for \(lang)")
        expect(!L10n.buyMeACoffee.isEmpty, "buyMeACoffee empty for \(lang)")
        expect(!L10n.dragMoveErrorTitle.isEmpty, "dragMoveErrorTitle empty for \(lang)")
        expect(!L10n.dockAutohidePermTitle.isEmpty, "dockAutohidePermTitle empty for \(lang)")
    }
}

@main
struct TestRunner {
    static func main() {
        testIconSizingNeverOverflowsDisplay()
        testTriggerZoneStrictlyInsideKeepAliveZone()
        testAppInstanceMatcherURLPriority()
        testLocalizationAllLanguagesNonEmpty()

        print("MultiScreenDock Tests: \(passedTests) passed, \(failedTests) failed.")
        if failedTests > 0 {
            Foundation.exit(1)
        }
    }
}
