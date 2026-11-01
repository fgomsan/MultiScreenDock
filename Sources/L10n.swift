import Foundation

enum L10n {
    static let isSpanish: Bool = {
        guard let primary = Locale.preferredLanguages.first?.lowercased() else { return false }
        return primary.hasPrefix("es")
    }()

    static func tr(_ en: String, _ es: String) -> String {
        isSpanish ? es : en
    }

    // MARK: - Status & Menu
    static var tooltipStatus: String {
        tr("MultiScreenDock — Persistent Dock across all displays",
           "MultiScreenDock — Dock visible en todas tus pantallas")
    }

    static func headerAllPanels(visible: Int, total: Int) -> String {
        tr("MultiScreenDock — Active on \(visible) of \(total) displays",
           "MultiScreenDock — Activo en \(visible) de \(total) pantallas")
    }

    static func headerHybrid(visible: Int, total: Int) -> String {
        tr("MultiScreenDock — \(visible) panels + native Dock (\(total) displays)",
           "MultiScreenDock — \(visible) paneles + Dock nativo (\(total) pantallas)")
    }

    static var hideNativeDock: String {
        tr("Auto-hide Apple's native Dock (use this fixed on all screens)",
           "Ocultar Dock nativo de Apple (usar este fijo en todas)")
    }

    static var avoidOverlap: String {
        tr("Avoid overlapping where native Dock is visible",
           "No duplicar donde asome el Dock nativo")
    }

    static var keepOverFullScreen: String {
        tr("Keep visible over full-screen apps",
           "Mantener visible sobre apps a pantalla completa")
    }

    static var hoverMagnification: String {
        tr("Smooth hover magnification",
           "Ampliación suave al pasar el ratón")
    }

    static var showUnpinnedApps: String {
        tr("Show running unpinned apps",
           "Mostrar también apps abiertas no ancladas")
    }

    static var iconSizeMenu: String {
        tr("Icon Size", "Tamaño de iconos")
    }

    static var sizeCompact: String { tr("Compact (28 pt)", "Compacto (28 pt)") }
    static var sizeDefault: String { tr("Standard (36 pt)", "Estándar (36 pt)") }
    static var sizeMedium: String { tr("Medium (44 pt)", "Mediano (44 pt)") }
    static var sizeLarge: String { tr("Large (52 pt)", "Grande (52 pt)") }

    static func activeScreensMenu(_ count: Int) -> String {
        tr("Active Displays (\(count))", "Pantallas activas (\(count))")
    }

    static var rowUpper: String { tr("Upper", "Arriba") }
    static var rowLower: String { tr("Lower", "Abajo") }

    static var syncNow: String {
        tr("Sync Dock Icons Now", "Sincronizar iconos del Dock ahora")
    }

    static var launchAtLogin: String {
        tr("Launch at Login", "Abrir automáticamente al iniciar sesión")
    }

    static var quitApp: String {
        tr("Quit MultiScreenDock", "Salir de MultiScreenDock")
    }

    // MARK: - Items & Context Menu
    static var trashLabel: String { tr("Trash", "Papelera") }
    static var newFinderWindow: String { tr("New Finder Window", "Nueva ventana del Finder") }
    static func showApp(_ name: String) -> String { tr("Show \(name)", "Mostrar \(name)") }
    static func openApp(_ name: String) -> String { tr("Open \(name)", "Abrir \(name)") }
    static var showInFinder: String { tr("Show in Finder", "Mostrar en el Finder") }
    static var showContainerInFinder: String { tr("Show Enclosing Folder", "Mostrar contenedor en el Finder") }
    static var openInFinder: String { tr("Open in Finder", "Abrir en el Finder") }
    static var openGeneric: String { tr("Open", "Abrir") }
    static var showSingle: String { tr("Show", "Mostrar") }
    static var hideSingle: String { tr("Hide", "Ocultar") }
    static func quitTargetApp(_ name: String) -> String { tr("Quit \(name)", "Salir de \(name)") }
    static var openTrash: String { tr("Open Trash", "Abrir Papelera") }
    static var emptyTrash: String { tr("Empty Trash…", "Vaciar Papelera…") }
}
