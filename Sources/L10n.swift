import Foundation

enum L10n {
    static let buyMeACoffeeURL = URL(string: "https://buymeacoffee.com/fgomsan")!

    /// Used by unit tests to verify all translations without mutating UserDefaults or instantiating DockSettings.
    static var overrideLanguageForTesting: AppLanguage?

    static func detectLanguage(from preferredLanguages: [String]) -> AppLanguage {
        for pref in preferredLanguages {
            let code = pref.lowercased()
            if code.hasPrefix("es") { return .es }
            if code.hasPrefix("fr") { return .fr }
            if code.hasPrefix("de") { return .de }
            if code.hasPrefix("pt") { return .pt }
            if code.hasPrefix("it") { return .it }
            if code.hasPrefix("ja") { return .ja }
            if code == "zh" || code.hasPrefix("zh-hans") || code.hasPrefix("zh-cn") || code.hasPrefix("zh-sg") {
                return .zhHans
            }
            if code.hasPrefix("zh") {
                // Traditional Chinese (zh-Hant / zh-TW / zh-HK) falls back to next preferred language or English
                continue
            }
            if code.hasPrefix("en") { return .en }
        }
        return .en
    }

    static var systemDetectedLanguage: AppLanguage {
        detectLanguage(from: Locale.preferredLanguages)
    }

    static var current: AppLanguage {
        if let override = overrideLanguageForTesting {
            return override == .system ? systemDetectedLanguage : override
        }
        let selected = DockSettings.shared.appLanguage
        return selected == .system ? systemDetectedLanguage : selected
    }

    private static func tr(
        en: String,
        es: String,
        fr: String,
        de: String,
        pt: String,
        it: String,
        ja: String,
        zh: String
    ) -> String {
        switch current {
        case .en, .system: return en
        case .es: return es
        case .fr: return fr
        case .de: return de
        case .pt: return pt
        case .it: return it
        case .ja: return ja
        case .zhHans: return zh
        }
    }

    // MARK: - Status & Menu
    static var tooltipStatus: String {
        tr(
            en: "MultiScreenDock — Smart multi-monitor Dock",
            es: "MultiScreenDock — Dock inteligente en todas tus pantallas",
            fr: "MultiScreenDock — Dock intelligent sur tous vos écrans",
            de: "MultiScreenDock — Intelligentes Dock auf allen Monitoren",
            pt: "MultiScreenDock — Dock inteligente em todos os monitores",
            it: "MultiScreenDock — Dock intelligente su tutti i monitor",
            ja: "MultiScreenDock — すべての画面にスマートなDockを表示",
            zh: "MultiScreenDock — 所有显示器上的智能程序坞"
        )
    }

    private static func plural(_ count: Int, one: String, other: String) -> String {
        count == 1 ? one : other
    }

    static func headerAutoHide(enabledCount: Int, total: Int) -> String {
        tr(
            en: "MultiScreenDock — Auto-hide active on \(enabledCount) of \(total) \(plural(total, one: "display", other: "displays"))",
            es: "MultiScreenDock — Auto-ocultación activa en \(enabledCount) de \(total) \(plural(total, one: "pantalla", other: "pantallas"))",
            fr: "MultiScreenDock — Masquage auto actif : \(enabledCount) sur \(total) \(plural(total, one: "écran", other: "écrans"))",
            de: "MultiScreenDock — Autom. Ausblenden aktiv auf \(enabledCount) von \(total) \(plural(total, one: "Display", other: "Displays"))",
            pt: "MultiScreenDock — Ocultação automática ativa em \(enabledCount) de \(total) \(plural(total, one: "monitor", other: "monitores"))",
            it: "MultiScreenDock — Nascondi automaticamente attivo su \(enabledCount) di \(total) \(plural(total, one: "schermo", other: "schermi"))",
            ja: "MultiScreenDock — 自動非表示：\(total)台中\(enabledCount)台のディスプレイで有効",
            zh: "MultiScreenDock — 自动隐藏已在 \(enabledCount)/\(total) 台显示器上启用"
        )
    }

