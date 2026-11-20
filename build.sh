#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MultiScreenDock"
FINAL_APP_BUNDLE="${PROJECT_DIR}/${APP_NAME}.app"
MAS_BUILD=false
if [[ "${1:-}" == "--mas" ]]; then
    MAS_BUILD=true
fi
BUILD_TMP="$(mktemp -d "${TMPDIR:-/tmp}/multiscreendock_build.XXXXXX")"
trap 'rm -rf "${BUILD_TMP}"' EXIT

APP_BUNDLE="${BUILD_TMP}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

echo "1/3 Generating app icon..."
ICONSET_DIR="${BUILD_TMP}/AppIcon.iconset"
mkdir -p "${ICONSET_DIR}"

swift - "${ICONSET_DIR}" << 'EOF'
import Cocoa

let outDir = CommandLine.arguments[1]
let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, px) in sizes {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    let s = CGFloat(px)
    let inset = s * 0.082
    let bgRect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let cornerR = bgRect.width * 0.225
    let squircle = NSBezierPath(roundedRect: bgRect, xRadius: cornerR, yRadius: cornerR)

    cg.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.38)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.022)
    shadow.shadowBlurRadius = s * 0.045
    shadow.set()
    NSColor(calibratedRed: 0.05, green: 0.14, blue: 0.35, alpha: 1.0).setFill()
    squircle.fill()
    cg.restoreGState()

    cg.saveGState()
    squircle.addClip()

    let bgGrad = NSGradient(colorsAndLocations:
        (NSColor(calibratedRed: 0.14, green: 0.56, blue: 0.98, alpha: 1.0), 0.0),
        (NSColor(calibratedRed: 0.07, green: 0.32, blue: 0.78, alpha: 1.0), 0.45),
        (NSColor(calibratedRed: 0.04, green: 0.14, blue: 0.42, alpha: 1.0), 1.0)
    )!
    bgGrad.draw(in: bgRect, angle: -75)

    let auraRect = NSRect(x: bgRect.minX - s * 0.10, y: bgRect.midY - s * 0.05, width: bgRect.width + s * 0.20, height: bgRect.height * 0.85)
    let auraPath = NSBezierPath(ovalIn: auraRect)
    let auraGrad = NSGradient(colors: [
        NSColor(calibratedRed: 0.38, green: 0.86, blue: 1.0, alpha: 0.42),
        NSColor(calibratedRed: 0.20, green: 0.50, blue: 0.98, alpha: 0.0)
    ])!
    auraGrad.draw(in: auraPath, relativeCenterPosition: .zero)

    func drawAppleDisplay(_ rect: NSRect, isPrimaryHero: Bool, dotColors: [NSColor]) {
        let bezelR = rect.height * 0.13
        let outerPath = NSBezierPath(roundedRect: rect, xRadius: bezelR, yRadius: bezelR)

        cg.saveGState()
        let scrShadow = NSShadow()
        scrShadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: isPrimaryHero ? 0.50 : 0.38)
        scrShadow.shadowOffset = NSSize(width: 0, height: -s * 0.014)
        scrShadow.shadowBlurRadius = s * 0.028
        scrShadow.set()
        NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.18, alpha: 0.96).setFill()
        outerPath.fill()
        cg.restoreGState()

        let bezelGrad = NSGradient(colors: [
            NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.29, alpha: 0.98),
            NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.15, alpha: 0.98)
        ])!
        bezelGrad.draw(in: outerPath, angle: -90)

        let bezelThick = max(0.8, s * 0.011)
        let innerRect = rect.insetBy(dx: bezelThick, dy: bezelThick)
        let innerR = max(1.0, bezelR - bezelThick * 0.7)
        let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: innerR, yRadius: innerR)

        let wpGrad = NSGradient(colorsAndLocations:
            (NSColor(calibratedRed: 0.28, green: 0.78, blue: 0.99, alpha: 1.0), 0.0),
            (NSColor(calibratedRed: 0.15, green: 0.45, blue: 0.92, alpha: 1.0), 0.52),
            (NSColor(calibratedRed: 0.22, green: 0.18, blue: 0.62, alpha: 1.0), 1.0)
        )!
        wpGrad.draw(in: innerPath, angle: -65)

        cg.saveGState()
        innerPath.addClip()
        let menuH = innerRect.height * 0.085
        let menuRect = NSRect(x: innerRect.minX, y: innerRect.maxY - menuH, width: innerRect.width, height: menuH)
        NSColor.white.withAlphaComponent(0.18).setFill()
        menuRect.fill()

        let glossPath = NSBezierPath()
        glossPath.move(to: NSPoint(x: innerRect.minX, y: innerRect.maxY))
        glossPath.line(to: NSPoint(x: innerRect.minX + innerRect.width * 0.58, y: innerRect.maxY))
        glossPath.line(to: NSPoint(x: innerRect.minX + innerRect.width * 0.22, y: innerRect.minY))
        glossPath.line(to: NSPoint(x: innerRect.minX, y: innerRect.minY))
        glossPath.close()
        NSColor.white.withAlphaComponent(0.08).setFill()
        glossPath.fill()

        let dockW = innerRect.width * 0.78
        let dockH = max(2.0, innerRect.height * 0.24)
        let dockY = innerRect.minY + innerRect.height * 0.075
        let dockRect = NSRect(x: innerRect.midX - dockW / 2, y: dockY, width: dockW, height: dockH)
        let dockR = dockH * 0.42
        let dockPath = NSBezierPath(roundedRect: dockRect, xRadius: dockR, yRadius: dockR)

        let dockGrad = NSGradient(colors: [
            NSColor(calibratedWhite: 1.0, alpha: 0.48),
            NSColor(calibratedRed: 0.78, green: 0.92, blue: 1.0, alpha: 0.28)
        ])!
        dockGrad.draw(in: dockPath, angle: -90)
        NSColor.white.withAlphaComponent(0.72).setStroke()
        dockPath.lineWidth = max(0.5, s * 0.003)
        dockPath.stroke()

        let count = dotColors.count
        let padX = dockRect.width * 0.08
        let usableW = dockRect.width - padX * 2
        let slotW = usableW / CGFloat(count)
        let iconSz = min(dockH * 0.66, slotW * 0.76)
        let iconY = dockRect.midY - iconSz * 0.44

        for (i, c) in dotColors.enumerated() {
            let cx = dockRect.minX + padX + slotW * (CGFloat(i) + 0.5)
            let iRect = NSRect(x: cx - iconSz / 2, y: iconY, width: iconSz, height: iconSz)
            let iPath = NSBezierPath(roundedRect: iRect, xRadius: iconSz * 0.24, yRadius: iconSz * 0.24)
            c.setFill()
            iPath.fill()
            if px >= 64 {
                NSColor.white.withAlphaComponent(0.55).setStroke()
                iPath.lineWidth = max(0.4, s * 0.0018)
                iPath.stroke()
            }
            if px >= 128 && (i == 0 || i == 1 || i == count - 2) {
                let dotD = max(1.0, s * 0.0045)
                let dotRect = NSRect(x: cx - dotD / 2, y: dockRect.minY + dockH * 0.06, width: dotD, height: dotD)
                NSColor.white.withAlphaComponent(0.95).setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
        }
        cg.restoreGState()

        outerPath.lineWidth = max(0.8, s * 0.0055)
        NSColor(calibratedRed: 0.70, green: 0.88, blue: 1.0, alpha: isPrimaryHero ? 0.92 : 0.68).setStroke()
        outerPath.stroke()
    }

    let tilePalette: [NSColor] = [
        NSColor(calibratedRed: 0.16, green: 0.68, blue: 1.0, alpha: 1.0),
        NSColor(calibratedRed: 0.15, green: 0.82, blue: 0.98, alpha: 1.0),
        NSColor(calibratedRed: 1.0, green: 0.76, blue: 0.18, alpha: 1.0),
        NSColor(calibratedRed: 0.98, green: 0.26, blue: 0.42, alpha: 1.0),
        NSColor(calibratedRed: 0.22, green: 0.84, blue: 0.48, alpha: 1.0)
    ]

    let topW = s * 0.345
    let topH = s * 0.235
    let topY = s * 0.535
    drawAppleDisplay(NSRect(x: s * 0.145, y: topY, width: topW, height: topH), isPrimaryHero: true, dotColors: tilePalette)
    drawAppleDisplay(NSRect(x: s * 0.510, y: topY, width: topW, height: topH), isPrimaryHero: true, dotColors: tilePalette)

    let sideW = s * 0.225
    let sideH = s * 0.190
    let sideY = s * 0.240
    drawAppleDisplay(NSRect(x: s * 0.125, y: sideY, width: sideW, height: sideH), isPrimaryHero: false, dotColors: Array(tilePalette.prefix(4)))
    drawAppleDisplay(NSRect(x: s * 0.650, y: sideY, width: sideW, height: sideH), isPrimaryHero: false, dotColors: Array(tilePalette.prefix(4)))

    let centerW = s * 0.265
    let centerH = s * 0.210
    let centerY = s * 0.235
    let baseRect = NSRect(x: s * 0.50 - centerW * 0.56, y: centerY - s * 0.016, width: centerW * 1.12, height: s * 0.018)
    let basePath = NSBezierPath(roundedRect: baseRect, xRadius: s * 0.008, yRadius: s * 0.008)
    NSColor(calibratedRed: 0.65, green: 0.78, blue: 0.95, alpha: 0.65).setFill()
    basePath.fill()
    drawAppleDisplay(NSRect(x: s * 0.50 - centerW / 2, y: centerY, width: centerW, height: centerH), isPrimaryHero: true, dotColors: tilePalette)

    cg.restoreGState()

    squircle.lineWidth = max(0.8, s * 0.007)
    NSColor.white.withAlphaComponent(0.38).setStroke()
    squircle.stroke()

    NSGraphicsContext.restoreGraphicsState()

    if let png = rep.representation(using: .png, properties: [:]) {
        try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    }
}
EOF

iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/AppIcon.icns"

echo "2/3 Creating Info.plist..."
cat > "${CONTENTS_DIR}/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>es</string>
        <string>fr</string>
        <string>de</string>
        <string>pt</string>
        <string>it</string>
        <string>ja</string>
        <string>zh-Hans</string>
    </array>
    <key>CFBundleDisplayName</key>
    <string>MultiScreenDock</string>
    <key>CFBundleExecutable</key>
    <string>MultiScreenDock</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.fgomsan.MultiScreenDock</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MultiScreenDock</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.5.0</string>
    <key>CFBundleVersion</key>
    <string>16</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>
    <key>NSAppleEventsUsageDescription</key>
    <string>MultiScreenDock uses System Events to open Finder windows, empty the Trash, or toggle Apple's native Dock auto-hide when requested.</string>
</dict>
</plist>
EOF

echo "3/3 Compiling Universal macOS binary (arm64 + x86_64)..."
SOURCES=(
    "${PROJECT_DIR}/Sources/L10n.swift"
    "${PROJECT_DIR}/Sources/Settings.swift"
    "${PROJECT_DIR}/Sources/UpdateChecker.swift"
    "${PROJECT_DIR}/Sources/Models.swift"
    "${PROJECT_DIR}/Sources/FolderStackPanel.swift"
    "${PROJECT_DIR}/Sources/DockPanelView.swift"
    "${PROJECT_DIR}/Sources/MultiScreenController.swift"
    "${PROJECT_DIR}/Sources/AppDelegate.swift"
    "${PROJECT_DIR}/Sources/main.swift"
)

