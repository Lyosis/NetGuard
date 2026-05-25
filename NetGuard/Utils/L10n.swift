import Foundation

// MARK: - L10n
/// Accès type-safe aux chaînes localisées.
/// Utilisation : Text(L10n.Sidebar.devices)  ou  label = L10n.Sidebar.devices
enum L10n {

    // MARK: - Helper interne
    private static func t(_ key: String, _ fallback: String) -> String {
        NSLocalizedString(key, value: fallback, comment: "")
    }
    private static func t(_ key: String, _ fallback: String, _ arg: CVarArg) -> String {
        String(format: NSLocalizedString(key, value: fallback, comment: ""), arg)
    }

    // MARK: - App
    enum App {
        static let name              = t("app.name",               "NetGuard")
        static let lastScanNever     = t("app.last_scan.never",    "Jamais scanné")
        static func lastScanSeconds(_ n: Int) -> String { t("app.last_scan.seconds", "Dernier scan il y a %d s",   n) }
        static func lastScanMinutes(_ n: Int) -> String { t("app.last_scan.minutes", "Dernier scan il y a %d min", n) }
        static func lastScanHours(_ n: Int)   -> String { t("app.last_scan.hours",   "Dernier scan il y a %d h",   n) }
    }

    // MARK: - Sidebar
    enum Sidebar {
        static let sectionNetwork   = t("sidebar.section.network",   "RÉSEAU")
        static let sectionAlerts    = t("sidebar.section.alerts",    "ALERTES")
        static let metricDevices    = t("sidebar.metric.devices",    "Appareils")
        static let metricPorts      = t("sidebar.metric.ports",      "Ports ouverts")
        static let metricEncrypt    = t("sidebar.metric.encrypt",    "Chiffrement")
        static let metricUnknown    = t("sidebar.metric.unknown",    "Inconnus")
        static let markAllRead      = t("sidebar.alerts.mark_all",   "Tout lire")
        static let scanning         = t("sidebar.alerts.scanning",   "Scan en cours…")
        static let noAlerts         = t("sidebar.alerts.none",       "Aucune alerte — lancez un scan")
        static func seeAll(_ n: Int) -> String { t("sidebar.alerts.see_all", "Voir toutes les alertes (%ld)", n) }
        static let scanFull         = t("sidebar.scan.full",         "Scan complet")
        static let scanQuick        = t("sidebar.scan.quick",        "Rapide")
        static let allAlerts        = t("sidebar.sheet.all_alerts",  "Toutes les alertes")
        static let close            = t("sidebar.sheet.close",       "Fermer")
        static let labelInterface   = t("sidebar.network.interface", "Interface")
        static let labelLocalIP     = t("sidebar.network.local_ip",  "IP locale")
        static let labelGateway     = t("sidebar.network.gateway",   "Passerelle")
        static let labelDNS         = t("sidebar.network.dns",       "DNS")
        static let labelSubnet      = t("sidebar.network.subnet",    "Sous-réseau")
        static let labelSSID        = t("sidebar.network.ssid",      "SSID")
        static let labelSecurity    = t("sidebar.network.security",  "Sécurité")
    }

    // MARK: - Carte réseau
    enum Map {
        static let title            = t("map.title",           "Carte du réseau local")
        static let internet         = t("map.internet",        "Internet")
        static let legendSafe       = t("map.legend.safe",     "Sûr")
        static let legendUnknown    = t("map.legend.unknown",  "Inconnu")
        static let legendAlert      = t("map.legend.alert",    "Alerte")
        static let emptyTitle       = t("map.empty.title",     "Aucun appareil détecté")
        static let emptySubtitle    = t("map.empty.subtitle",  "Lancez un scan pour découvrir les appareils")
        static let resetView        = t("map.reset_view",      "Réinitialiser la vue")
    }