    static func headerAllPanels(visible: Int, total: Int) -> String {
        tr(
            en: "MultiScreenDock — Fixed on \(visible) of \(total) \(plural(total, one: "display", other: "displays"))",
            es: "MultiScreenDock — Fijo en \(visible) de \(total) \(plural(total, one: "pantalla", other: "pantallas"))",
            fr: "MultiScreenDock — Fixe : \(visible) sur \(total) \(plural(total, one: "écran", other: "écrans"))",
            de: "MultiScreenDock — Sichtbar fixiert auf \(visible) von \(total) \(plural(total, one: "Display", other: "Displays"))",
            pt: "MultiScreenDock — Fixo em \(visible) de \(total) \(plural(total, one: "monitor", other: "monitores"))",
            it: "MultiScreenDock — Fisso su \(visible) di \(total) \(plural(total, one: "schermo", other: "schermi"))",
            ja: "MultiScreenDock — 常時表示：\(total)台中\(visible)台のディスプレイ",
            zh: "MultiScreenDock — 已固定显示在 \(visible)/\(total) 台显示器上"
        )
    }

    static func headerHybrid(visible: Int, total: Int) -> String {
        tr(
            en: "MultiScreenDock — \(visible) \(plural(visible, one: "panel", other: "panels")) + native Dock (\(total) \(plural(total, one: "display", other: "displays")))",
            es: "MultiScreenDock — \(visible) \(plural(visible, one: "panel", other: "paneles")) + Dock nativo (\(total) \(plural(total, one: "pantalla", other: "pantallas")))",
            fr: "MultiScreenDock — \(visible) \(plural(visible, one: "panneau", other: "panneaux")) + Dock natif (\(total) \(plural(total, one: "écran", other: "écrans")))",
            de: "MultiScreenDock — \(visible) \(plural(visible, one: "Leiste", other: "Leisten")) + System-Dock (\(total) \(plural(total, one: "Display", other: "Displays")))",
            pt: "MultiScreenDock — \(visible) \(plural(visible, one: "painel", other: "painéis")) + Dock nativo (\(total) \(plural(total, one: "monitor", other: "monitores")))",
            it: "MultiScreenDock — \(visible) \(plural(visible, one: "barra", other: "barre")) + Dock di sistema (\(total) \(plural(total, one: "schermo", other: "schermi")))",
            ja: "MultiScreenDock — \(visible)パネル + 標準Dock（計\(total)台）",
            zh: "MultiScreenDock — \(visible) 个面板 + 原生程序坞（共 \(total) 台显示器）"
        )
    }

    static var modeAutoHide: String {
        tr(
            en: "Auto-hide & reveal on bottom hover",
            es: "Ocultar y mostrar al acercar el ratón abajo",
            fr: "Masquer et afficher au survol du bord inférieur",
            de: "Automatisch ausblenden & am unteren Rand einblenden",
            pt: "Ocultar e mostrar ao passar o cursor na borda inferior",
            it: "Nascondi e mostra al passaggio sul bordo inferiore",
            ja: "自動的に隠す（画面下端にカーソルを合わせて表示）",
            zh: "自动隐藏（鼠标移至底部边缘时显示）"
        )
    }

    static var modeAlwaysVisible: String {
        tr(
            en: "Keep Dock always fixed & visible",
            es: "Mantener el Dock siempre fijo y visible",
            fr: "Garder le Dock toujours fixe et visible",
            de: "Dock immer sichtbar fixieren",
            pt: "Manter o Dock sempre fixo e visível",
            it: "Mantieni il Dock sempre fisso e visibile",
            ja: "Dockを常に表示したままにする",
            zh: "始终保持程序坞固定可见"
        )
    }

    static var showHintPill: String {
        tr(
            en: "Show subtle bottom edge indicator when hidden",
            es: "Mostrar línea guía sutil abajo al estar oculto",
            fr: "Afficher un discret repère en bas lorsque masqué",
            de: "Dezente Hinweislinie am unteren Rand anzeigen",
            pt: "Mostrar indicador sutil na borda inferior quando oculto",
            it: "Mostra indicatore discreto in basso quando nascosto",
            ja: "非表示時に画面下端の控えめなガイドバーを表示",
            zh: "隐藏时在底部显示柔和提示条"
        )
    }

