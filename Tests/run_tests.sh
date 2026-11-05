#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_BIN="$(mktemp "${TMPDIR:-/tmp}/msd_tests.XXXXXX")"
trap 'rm -f "${TMP_BIN}"' EXIT

swiftc -O -parse-as-library \
    -framework Cocoa -framework QuartzCore -framework ColorSync -framework ServiceManagement -framework QuickLookThumbnailing \
    "${PROJECT_DIR}/Sources/L10n.swift" \
    "${PROJECT_DIR}/Sources/Settings.swift" \
    "${PROJECT_DIR}/Sources/UpdateChecker.swift" \
    "${PROJECT_DIR}/Sources/Models.swift" \
    "${PROJECT_DIR}/Sources/FolderStackPanel.swift" \
    "${PROJECT_DIR}/Sources/DockPanelView.swift" \
    "${PROJECT_DIR}/Sources/MultiScreenController.swift" \
    "${PROJECT_DIR}/Sources/AppDelegate.swift" \
    "${PROJECT_DIR}/Tests/run_tests.swift" \
    -o "${TMP_BIN}"

"${TMP_BIN}"
