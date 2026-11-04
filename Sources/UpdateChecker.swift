import Cocoa

final class UpdateChecker {
    static let shared = UpdateChecker()

    static let expectedTeamIdentifier = "G387RJ72S5"
    static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/fgomsan/MultiScreenDock/releases/latest")!
    static let releasesPageURL = URL(string: "https://github.com/fgomsan/MultiScreenDock/releases/latest")!
    static let issuesNewBaseURL = "https://github.com/fgomsan/MultiScreenDock/issues/new"
    static let homebrewUpgradeCommand = "brew update && brew upgrade --cask multiscreendock"

    struct ReleaseInfo: Equatable {
        let version: String
        let tagName: String
        let htmlURL: URL
        let zipDownloadURL: URL?
        let body: String
    }

    private(set) var availableUpdate: ReleaseInfo?
    var onUpdateStateChange: (() -> Void)?

    private var periodicTimer: Timer?
    private var isChecking = false
    private var isInstalling = false

    var currentAppVersion: String {
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return "1.3.5"
    }

    // MARK: - Pure Testable Helpers

    static func parseVersionComponents(_ raw: String) -> (numbers: [Int], isPrerelease: Bool) {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("v") || cleaned.hasPrefix("V") {
            cleaned.removeFirst()
        }
        if let plusIdx = cleaned.firstIndex(of: "+") {
            cleaned = String(cleaned[..<plusIdx])
        }
        var isPrerelease = false
        if let dashIdx = cleaned.firstIndex(of: "-") {
            isPrerelease = true
            cleaned = String(cleaned[..<dashIdx])
        }
        var nums = cleaned.split(separator: ".").map { Int($0) ?? 0 }
        while nums.count > 1 && nums.last == 0 {
            nums.removeLast()
        }
        return (nums.isEmpty ? [0] : nums, isPrerelease)
    }

    static func isVersion(_ remote: String, newerThan local: String) -> Bool {
        let r = parseVersionComponents(remote)
        let l = parseVersionComponents(local)
        let maxCount = max(r.numbers.count, l.numbers.count)
        for i in 0..<maxCount {
            let rv = i < r.numbers.count ? r.numbers[i] : 0
            let lv = i < l.numbers.count ? l.numbers[i] : 0
            if rv != lv {
                return rv > lv
            }
        }
        if !r.isPrerelease && l.isPrerelease {
            return true
        }
        return false
    }

    static func buildFeedbackIssueURL(
        appVersion: String,
        osVersion: String,
        screenCount: Int,
        mode: String
    ) -> URL {
        var components = URLComponents(string: issuesNewBaseURL)
        let template = """
        <!-- Describe your suggestion or bug report here / Describe aquí tu sugerencia o fallo -->


        ---
        **Environment**
        - MultiScreenDock: v\(appVersion)
        - macOS: \(osVersion)
        - Connected displays: \(screenCount) (\(mode))
        """
        components?.queryItems = [
            URLQueryItem(name: "body", value: template)
        ]
        return components?.url ?? URL(string: issuesNewBaseURL)!
    }

    // MARK: - User Actions & Lifecycle

    func openFeedbackIssuePage() {
        let url = Self.buildFeedbackIssueURL(
            appVersion: currentAppVersion,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            screenCount: NSScreen.screens.count,
            mode: DockSettings.shared.visibilityMode.rawValue
        )
        NSWorkspace.shared.open(url)
    }