    static var responsivenessMenu: String {
        tr(
            en: "Hover Reveal Sensitivity",
            es: "Sensibilidad al acercar el ratón",
            fr: "Sensibilité d’apparition au survol",
            de: "Ansprechverhalten beim Einblenden",
            pt: "Sensibilidade ao aproximar o cursor",
            it: "Sensibilità di comparsa al passaggio",
            ja: "表示の反応速度（感度）",
            zh: "底部悬停唤出灵敏度"
        )
    }

    static var respFast: String {
        tr(
            en: "Instant (40 ms)",
            es: "Instantánea (40 ms)",
            fr: "Instantanée (40 ms)",
            de: "Sofort (40 ms)",
            pt: "Instantânea (40 ms)",
            it: "Istantanea (40 ms)",
            ja: "高速（40 ms）",
            zh: "即时（40 毫秒）"
        )
    }

    static var respBalanced: String {
        tr(
            en: "Balanced — Recommended (anti-crossing filter)",
            es: "Equilibrada — Recomendada (filtro al cruzar pantallas)",
            fr: "Équilibrée — Recommandée (filtre inter-écrans)",
            de: "Ausgewogen — Empfohlen (Filter bei Bildschirmwechsel)",
            pt: "Equilibrada — Recomendada (filtro entre telas)",
            it: "Bilanciata — Consigliata (filtro cambio schermo)",
            ja: "標準 — 推奨（上下画面の通過誤作動を防止）",
            zh: "均衡 — 推荐（带跨屏防误触过滤）"
        )
    }

    static var respRelaxed: String {
        tr(
            en: "Deliberate (slower trigger)",
            es: "Pausada (requiere detener más el cursor)",
            fr: "Posée (déclenchement plus lent)",
            de: "Verzögert (längeres Verweilen nötig)",
            pt: "Pausada (ativação mais lenta)",
            it: "Rilassata (attivazione più lenta)",
            ja: "ゆっくり（少し長めに静止して表示）",
            zh: "舒缓（需稍作停留才唤出）"
        )
    }

    static var skipPrimaryDisplay: String {
        tr(
            en: "Skip primary display (use native macOS Dock there)",
            es: "Omitir en el monitor principal (usar allí el Dock original)",
            fr: "Ignorer l’écran principal (y garder le Dock macOS natif)",
            de: "Hauptdisplay überspringen (dort macOS-Dock nutzen)",
            pt: "Ignorar monitor principal (usar lá o Dock nativo do macOS)",
            it: "Ignora schermo principale (usa lì il Dock nativo di macOS)",
            ja: "メインディスプレイを除外（標準のmacOS Dockを使用）",
            zh: "跳过主显示器（在主屏使用 macOS 原生程序坞）"
        )
    }

    static var primaryBadge: String {
        tr(
            en: "Primary",
            es: "Principal",
            fr: "Principal",
            de: "Hauptdisplay",
            pt: "Principal",
            it: "Principale",
            ja: "メイン",
            zh: "主显示器"
        )
    }

    static var hideNativeDock: String {
        tr(
            en: "Auto-hide Apple's native Dock",
            es: "Ocultar automáticamente el Dock nativo de Apple",
            fr: "Masquer automatiquement le Dock natif d’Apple",
            de: "Apples System-Dock automatisch ausblenden",
            pt: "Ocultar automaticamente o Dock nativo da Apple",
            it: "Nascondi automaticamente il Dock nativo di Apple",
            ja: "Apple標準のDockを自動的に隠す",
            zh: "自动隐藏 Apple 原生程序坞"
        )
    }

    static var avoidOverlap: String {
        tr(
            en: "Avoid overlapping where native Dock is visible",
            es: "No duplicar donde asome el Dock nativo",
            fr: "Éviter le chevauchement où le Dock natif est visible",
            de: "Überlappung mit sichtbarem System-Dock vermeiden",
            pt: "Evitar sobreposição onde o Dock nativo estiver visível",
            it: "Evita sovrapposizioni dove il Dock nativo è visibile",
            ja: "標準Dockが表示されている画面では重複表示しない",
            zh: "原生程序坞可见时避免重叠显示"
        )
    }

