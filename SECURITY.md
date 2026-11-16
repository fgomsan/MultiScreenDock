# Security Policy

## Supported Versions

Only the latest release of **MultiScreenDock** receives security updates.

| Version | Supported          |
| ------- | ------------------ |
| 1.4.x   | :white_check_mark: |
| < 1.4.0 | :x:                |

## Security Architecture

- **Zero Elevated Permissions:** MultiScreenDock runs entirely in user space using standard public macOS `AppKit` (`NSWorkspace`, `NSScreen`, `NSPanel`) and `CoreGraphics` (`CGWindowListCopyWindowInfo`) APIs. It does **not** require Accessibility, Screen Recording, Input Monitoring, or Full Disk Access permissions.
- **Zero Network Access:** MultiScreenDock makes no network requests, includes no analytics or telemetry SDKs, and collects zero user data.
- **Code Signing & Notarization:** Official release binaries are signed with an Apple Developer ID Application certificate (`494Z3H5Z5Q`) with Hardened Runtime enabled and notarized by Apple.

## Reporting a Vulnerability

If you discover a security vulnerability in MultiScreenDock, please report it privately via [GitHub Security Advisories](https://github.com/fgomsan/MultiScreenDock/security/advisories/new) or by opening a minimal issue without exploit details so we can coordinate a fix and release a patched notarized build promptly.