    func startAutomaticChecksIfEnabled() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        periodicTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.performAutomaticCheckIfDue()
        }
        timer.tolerance = 300
        periodicTimer = timer

        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            self?.performAutomaticCheckIfDue()
        }
    }

    private func performAutomaticCheckIfDue() {
        guard DockSettings.shared.autoCheckUpdates else { return }
        let elapsed = Date().timeIntervalSince1970 - DockSettings.shared.lastUpdateCheckTimestamp
        guard elapsed >= 86_400 else { return }
        checkNow(userInitiated: false)
    }

    func presentAvailableUpdateOrCheck() {
        if let release = availableUpdate {
            presentUpdateAlert(for: release)
        } else {
            checkNow(userInitiated: true)
        }
    }

    func checkNow(userInitiated: Bool) {
        if isChecking && !userInitiated {
            return
        }
        isChecking = true

        var request = URLRequest(
            url: Self.latestReleaseAPIURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MultiScreenDock/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isChecking = false

                if let error = error {
                    if userInitiated {
                        self.presentCheckErrorAlert(detail: error.localizedDescription)
                    }
                    return
                }

                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard statusCode == 200,
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    if userInitiated {
                        self.presentCheckErrorAlert(detail: "HTTP \(statusCode)")
                    }
                    return
                }

                DockSettings.shared.lastUpdateCheckTimestamp = Date().timeIntervalSince1970

                let isDraft = (json["draft"] as? Bool) ?? false
                let isPrerelease = (json["prerelease"] as? Bool) ?? false
                let htmlURLString = (json["html_url"] as? String) ?? Self.releasesPageURL.absoluteString
                let htmlURL = URL(string: htmlURLString) ?? Self.releasesPageURL
                let body = (json["body"] as? String) ?? ""

                var zipURL: URL?
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String,
                           name.lowercased().hasSuffix(".zip"),
                           let dlStr = asset["browser_download_url"] as? String,
                           let parsed = URL(string: dlStr),
                           parsed.scheme?.lowercased() == "https" {
                            zipURL = parsed
                            break
                        }
                    }
                }

                var cleanVersion = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanVersion.hasPrefix("v") || cleanVersion.hasPrefix("V") {
                    cleanVersion.removeFirst()
                }

                if !isDraft && !isPrerelease && Self.isVersion(cleanVersion, newerThan: self.currentAppVersion) {
                    let info = ReleaseInfo(
                        version: cleanVersion,
                        tagName: tagName,
                        htmlURL: htmlURL,
                        zipDownloadURL: zipURL,
                        body: body
                    )
                    self.availableUpdate = info
                    self.onUpdateStateChange?()
                    if userInitiated {
                        self.presentUpdateAlert(for: info)
                    }
                } else {
                    if self.availableUpdate != nil {
                        self.availableUpdate = nil
                        self.onUpdateStateChange?()
                    }
                    if userInitiated {
                        self.presentUpToDateAlert()
                    }
                }
            }
        }.resume()
    }

    // MARK: - Native Dialogs

    private func presentUpToDateAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.upToDateTitle
        alert.informativeText = L10n.upToDateMessage(currentAppVersion)
        alert.addButton(withTitle: L10n.okBtn)
        alert.runModal()
    }

    private func presentCheckErrorAlert(detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.updateCheckErrorTitle
        alert.informativeText = detail
        alert.addButton(withTitle: L10n.updateViewOnGitHubBrewBtn)
        alert.addButton(withTitle: L10n.cancelBtn)
        if alert.runModal() == .alertFirstButtonReturn {
            copyHomebrewCommandToPasteboard()
            NSWorkspace.shared.open(Self.releasesPageURL)
        }
    }

    func presentUpdateAlert(for release: ReleaseInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.updateAvailableTitle(release.version)

        let trimmedNotes = release.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt: String
        if trimmedNotes.count > 520 {
            excerpt = String(trimmedNotes.prefix(520)) + "…"
        } else {
            excerpt = trimmedNotes
        }

        if excerpt.isEmpty {
            alert.informativeText = L10n.updateCurrentVersionNote(currentAppVersion)
        } else {
            alert.informativeText = "\(L10n.updateCurrentVersionNote(currentAppVersion))\n\n\(excerpt)"
        }

        let canSelfInstall = (release.zipDownloadURL != nil && Bundle.main.bundleURL.pathExtension == "app")
        if canSelfInstall {
            alert.addButton(withTitle: L10n.updateInstallAndRelaunchBtn)
            alert.addButton(withTitle: L10n.updateViewOnGitHubBrewBtn)
            alert.addButton(withTitle: L10n.updateLaterBtn)

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                downloadVerifyAndInstall(release)
            } else if response == .alertSecondButtonReturn {
                copyHomebrewCommandToPasteboard()
                NSWorkspace.shared.open(release.htmlURL)
            }
        } else {
            alert.addButton(withTitle: L10n.updateViewOnGitHubBrewBtn)
            alert.addButton(withTitle: L10n.updateLaterBtn)
            if alert.runModal() == .alertFirstButtonReturn {
                copyHomebrewCommandToPasteboard()
                NSWorkspace.shared.open(release.htmlURL)
            }
        }
    }

    private func copyHomebrewCommandToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(Self.homebrewUpgradeCommand, forType: .string)
    }

    // MARK: - Verified Self-Update Installer

    private enum InstallError: LocalizedError {
        case missingDownloadURL
        case invalidArchive
        case signatureVerificationFailed(String)
        case untrustedSigningIdentity
        case nonWritableInstallLocation

        var errorDescription: String? {
            switch self {
            case .missingDownloadURL:
                return "Missing release archive URL."
            case .invalidArchive:
                return "Release archive did not contain MultiScreenDock.app."
            case .signatureVerificationFailed(let msg):
                return "Code signature verification failed (\(msg))."
            case .untrustedSigningIdentity:
                return "Bundle identifier or Apple Developer Team ID did not match G387RJ72S5."
            case .nonWritableInstallLocation:
                return "Application folder is not writable by the current user."
            }
        }
    }

    private func downloadVerifyAndInstall(_ release: ReleaseInfo) {
        guard !isInstalling else { return }
        guard let zipURL = release.zipDownloadURL, zipURL.scheme?.lowercased() == "https" else {
            fallbackToManualRelease(release, errorDetail: InstallError.missingDownloadURL.localizedDescription)
            return
        }

        isInstalling = true
        let fm = FileManager.default
        let stagingRoot = fm.temporaryDirectory.appendingPathComponent(
            "MultiScreenDockUpdate-\(UUID().uuidString)",
            isDirectory: true
        )

        URLSession.shared.downloadTask(with: zipURL) { [weak self] tempFileURL, response, error in
            guard let self = self else { return }

            if let error = error {
                try? fm.removeItem(at: stagingRoot)
                DispatchQueue.main.async {
                    self.isInstalling = false
                    self.fallbackToManualRelease(release, errorDetail: error.localizedDescription)
                }
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard statusCode == 200, let tempFileURL = tempFileURL else {
                try? fm.removeItem(at: stagingRoot)
                DispatchQueue.main.async {
                    self.isInstalling = false
                    self.fallbackToManualRelease(release, errorDetail: "HTTP \(statusCode)")
                }
                return
            }

            let archivePath = stagingRoot.appendingPathComponent("update.zip")
            let extractDir = stagingRoot.appendingPathComponent("extracted", isDirectory: true)
            do {
                try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
                try fm.moveItem(at: tempFileURL, to: archivePath)
            } catch {
                try? fm.removeItem(at: stagingRoot)
                DispatchQueue.main.async {
                    self.isInstalling = false
                    self.fallbackToManualRelease(release, errorDetail: error.localizedDescription)
                }
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try Self.extractVerifyAndReplaceApp(
                        archiveURL: archivePath,
                        extractDir: extractDir,
                        targetAppURL: Bundle.main.bundleURL
                    )
                    try? fm.removeItem(at: stagingRoot)

                    DispatchQueue.main.async {
                        Self.relaunchReplacedAppAndExit(at: Bundle.main.bundleURL)
                    }
                } catch {
                    try? fm.removeItem(at: stagingRoot)
                    DispatchQueue.main.async {
                        self.isInstalling = false
                        self.fallbackToManualRelease(release, errorDetail: error.localizedDescription)
                    }
                }
            }
        }.resume()
    }

    private static func extractVerifyAndReplaceApp(
        archiveURL: URL,
        extractDir: URL,
        targetAppURL: URL
    ) throws {
        let fm = FileManager.default
        let parentDir = targetAppURL.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parentDir.path) else {
            throw InstallError.nonWritableInstallLocation
        }

        let dittoResult = try runProcess(
            executable: "/usr/bin/ditto",
            arguments: ["-x", "-k", archiveURL.path, extractDir.path]
        )
        guard dittoResult.exitCode == 0 else {
            throw InstallError.invalidArchive
        }

        let extractedAppURL = extractDir.appendingPathComponent("MultiScreenDock.app", isDirectory: true)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: extractedAppURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw InstallError.invalidArchive
        }

        let resourceValues = try extractedAppURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        if resourceValues.isSymbolicLink == true {
            throw InstallError.invalidArchive
        }

        // 1. Strict deep code-signature integrity check
        let verifyResult = try runProcess(
            executable: "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", extractedAppURL.path]
        )
        guard verifyResult.exitCode == 0 else {
            throw InstallError.signatureVerificationFailed(verifyResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // 2. Pin exact Bundle Identifier and Apple Developer TeamIdentifier (G387RJ72S5)
        let infoResult = try runProcess(
            executable: "/usr/bin/codesign",
            arguments: ["-dv", "--verbose=2", extractedAppURL.path]
        )
        let meta = infoResult.stderr
        guard meta.contains("Identifier=\(DockSettings.bundleIdentifier)"),
              meta.contains("TeamIdentifier=\(expectedTeamIdentifier)") else {
            throw InstallError.untrustedSigningIdentity
        }

        let plistURL = extractedAppURL.appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: plistURL),
              (plist["CFBundleIdentifier"] as? String) == DockSettings.bundleIdentifier else {
            throw InstallError.untrustedSigningIdentity
        }

        // 3. Atomic swap of the .app bundle
        _ = try fm.replaceItemAt(
            targetAppURL,
            withItemAt: extractedAppURL,
            backupItemName: nil,
            options: []
        )
    }

    private static func runProcess(
        executable: String,
        arguments: [String]
    ) throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        try proc.run()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return (
            proc.terminationStatus,
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? ""
        )
    }

    private static func relaunchReplacedAppAndExit(at appURL: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
        launcher.arguments = [
            "-c",
            "i=0; while kill -0 \"$1\" 2>/dev/null && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done; /usr/bin/open \"$2\"",
            "--",
            "\(pid)",
            appURL.path
        ]
        try? launcher.run()
        NSApp.terminate(nil)
    }

    private func fallbackToManualRelease(_ release: ReleaseInfo, errorDetail: String) {
        copyHomebrewCommandToPasteboard()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.updateInstallErrorTitle
        alert.informativeText = "\(L10n.updateInstallFallbackMessage)\n\n(\(errorDetail))"
        alert.addButton(withTitle: L10n.okBtn)
        alert.runModal()
        NSWorkspace.shared.open(release.htmlURL)
    }
}