    static var keepOverFullScreen: String {
        tr(
            en: "Allow on full-screen apps",
            es: "Funcionar también sobre apps a pantalla completa",
            fr: "Autoriser sur les apps en plein écran",
            de: "Auch über Vollbild-Apps anzeigen",
            pt: "Permitir sobre apps em tela cheia",
            it: "Consenti sopra le app a tutto schermo",
            ja: "フルスクリーンアプリ上でも表示を許可",
            zh: "允许在全屏应用上方显示"
        )
    }

    static var hoverMagnification: String {
        tr(
            en: "Smooth hover magnification",
            es: "Ampliación suave al pasar el ratón",
            fr: "Agrandissement fluide au survol",
            de: "Sanfte Vergrößerung beim Überfahren",
            pt: "Ampliação suave ao passar o cursor",
            it: "Ingrandimento fluido al passaggio del mouse",
            ja: "ホバー時のスムーズな拡大表示",
            zh: "鼠标悬停平滑放大图标"
        )
    }

    static var showUnpinnedApps: String {
        tr(
            en: "Show running unpinned apps",
            es: "Mostrar también apps abiertas no ancladas",
            fr: "Afficher les apps ouvertes non épinglées",
            de: "Laufende nicht angeheftete Apps anzeigen",
            pt: "Mostrar apps abertos não fixados",
            it: "Mostra app aperte non mantenute nel Dock",
            ja: "起動中の未固定アプリも表示",
            zh: "显示正在运行但未固定的应用"
        )
    }

    static var iconSizeMenu: String {
        tr(
            en: "Icon Size",
            es: "Tamaño de iconos",
            fr: "Taille des icônes",
            de: "Symbolgröße",
            pt: "Tamanho dos ícones",
            it: "Dimensione icone",
            ja: "アイコンのサイズ",
            zh: "图标大小"
        )
    }

    static var sizeCompact: String {
        tr(
            en: "Compact (28 pt)",
            es: "Compacto (28 pt)",
            fr: "Compact (28 pt)",
            de: "Kompakt (28 pt)",
            pt: "Compacto (28 pt)",
            it: "Compatta (28 pt)",
            ja: "コンパクト (28 pt)",
            zh: "紧凑 (28 pt)"
        )
    }

    static var sizeDefault: String {
        tr(
            en: "Standard (36 pt)",
            es: "Estándar (36 pt)",
            fr: "Standard (36 pt)",
            de: "Standard (36 pt)",
            pt: "Padrão (36 pt)",
            it: "Standard (36 pt)",
            ja: "標準 (36 pt)",
            zh: "标准 (36 pt)"
        )
    }

    static var sizeMedium: String {
        tr(
            en: "Medium (44 pt)",
            es: "Mediano (44 pt)",
            fr: "Moyen (44 pt)",
            de: "Mittel (44 pt)",
            pt: "Médio (44 pt)",
            it: "Media (44 pt)",
            ja: "中 (44 pt)",
            zh: "中等 (44 pt)"
        )
    }

    static var sizeLarge: String {
        tr(
            en: "Large (52 pt)",
            es: "Grande (52 pt)",
            fr: "Grand (52 pt)",
            de: "Groß (52 pt)",
            pt: "Grande (52 pt)",
            it: "Grande (52 pt)",
            ja: "大 (52 pt)",
            zh: "大号 (52 pt)"
        )
    }

    static func sizeSystemDock(_ pts: Int) -> String {
        tr(
            en: "System Dock (\(pts) pt)",
            es: "Dock del sistema (\(pts) pt)",
            fr: "Dock système (\(pts) pt)",
            de: "System-Dock (\(pts) pt)",
            pt: "Dock do sistema (\(pts) pt)",
            it: "Dock di sistema (\(pts) pt)",
            ja: "標準Dock（\(pts) pt）",
            zh: "系统程序坞（\(pts) pt）"
        )
    }

    static func activeScreensMenu(_ count: Int) -> String {
        tr(
            en: "Active Displays (\(count))",
            es: "Pantallas activas (\(count))",
            fr: "Écrans actifs (\(count))",
            de: "Aktive Displays (\(count))",
            pt: "Monitores ativos (\(count))",
            it: "Schermi attivi (\(count))",
            ja: "対象ディスプレイ (\(count))",
            zh: "活动显示器 (\(count))"
        )
    }