    // MARK: - Détail appareil
    enum Detail {
        static let sectionIdentity  = t("detail.section.identity",  "IDENTITÉ")
        static let sectionNetwork   = t("detail.section.network",   "RÉSEAU")
        static func sectionPorts(_ n: Int) -> String { t("detail.section.ports",  "PORTS OUVERTS (%ld)", n) }
        static func sectionAlerts(_ n: Int) -> String { t("detail.section.alerts", "ALERTES (%ld)",       n) }
        static let labelVendor      = t("detail.label.vendor",      "Fabricant")
        static let labelOS          = t("detail.label.os",          "Système")
        static let labelTTL         = t("detail.label.ttl",         "TTL")
        static func ttlValue(_ n: Int) -> String { t("detail.ttl_value", "%ld sauts", n) }
        static let labelMAC         = t("detail.label.mac",         "Adresse MAC")
        static let labelBonjour     = t("detail.label.bonjour",     "Bonjour")
        static let labelNetBIOS     = t("detail.label.netbios",     "NetBIOS")
        static let labelDNS         = t("detail.label.dns",         "DNS")
        static let labelType        = t("detail.label.type",        "Type")
        static let labelRole        = t("detail.label.role",        "Rôle")
        static let currentDevice    = t("detail.current_device",    "Ce Mac (appareil courant)")
        static let labelLatency     = t("detail.label.latency",     "Latence")
        static let labelHTTPServer  = t("detail.label.http_server", "Serveur HTTP")
        static let labelWebPage     = t("detail.label.web_page",    "Page web")
        static let labelFirstSeen   = t("detail.label.first_seen",  "Vu pour la 1ère fois")
        static let labelLastSeen    = t("detail.label.last_seen",   "Dernière activité")
        static let placeholder      = t("detail.placeholder",       "Sélectionne un appareil")
        static let placeholderSub   = t("detail.placeholder.sub",   "Clique sur un nœud de la carte\npour voir ses détails")
    }

    // MARK: - Types d'appareils
    enum DeviceType {
        static let router    = t("device.type.router",   "Routeur")
        static let mac       = t("device.type.mac",      "Mac")
        static let iphone    = t("device.type.iphone",   "iPhone")
        static let ipad      = t("device.type.ipad",     "iPad")
        static let nas       = t("device.type.nas",      "NAS")
        static let printer   = t("device.type.printer",  "Imprimante")
        static let wifi      = t("device.type.wifi",     "WiFi AP")
        static let firewall  = t("device.type.firewall", "Firewall")
        static let `switch`  = t("device.type.switch",  "Switch")
        static let unknown   = t("device.type.unknown",  "Inconnu")
        static let internet  = t("device.type.internet", "Internet")
    }

    // MARK: - Statut appareil
    enum DeviceStatus {
        static let safe      = t("device.status.safe",    "Sûr")
        static let unknown   = t("device.status.unknown", "Inconnu")
        static let alert     = t("device.status.alert",   "Alerte")
        static let offline   = t("device.status.offline", "Hors ligne")
    }

    // MARK: - Système d'exploitation
    enum OS {
        static let macOS     = t("os.macos",   "macOS / Linux")
        static let windows   = t("os.windows", "Windows")
        static let linux     = t("os.linux",   "Linux")
        static let ios       = t("os.ios",     "iOS / iPadOS")
        static let router    = t("os.router",  "Routeur / Firmware")
        static let unknown   = t("os.unknown", "Inconnu")
    }

    // MARK: - Sévérité alertes
    enum Severity {
        static let critical  = t("alert.severity.critical", "Critique")
        static let high      = t("alert.severity.high",     "Élevé")
        static let medium    = t("alert.severity.medium",   "Moyen")
        static let low       = t("alert.severity.low",      "Faible")
        static let info      = t("alert.severity.info",     "Info")
    }

    // MARK: - Moniteur réseau
    enum Monitor {
        static let connected          = t("monitor.connected",         "Réseau connecté")
        static let disconnected       = t("monitor.disconnected",      "Réseau déconnecté")
        static let interfaceChanged   = t("monitor.interface_changed", "Interface changée")
        static let wifi               = t("monitor.wifi",              "WiFi")
        static let ethernet           = t("monitor.ethernet",          "Ethernet")
        static let noNetwork          = t("monitor.no_network",        "Aucun réseau")
        static let tapToRescan        = t("monitor.banner.tap_rescan", "Appuyer pour rescanner")
    }
}
