import Foundation

enum L10n {
    static let isSpanish: Bool = {
        guard let primary = Locale.preferredLanguages.first?.lowercased() else { return false }
        return primary.hasPrefix("es")
    }()

    private static func pick(_ en: String, _ es: String) -> String {
        isSpanish ? es : en
    }

    // MARK: - Status & Menu
    static var tooltipStatus: String {
        pick("MultiScreenDock — Smart multi-monitor Dock",
             "MultiScreenDock — Dock inteligente en todas tus pantallas")
    }

    static func headerAutoHide(enabledCount: Int, total: Int) -> String {
        pick("MultiScreenDock — Auto-hide active on \(enabledCount) of \(total) displays",
             "MultiScreenDock — Auto-ocultación activa en \(enabledCount) de \(total) pantallas")
    }

    static func headerAllPanels(visible: Int, total: Int) -> String {
        pick("MultiScreenDock — Fixed on \(visible) of \(total) displays",
             "MultiScreenDock — Fijo en \(visible) de \(total) pantallas")
    }

    static func headerHybrid(visible: Int, total: Int) -> String {
        pick("MultiScreenDock — \(visible) panels + native Dock (\(total) displays)",
             "MultiScreenDock — \(visible) paneles + Dock nativo (\(total) pantallas)")
    }

    static var modeAutoHide: String {
        pick("Auto-hide & reveal on bottom hover",
             "Ocultar y mostrar al acercar el ratón abajo")
    }

    static var modeAlwaysVisible: String {
        pick("Keep Dock always fixed & visible",
             "Mantener el Dock siempre fijo visible")
    }

    static var showHintPill: String {
        pick("Show subtle bottom edge indicator when hidden",
             "Mostrar línea guía sutil abajo al estar oculto")
    }

    static var responsivenessMenu: String {
        pick("Hover Reveal Sensitivity",
             "Sensibilidad al acercar el ratón")
    }

    static var respFast: String {
        pick("Instant (40 ms)", "Instantánea (40 ms)")
    }

    static var respBalanced: String {
        pick("Balanced — Recommended (anti-crossing filter)",
             "Equilibrada — Recomendada (filtro al cruzar pantallas)")
    }

    static var respRelaxed: String {
        pick("Deliberate (slower trigger)",
             "Pausada (requiere detener más el cursor)")
    }

    static var skipPrimaryDisplay: String {
        pick("Skip primary display (use native macOS Dock there)",
             "Omitir en el monitor principal (usar allí el Dock original)")
    }

    static var primaryBadge: String {
        pick("Primary", "Principal")
    }

    static var hideNativeDock: String {
        pick("Auto-hide Apple's native Dock",
             "Ocultar automáticamente el Dock nativo de Apple")
    }

    static var avoidOverlap: String {
        pick("Avoid overlapping where native Dock is visible",
             "No duplicar donde asome el Dock nativo")
    }

    static var keepOverFullScreen: String {
        pick("Allow on full-screen apps",
             "Funcionar también sobre apps a pantalla completa")
    }

    static var hoverMagnification: String {
        pick("Smooth hover magnification",
             "Ampliación suave al pasar el ratón")
    }

    static var showUnpinnedApps: String {
        pick("Show running unpinned apps",
             "Mostrar también apps abiertas no ancladas")
    }

    static var iconSizeMenu: String {
        pick("Icon Size", "Tamaño de iconos")
    }

    static var sizeCompact: String { pick("Compact (28 pt)", "Compacto (28 pt)") }
    static var sizeDefault: String { pick("Standard (36 pt)", "Estándar (36 pt)") }
    static var sizeMedium: String { pick("Medium (44 pt)", "Mediano (44 pt)") }
    static var sizeLarge: String { pick("Large (52 pt)", "Grande (52 pt)") }

    static func activeScreensMenu(_ count: Int) -> String {
        pick("Active Displays (\(count))", "Pantallas activas (\(count))")
    }

    static var rowUpper: String { pick("Upper", "Arriba") }
    static var rowLower: String { pick("Lower", "Abajo") }

    static var syncNow: String {
        pick("Sync Dock Icons Now", "Sincronizar iconos del Dock ahora")
    }

    static var launchAtLogin: String {
        pick("Launch at Login", "Abrir automáticamente al iniciar sesión")
    }

    static var dockSettingsSubmenu: String {
        pick("MultiScreenDock Settings", "Ajustes de MultiScreenDock")
    }

    static var quitApp: String {
        pick("Quit MultiScreenDock", "Salir de MultiScreenDock")
    }

    // MARK: - Items & Context Menu
    static var trashLabel: String { pick("Trash", "Papelera") }
    static var newFinderWindow: String { pick("New Finder Window", "Nueva ventana del Finder") }
    static func showApp(_ name: String) -> String { pick("Show \(name)", "Mostrar \(name)") }
    static func openApp(_ name: String) -> String { pick("Open \(name)", "Abrir \(name)") }
    static var showInFinder: String { pick("Show in Finder", "Mostrar en el Finder") }
    static var showContainerInFinder: String { pick("Show Enclosing Folder", "Mostrar contenedor en el Finder") }
    static var openInFinder: String { pick("Open in Finder", "Abrir en el Finder") }
    static var openGeneric: String { pick("Open", "Abrir") }
    static var showSingle: String { pick("Show", "Mostrar") }
    static var hideSingle: String { pick("Hide", "Ocultar") }
    static func quitTargetApp(_ name: String) -> String { pick("Quit \(name)", "Salir de \(name)") }
    static var openTrash: String { pick("Open Trash", "Abrir Papelera") }
    static var emptyTrash: String { pick("Empty Trash…", "Vaciar Papelera…") }
}