    static var rowUpper: String {
        tr(
            en: "Upper",
            es: "Arriba",
            fr: "Haut",
            de: "Oben",
            pt: "Superior",
            it: "Superiore",
            ja: "上段",
            zh: "上排"
        )
    }

    static var rowLower: String {
        tr(
            en: "Lower",
            es: "Abajo",
            fr: "Bas",
            de: "Unten",
            pt: "Inferior",
            it: "Inferiore",
            ja: "下段",
            zh: "下排"
        )
    }

    static var languageMenu: String {
        tr(
            en: "Language",
            es: "Idioma",
            fr: "Langue",
            de: "Sprache",
            pt: "Idioma",
            it: "Lingua",
            ja: "言語 (Language)",
            zh: "语言 (Language)"
        )
    }

    static func languageSystemAuto(_ detectedName: String) -> String {
        tr(
            en: "Automatic (macOS — \(detectedName))",
            es: "Automático (macOS — \(detectedName))",
            fr: "Automatique (macOS — \(detectedName))",
            de: "Automatisch (macOS — \(detectedName))",
            pt: "Automático (macOS — \(detectedName))",
            it: "Automatico (macOS — \(detectedName))",
            ja: "自動（macOS — \(detectedName)）",
            zh: "自动跟随系统（macOS — \(detectedName)）"
        )
    }

    static var syncNow: String {
        tr(
            en: "Sync Dock Icons Now",
            es: "Sincronizar iconos del Dock ahora",
            fr: "Synchroniser les icônes du Dock maintenant",
            de: "Dock-Symbole jetzt synchronisieren",
            pt: "Sincronizar ícones do Dock agora",
            it: "Sincronizza icone del Dock ora",
            ja: "Dockアイコンを今すぐ同期",
            zh: "立即同步程序坞图标"
        )
    }

    static var launchAtLogin: String {
        tr(
            en: "Launch at Login",
            es: "Abrir automáticamente al iniciar sesión",
            fr: "Ouvrir à la connexion",
            de: "Bei der Anmeldung öffnen",
            pt: "Abrir ao iniciar sessão",
            it: "Apri al login",
            ja: "ログイン時に開く",
            zh: "登录时自动打开"
        )
    }

    static var buyMeACoffee: String {
        tr(
            en: "Buy Me a Coffee…",
            es: "Invítame a un café…",
            fr: "M’offrir un café…",
            de: "Spendier mir einen Kaffee…",
            pt: "Pague-me um café…",
            it: "Offrimi un caffè…",
            ja: "開発者にコーヒーを贈る…",
            zh: "请开发者喝杯咖啡…"
        )
    }

    static var dockSettingsSubmenu: String {
        tr(
            en: "MultiScreenDock Settings",
            es: "Ajustes de MultiScreenDock",
            fr: "Réglages MultiScreenDock",
            de: "MultiScreenDock-Einstellungen",
            pt: "Ajustes do MultiScreenDock",
            it: "Impostazioni MultiScreenDock",
            ja: "MultiScreenDock の設定",
            zh: "MultiScreenDock 设置"
        )
    }

    static var quitApp: String {
        tr(
            en: "Quit MultiScreenDock",
            es: "Salir de MultiScreenDock",
            fr: "Quitter MultiScreenDock",
            de: "MultiScreenDock beenden",
            pt: "Encerrar MultiScreenDock",
            it: "Esci da MultiScreenDock",
            ja: "MultiScreenDock を終了",
            zh: "退出 MultiScreenDock"
        )
    }

    // MARK: - Items & Context Menu
    static var finderLabel: String {
        tr(
            en: "Finder",
            es: "Finder",
            fr: "Finder",
            de: "Finder",
            pt: "Finder",
            it: "Finder",
            ja: "Finder",
            zh: "访达"
        )
    }

    static var runningAccessibilityState: String {
        tr(
            en: "Running",
            es: "En ejecución",
            fr: "Ouverte",
            de: "Aktiv",
            pt: "Em execução",
            it: "In esecuzione",
            ja: "起動中",
            zh: "正在运行"
        )
    }

    static var trashLabel: String {
        tr(
            en: "Trash",
            es: "Papelera",
            fr: "Corbeille",
            de: "Papierkorb",
            pt: "Lixo",
            it: "Cestino",
            ja: "ゴミ箱",
            zh: "废纸篓"
        )
    }