FRAMEWORKS=(-framework Cocoa -framework QuartzCore -framework ColorSync -framework ServiceManagement -framework QuickLookThumbnailing)
SWIFT_FLAGS=()
if [[ "${MAS_BUILD}" == "true" ]]; then
    echo "   (Mac App Store build mode: -DAPP_STORE + App Sandbox entitlements)"
    SWIFT_FLAGS+=(-DAPP_STORE)
fi

swiftc -O "${SWIFT_FLAGS[@]}" -target arm64-apple-macos13.0 "${FRAMEWORKS[@]}" "${SOURCES[@]}" -o "${BUILD_TMP}/${APP_NAME}-arm64"
swiftc -O "${SWIFT_FLAGS[@]}" -target x86_64-apple-macos13.0 -Xlinker -w "${FRAMEWORKS[@]}" "${SOURCES[@]}" -o "${BUILD_TMP}/${APP_NAME}-x86_64"
lipo -create -output "${MACOS_DIR}/${APP_NAME}" "${BUILD_TMP}/${APP_NAME}-arm64" "${BUILD_TMP}/${APP_NAME}-x86_64"

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
if [[ "${MAS_BUILD}" == "true" ]]; then
    PROVISION_PROFILE="${PROJECT_DIR}/packaging/mas/embedded.provisionprofile"
    if [[ -f "${PROVISION_PROFILE}" ]]; then
        cp "${PROVISION_PROFILE}" "${CONTENTS_DIR}/embedded.provisionprofile"
    fi
    xattr -cr "${APP_BUNDLE}"
    ENTITLEMENTS_PATH="${PROJECT_DIR}/packaging/mas/MultiScreenDock-MAS.entitlements"
    codesign --force --deep --entitlements "${ENTITLEMENTS_PATH}" --sign "${CODESIGN_IDENTITY}" "${APP_BUNDLE}"
    codesign --verify --deep --strict "${APP_BUNDLE}"
else
    xattr -cr "${APP_BUNDLE}"
    codesign --force --deep --sign "${CODESIGN_IDENTITY}" "${APP_BUNDLE}"
fi

if [[ "${MAS_BUILD}" == "true" && -n "${MAS_INSTALLER_IDENTITY:-}" ]]; then
    PKG_PATH="${PROJECT_DIR}/${APP_NAME}-MAS.pkg"
    rm -f "${PKG_PATH}"
    productbuild --component "${APP_BUNDLE}" /Applications --sign "${MAS_INSTALLER_IDENTITY}" "${PKG_PATH}"
    echo "Mac App Store package ready: ${PKG_PATH}"
fi

rm -rf "${FINAL_APP_BUNDLE}"
ditto --norsrc "${APP_BUNDLE}" "${FINAL_APP_BUNDLE}"
xattr -cr "${FINAL_APP_BUNDLE}"

echo "Build complete: ${FINAL_APP_BUNDLE}"
