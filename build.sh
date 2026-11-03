#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MultiScreenDock"
FINAL_APP_BUNDLE="${PROJECT_DIR}/${APP_NAME}.app"
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
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(px)
    let inset = s * 0.08
    let bgRect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: bgRect, xRadius: s * 0.22, yRadius: s * 0.22)

    let grad = NSGradient(colors: [
        NSColor(calibratedRed: 0.09, green: 0.34, blue: 0.78, alpha: 1.0),
        NSColor(calibratedRed: 0.05, green: 0.14, blue: 0.38, alpha: 1.0)
    ])!
    grad.draw(in: path, angle: -90)

    let lineW = max(1.0, s * 0.018)

    func drawMiniScreen(_ rect: NSRect) {
        let sp = NSBezierPath(roundedRect: rect, xRadius: s * 0.035, yRadius: s * 0.035)
        sp.lineWidth = lineW
        NSColor.white.withAlphaComponent(0.16).setFill()
        sp.fill()
        NSColor.white.withAlphaComponent(0.75).setStroke()
        sp.stroke()

        let dw = rect.width * 0.62
        let dh = max(2.0, rect.height * 0.16)
        let dRect = NSRect(x: rect.midX - dw / 2, y: rect.minY + rect.height * 0.10, width: dw, height: dh)
        let dp = NSBezierPath(roundedRect: dRect, xRadius: dh / 2, yRadius: dh / 2)
        NSColor(calibratedRed: 0.45, green: 0.86, blue: 1.0, alpha: 0.98).setFill()
        dp.fill()
    }

    // Upper row (2 displays)
    let topW = s * 0.31
    let topH = s * 0.22
    let topY = s * 0.53
    drawMiniScreen(NSRect(x: s * 0.17, y: topY, width: topW, height: topH))
    drawMiniScreen(NSRect(x: s * 0.52, y: topY, width: topW, height: topH))

    // Lower row (3 displays)
    let botW = s * 0.22
    let botH = s * 0.19
    let botY = s * 0.25
    drawMiniScreen(NSRect(x: s * 0.14, y: botY, width: botW, height: botH))
    drawMiniScreen(NSRect(x: s * 0.39, y: botY, width: botW, height: botH))
    drawMiniScreen(NSRect(x: s * 0.64, y: botY, width: botW, height: botH))

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
    <string>1.3.3</string>
    <key>CFBundleVersion</key>
    <string>7</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>MultiScreenDock uses System Events to open Finder windows, empty the Trash, or toggle Apple's native Dock auto-hide when requested.</string>
</dict>
</plist>
EOF

echo "3/3 Compiling Universal macOS binary (arm64 + x86_64)..."
SOURCES=(
    "${PROJECT_DIR}/Sources/L10n.swift"
    "${PROJECT_DIR}/Sources/Settings.swift"
    "${PROJECT_DIR}/Sources/Models.swift"
    "${PROJECT_DIR}/Sources/DockPanelView.swift"
    "${PROJECT_DIR}/Sources/MultiScreenController.swift"
    "${PROJECT_DIR}/Sources/AppDelegate.swift"
    "${PROJECT_DIR}/Sources/main.swift"
)

FRAMEWORKS=(-framework Cocoa -framework QuartzCore -framework ColorSync -framework ServiceManagement)

swiftc -O -target arm64-apple-macos13.0 "${FRAMEWORKS[@]}" "${SOURCES[@]}" -o "${BUILD_TMP}/${APP_NAME}-arm64"
swiftc -O -target x86_64-apple-macos13.0 -Xlinker -w "${FRAMEWORKS[@]}" "${SOURCES[@]}" -o "${BUILD_TMP}/${APP_NAME}-x86_64"
lipo -create -output "${MACOS_DIR}/${APP_NAME}" "${BUILD_TMP}/${APP_NAME}-arm64" "${BUILD_TMP}/${APP_NAME}-x86_64"

xattr -cr "${APP_BUNDLE}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
codesign --force --deep --sign "${CODESIGN_IDENTITY}" "${APP_BUNDLE}"

rm -rf "${FINAL_APP_BUNDLE}"
ditto "${APP_BUNDLE}" "${FINAL_APP_BUNDLE}"

echo "Build complete: ${FINAL_APP_BUNDLE}"