    static var newFinderWindow: String {
        tr(
            en: "New Finder Window",
            es: "Nueva ventana del Finder",
            fr: "Nouvelle fenêtre du Finder",
            de: "Neues Finder-Fenster",
            pt: "Nova Janela do Finder",
            it: "Nuova finestra del Finder",
            ja: "新規Finderウインドウ",
            zh: "新建访达窗口"
        )
    }

    static func showApp(_ name: String) -> String {
        tr(
            en: "Show \(name)",
            es: "Mostrar \(name)",
            fr: "Afficher \(name)",
            de: "\(name) einblenden",
            pt: "Mostrar \(name)",
            it: "Mostra \(name)",
            ja: "\(name)を表示",
            zh: "显示 \(name)"
        )
    }

    static func openApp(_ name: String) -> String {
        tr(
            en: "Open \(name)",
            es: "Abrir \(name)",
            fr: "Ouvrir \(name)",
            de: "\(name) öffnen",
            pt: "Abrir \(name)",
            it: "Apri \(name)",
            ja: "\(name)を開く",
            zh: "打开 \(name)"
        )
    }

    static var showInFinder: String {
        tr(
            en: "Show in Finder",
            es: "Mostrar en el Finder",
            fr: "Afficher dans le Finder",
            de: "Im Finder zeigen",
            pt: "Mostrar no Finder",
            it: "Mostra nel Finder",
            ja: "Finderに表示",
            zh: "在访达中显示"
        )
    }

    static var showContainerInFinder: String {
        tr(
            en: "Show Enclosing Folder",
            es: "Mostrar contenedor en el Finder",
            fr: "Afficher le dossier parent",
            de: "Übergeordneten Ordner zeigen",
            pt: "Mostrar na Pasta",
            it: "Mostra cartella superiore",
            ja: "内包しているフォルダを表示",
            zh: "显示所在文件夹"
        )
    }

    static var openInFinder: String {
        tr(
            en: "Open in Finder",
            es: "Abrir en el Finder",
            fr: "Ouvrir dans le Finder",
            de: "Im Finder öffnen",
            pt: "Abrir no Finder",
            it: "Apri nel Finder",
            ja: "Finderで開く",
            zh: "在访达中打开"
        )
    }

    static var openGeneric: String {
        tr(
            en: "Open",
            es: "Abrir",
            fr: "Ouvrir",
            de: "Öffnen",
            pt: "Abrir",
            it: "Apri",
            ja: "開く",
            zh: "打开"
        )
    }

    static var showSingle: String {
        tr(
            en: "Show",
            es: "Mostrar",
            fr: "Afficher",
            de: "Einblenden",
            pt: "Mostrar",
            it: "Mostra",
            ja: "表示",
            zh: "显示"
        )
    }

    static var hideSingle: String {
        tr(
            en: "Hide",
            es: "Ocultar",
            fr: "Masquer",
            de: "Ausblenden",
            pt: "Ocultar",
            it: "Nascondi",
            ja: "隠す",
            zh: "隐藏"
        )
    }

    static func quitTargetApp(_ name: String) -> String {
        tr(
            en: "Quit \(name)",
            es: "Salir de \(name)",
            fr: "Quitter \(name)",
            de: "\(name) beenden",
            pt: "Encerrar \(name)",
            it: "Esci da \(name)",
            ja: "\(name)を終了",
            zh: "退出 \(name)"
        )
    }

    static var openTrash: String {
        tr(
            en: "Open Trash",
            es: "Abrir Papelera",
            fr: "Ouvrir la corbeille",
            de: "Papierkorb öffnen",
            pt: "Abrir Lixo",
            it: "Apri Cestino",
            ja: "ゴミ箱を開く",
            zh: "打开废纸篓"
        )
    }

    static var emptyTrash: String {
        tr(
            en: "Empty Trash…",
            es: "Vaciar Papelera…",
            fr: "Vider la corbeille…",
            de: "Papierkorb entleeren…",
            pt: "Esvaziar Lixo…",
            it: "Vuota il Cestino…",
            ja: "ゴミ箱を空にする…",
            zh: "清倒废纸篓…"
        )
    }

