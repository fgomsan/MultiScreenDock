# MultiScreenDock

[![Build macOS Universal App](https://github.com/fgomsan/MultiScreenDock/actions/workflows/build.yml/badge.svg)](https://github.com/fgomsan/MultiScreenDock/actions/workflows/build.yml)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B%20(Universal)-blue)](#installation)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**MultiScreenDock** is a lightweight, zero-dependency, native Swift/AppKit utility that keeps a live, synchronized macOS Dock **simultaneously visible across all connected monitors** — including vertically stacked upper displays where Apple's native Dock can never be summoned.

---

## Why does this exist?

macOS has two hard limitations when working with multiple monitors (2, 3, 5+ displays):

1. **Single-instance Dock:** Apple only renders the Dock on **one display at a time**, forcing you to push your cursor against a screen's bottom edge and wait for it to jump.
2. **Stacked displays dead-zone:** If you stack monitors in two rows (e.g. two ultrawide/4K displays above three lower displays), the bottom edge of the upper monitors borders the lower displays. Because your mouse cursor crosses into the lower monitors instead of hitting a physical boundary, **Apple's native Dock can never appear on the upper displays at all.**

```
┌───────────────────────┬───────────────────────┐
│   Upper Display 1     │   Upper Display 2     │
│     [════Dock════]    │     [════Dock════]    │  ◄── Native macOS Dock can NEVER reach here
├───────────────┬───────┴───────┬───────────────┤
│ Lower Left    │  Main / Mac   │ Lower Right   │
│  [═══Dock═══] │  [═══Dock═══] │  [═══Dock═══] │  ◄── Native macOS only shows 1 at a time
└───────────────┴───────────────┴───────────────┘
```

**MultiScreenDock** solves both problems cleanly in ~700 lines of pure Swift/AppKit, using **~0.0% idle CPU** and requiring **no Screen Recording or Accessibility permissions**.

---

## Features

- **Automatic sync with your real macOS Dock:** Reads `~/Library/Preferences/com.apple.dock.plist` and live `NSWorkspace` notifications to mirror **Finder**, all your **pinned apps**, **currently running unpinned apps** (with active/frontmost indicator dots), **pinned folders/files** (e.g. *Downloads*), and the **Trash**.
- **Smart anti-overlap with Apple's native Dock:** Automatically hides its bar on whichever single monitor currently displays Apple's native Dock (`visibleFrame` detection), or lets you toggle Apple's Dock auto-hide in one click from the menu bar so all monitors share the exact same static bar.
- **Per-monitor adaptive scaling:** Keeps your preferred icon size on wide monitors while proportionally scaling down on narrower displays so icons never clip or overflow.
- **Non-activating floating glass bar:** Clicking or hovering never steals focus from your active text editor or window until you launch/activate an app.
- **Full mouse & drag-and-drop workflow:**
  - **Left click:** Launch / activate app (`⌘+Click` reveals in Finder, `⌥+Click` hides active app).
  - **Right click:** Context menu (*Open/Show*, *Show in Finder*, *Hide*, *Quit*, *Empty Trash…*).
  - **Drag & Drop:** Drag files directly onto any app icon, folder, or Trash on any monitor.
- **Visible over full-screen apps** (optional toggle in menu bar).
- **Per-display toggles & Launch at Login** built right into the menu bar icon (`dock.rectangle`).
- **Automatic Localization:** English and Spanish (`en` / `es`) out of the box.

---

## Installation

### Option A: Download Prebuilt Universal App (Apple Silicon + Intel)

1. Download **`MultiScreenDock-v1.0.0-macOS.zip`** from the [**Latest Release**](https://github.com/fgomsan/MultiScreenDock/releases/latest).
2. Unzip and move **`MultiScreenDock.app`** to `/Applications` (or anywhere you like).
3. Because the app is ad-hoc signed without a paid Apple Developer ID certificate, clear the Gatekeeper quarantine flag once before first launch:
   ```bash
   xattr -cr /Applications/MultiScreenDock.app
   open /Applications/MultiScreenDock.app
   ```

### Option B: Build from Source (takes ~5 seconds)

Requires macOS 13+ with Xcode Command Line Tools (`xcode-select --install`):

```bash
git clone https://github.com/fgomsan/MultiScreenDock.git
cd MultiScreenDock
./build.sh
open ./MultiScreenDock.app
```

---

## Español — Guía rápida

**MultiScreenDock** mantiene tu Dock de macOS **siempre visible de forma simultánea en todas tus pantallas** (2, 3, 5 o más monitores), incluyendo **pantallas colocadas en una fila superior**, donde el Dock nativo de Apple jamás puede subir porque el ratón cruza hacia los monitores inferiores.

### Características principales
- **Sincronización automática:** Muestra **Finder**, tus **apps ancladas**, las **apps abiertas en ejecución** (con punto indicador), tus **carpetas/archivos del Dock** (*Descargas*, etc.) y la **Papelera**, leyendo directamente tu configuración real de `com.apple.dock.plist`.
- **Cero permisos invasivos y ~0 % de CPU:** Escrito al 100 % en Swift/AppKit nativo, sin pedir permisos de Accesibilidad ni Grabación de Pantalla.
- **Control desde la barra de menús:** Cambia el tamaño de iconos, activa o desactiva pantallas concretas, mantén el Dock visible sobre apps a pantalla completa, activa **Abrir al iniciar sesión** o activa **Ocultar Dock nativo de Apple** con un clic.

### Compilar o instalar
```bash
git clone https://github.com/fgomsan/MultiScreenDock.git
cd MultiScreenDock
./build.sh
open ./MultiScreenDock.app
```
*(Si descargas el `.zip` desde [Releases](https://github.com/fgomsan/MultiScreenDock/releases/latest), ejecuta `xattr -cr MultiScreenDock.app` antes de abrirlo por primera vez).*

---

## License

Released under the [MIT License](LICENSE).