    static var emptyTrashConfirmTitle: String {
        tr(
            en: "Are you sure you want to permanently erase the items in the Trash?",
            es: "¿Seguro que quieres borrar definitivamente los ítems de la Papelera?",
            fr: "Voulez-vous vraiment effacer définitivement les éléments de la corbeille ?",
            de: "Möchtest du die Objekte im Papierkorb wirklich endgültig löschen?",
            pt: "Tem certeza de que deseja apagar permanentemente os itens no Lixo?",
            it: "Vuoi davvero eliminare definitivamente gli elementi nel Cestino?",
            ja: "ゴミ箱内の項目を完全に消去してもよろしいですか？",
            zh: "确定要永久抹掉废纸篓中的项目吗？"
        )
    }

    static var emptyTrashConfirmMessage: String {
        tr(
            en: "You can't undo this action.",
            es: "Esta acción no se puede deshacer.",
            fr: "Cette action est irréversible.",
            de: "Diese Aktion kann nicht widerrufen werden.",
            pt: "Você não pode desfazer esta ação.",
            it: "Non puoi annullare questa azione.",
            ja: "この操作は取り消せません。",
            zh: "此操作不能撤销。"
        )
    }

    static var emptyTrashConfirmBtn: String {
        tr(
            en: "Empty Trash",
            es: "Vaciar Papelera",
            fr: "Vider la corbeille",
            de: "Papierkorb entleeren",
            pt: "Esvaziar Lixo",
            it: "Vuota il Cestino",
            ja: "ゴミ箱を空にする",
            zh: "清倒废纸篓"
        )
    }

    // MARK: - Alerts & Error Feedback
    static var dragMoveErrorTitle: String {
        tr(
            en: "Could Not Move All Items",
            es: "No se pudieron mover todos los archivos",
            fr: "Impossible de déplacer tous les éléments",
            de: "Nicht alle Objekte konnten bewegt werden",
            pt: "Não foi possível mover todos os itens",
            it: "Impossibile spostare tutti gli elementi",
            ja: "一部の項目を移動できませんでした",
            zh: "无法移动部分项目"
        )
    }

    static var dragCopyErrorTitle: String {
        tr(
            en: "Could Not Copy All Items",
            es: "No se pudieron copiar todos los archivos",
            fr: "Impossible de copier tous les éléments",
            de: "Nicht alle Objekte konnten kopiert werden",
            pt: "Não foi possível copiar todos os itens",
            it: "Impossibile copiare tutti gli elementi",
            ja: "一部の項目をコピーできませんでした",
            zh: "无法拷贝部分项目"
        )
    }

    static var dragTrashErrorTitle: String {
        tr(
            en: "Could Not Move Items to Trash",
            es: "No se pudieron enviar los archivos a la Papelera",
            fr: "Impossible de placer les éléments dans la corbeille",
            de: "Objekte konnten nicht in den Papierkorb gelegt werden",
            pt: "Não foi possível mover os itens para o Lixo",
            it: "Impossibile spostare gli elementi nel Cestino",
            ja: "項目をゴミ箱に入れられませんでした",
            zh: "无法将项目移到废纸篓"
        )
    }

    static var dragOpenErrorTitle: String {
        tr(
            en: "Could Not Open Items",
            es: "No se pudieron abrir los archivos",
            fr: "Impossible d’ouvrir les éléments",
            de: "Objekte konnten nicht geöffnet werden",
            pt: "Não foi possível abrir os itens",
            it: "Impossibile aprire gli elementi",
            ja: "項目を開けませんでした",
            zh: "无法打开项目"
        )
    }

    static var dockAutohidePermTitle: String {
        tr(
            en: "Automation Permission Denied",
            es: "Permiso de Automatización denegado",
            fr: "Autorisation d’automatisation refusée",
            de: "Automatisierungsberechtigung verweigert",
            pt: "Permissão de Automação negada",
            it: "Autorizzazione Automazione negata",
            ja: "オートメーションの許可がありません",
            zh: "自动化权限被拒绝"
        )
    }

    static var dockAutohideScriptErrorTitle: String {
        tr(
            en: "Could Not Toggle Apple's Dock",
            es: "No se pudo cambiar el Dock de Apple",
            fr: "Impossible de modifier le Dock d’Apple",
            de: "Apples System-Dock konnte nicht umgeschaltet werden",
            pt: "Não foi possível alternar o Dock da Apple",
            it: "Impossibile modificare il Dock di Apple",
            ja: "Apple標準のDockを切り替えられませんでした",
            zh: "无法切换 Apple 原生程序坞"
        )
    }

    static var dockAutohidePermMessage: String {
        tr(
            en: "MultiScreenDock could not ask System Events to toggle Apple's Dock smoothly. You can grant Automation permission in System Settings, or apply the preference now by restarting Apple's Dock.",
            es: "MultiScreenDock no pudo cambiar el Dock de Apple suavemente mediante System Events. Puedes conceder permiso en Ajustes del Sistema o aplicarlo ahora reiniciando el proceso del Dock.",
            fr: "MultiScreenDock n’a pas pu modifier le Dock via System Events. Vous pouvez accorder l’accès dans Réglages Système ou redémarrer le Dock maintenant.",
            de: "MultiScreenDock konnte das Apple-Dock nicht über System Events umschalten. Sie können die Berechtigung in den Systemeinstellungen erteilen oder das Dock jetzt neu starten.",
            pt: "O MultiScreenDock não pôde alternar o Dock da Apple via System Events. Você pode conceder permissão nos Ajustes do Sistema ou reiniciar o Dock agora.",
            it: "MultiScreenDock non ha potuto modificare il Dock tramite System Events. Puoi concedere il permesso in Impostazioni di Sistema o riavviare il Dock ora.",
            ja: "System Events経由でApple標準Dockを切り替えられませんでした。システム設定で許可するか、Dockを再起動して今すぐ適用できます。",
            zh: "无法通过 System Events 平滑切换原生程序坞。您可以在系统设置中授予自动化权限，或立即重启原生程序坞以应用更改。"
        )
    }

    static var dockAutohideRestartBtn: String {
        tr(
            en: "Restart Dock Now",
            es: "Reiniciar el Dock ahora",
            fr: "Redémarrer le Dock",
            de: "Dock jetzt neu starten",
            pt: "Reiniciar Dock agora",
            it: "Riavvia il Dock ora",
            ja: "Dockを今すぐ再起動",
            zh: "立即重启程序坞"
        )
    }

    static var openAutomationSettingsBtn: String {
        tr(
            en: "Open System Settings",
            es: "Abrir Ajustes del Sistema",
            fr: "Ouvrir Réglages Système",
            de: "Systemeinstellungen öffnen",
            pt: "Abrir Ajustes do Sistema",
            it: "Apri Impostazioni di Sistema",
            ja: "システム設定を開く",
            zh: "打开系统设置"
        )
    }

    static var cancelBtn: String {
        tr(
            en: "Cancel",
            es: "Cancelar",
            fr: "Annuler",
            de: "Abbrechen",
            pt: "Cancelar",
            it: "Annulla",
            ja: "キャンセル",
            zh: "取消"
        )
    }

    static var okBtn: String {
        tr(
            en: "OK",
            es: "Aceptar",
            fr: "OK",
            de: "OK",
            pt: "OK",
            it: "OK",
            ja: "OK",
            zh: "好"
        )
    }

    static var loginItemErrorTitle: String {
        tr(
            en: "Could Not Update Login Item",
            es: "No se pudo actualizar el inicio automático",
            fr: "Impossible de modifier l’ouverture à la connexion",
            de: "Anmeldeobjekt konnte nicht geändert werden",
            pt: "Não foi possível alterar o item de início",
            it: "Impossibile aggiornare l’elemento di login",
            ja: "ログイン項目を更新できませんでした",
            zh: "无法更新登录项"
        )
    }

    static var loginItemRequiresApprovalBadge: String {
        tr(
            en: " (Approve in System Settings)",
            es: " (Aprobar en Ajustes del Sistema)",
            fr: " (À autoriser dans Réglages Système)",
            de: " (In Systemeinstellungen erlauben)",
            pt: " (Aprovar nos Ajustes do Sistema)",
            it: " (Approva in Impostazioni di Sistema)",
            ja: "（システム設定で許可が必要）",
            zh: "（需在系统设置中批准）"
        )
    }
}
