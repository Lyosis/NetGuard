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
    private static func t(_ key: String, _ fallback: String, _ a1: CVarArg, _ a2: CVarArg) -> String {
        String(format: NSLocalizedString(key, value: fallback, comment: ""), a1, a2)
    }

    // MARK: - App
    enum App {
        static let name              = t("app.name",               "NetGuard")
        static let lastScanNever     = t("app.last_scan.never",    "Jamais scanné")
        static func lastScanSeconds(_ n: Int) -> String { t("app.last_scan.seconds", "Dernier scan il y a %d s",   n) }
        static func lastScanMinutes(_ n: Int) -> String { t("app.last_scan.minutes", "Dernier scan il y a %d min", n) }
        static func lastScanHours(_ n: Int)   -> String { t("app.last_scan.hours",   "Dernier scan il y a %d h",   n) }
    }

    // MARK: - Accessibilité (VoiceOver)
    enum A11y {
        /// Annonce vocale de fin de scan : « Scan terminé. 12 appareils, 3 alertes. »
        static func scanDone(devices: Int, alerts: Int) -> String {
            t("a11y.scan.done", "Scan terminé. %1$d appareils, %2$d alertes.", devices, alerts)
        }
        /// Annonce vocale de fin de scan rapide : « Scan rapide terminé. 12 appareils. »
        static func scanQuickDone(devices: Int) -> String {
            t("a11y.scan.quick_done", "Scan rapide terminé. %d appareils.", devices)
        }
        /// Indice d'action sur un nœud de la carte
        static let nodeHint   = t("a11y.node.hint", "Touchez deux fois pour voir les détails.")
        /// Fragment de libellé : « 3 alertes »
        static func alerts(_ n: Int) -> String { t("a11y.alerts", "%d alertes", n) }
        /// Libellé du bouton Internet sur la carte
        static let internet   = t("a11y.internet", "Internet, passerelle vers l'extérieur")
        static let zoomIn     = t("a11y.zoom_in",  "Zoom avant")
        static let zoomOut    = t("a11y.zoom_out", "Zoom arrière")
        static let filterActive = t("a11y.filter.active", "Filtre actif. Touchez pour désactiver.")
        static let filterHint   = t("a11y.filter.hint",   "Touchez pour filtrer la carte sur cette catégorie.")
    }

    // MARK: - Barre de menus (macOS)
    enum Menu {
        static let scan         = t("menu.scan",            "Scan")
        static let scanFull      = t("menu.scan.full",       "Scan complet")
        static let scanQuick     = t("menu.scan.quick",      "Scan rapide")
        static let markAllRead   = t("menu.alerts.mark_all", "Marquer toutes les alertes comme lues")
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
        static let emptyTitle        = t("map.empty.title",       "Aucun appareil détecté")
        static let emptySubtitle     = t("map.empty.subtitle",    "Lancez un scan pour découvrir les appareils")
        static let diagnose          = t("map.diagnose",           "Diagnostiquer le réseau")
        static let resetView         = t("map.reset_view",         "Réinitialiser la vue")
        static let searchPlaceholder = t("map.search.placeholder", "Rechercher…")
        static let filterNoResults   = t("map.filter.no_results",  "Aucun appareil ne correspond")
        static let filterClear       = t("map.filter.clear",       "Effacer les filtres")
        static let filterToggle      = t("map.filter.toggle",      "Filtres")
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
        static let labelBonjour         = t("detail.label.bonjour",          "Bonjour")
        static let labelBonjourServices = t("detail.label.bonjour_services", "Services")
        static let labelUPnP            = t("detail.label.upnp",             "UPnP")
        static let labelNetBIOS         = t("detail.label.netbios",          "NetBIOS")
        static let labelDNS         = t("detail.label.dns",         "DNS")
        static let labelType        = t("detail.label.type",        "Type")
        static let labelRole        = t("detail.label.role",        "Rôle")
        static let currentDevice    = t("detail.current_device",    "Ce Mac (appareil courant)")
        static let labelPrivacy     = t("detail.label.privacy",     "Confidentialité")
        static let privateMACBadge  = t("detail.privacy.mac_private",
                                        "MAC privée — à vérifier sur l'appareil")
        static let privateMACHint   = t("detail.privacy.mac_private.hint",
                                        "Cet appareil utilise une adresse MAC privée (option WiFi privé d'iOS/iPadOS/macOS Sonoma+/Android 10+). Le type est déduit par heuristique — confirme depuis l'appareil lui-même.")
        static let labelLatency     = t("detail.label.latency",     "Latence")
        static let labelHTTPServer  = t("detail.label.http_server", "Serveur HTTP")
        static let labelWebPage     = t("detail.label.web_page",    "Page web")
        static let labelFirstSeen   = t("detail.label.first_seen",  "Vu pour la 1ère fois")
        static let labelLastSeen    = t("detail.label.last_seen",   "Dernière activité")
        static let placeholder      = t("detail.placeholder",       "Sélectionne un appareil")
        static let placeholderSub   = t("detail.placeholder.sub",   "Clique sur un nœud de la carte\npour voir ses détails")
    }

    // MARK: - Accès rapide (lanceurs de protocoles)
    enum QuickAccess {
        static let sectionTitle = t("qa.section",         "ACCÈS RAPIDE")
        static let browser      = t("qa.browser",         "Navigateur")
        static let ssh          = t("qa.ssh",             "SSH")
        static let sftp         = t("qa.sftp",            "SFTP")
        static let smb          = t("qa.smb",             "SMB")
        static let afp          = t("qa.afp",             "AFP")
        static let vnc          = t("qa.vnc",             "VNC")
        static let ftp          = t("qa.ftp",             "FTP")
        // Hints accessibilité
        static let browserHint  = t("qa.browser.hint",    "Ouvre l'interface web de l'appareil dans le navigateur par défaut.")
        static let sshHint      = t("qa.ssh.hint",        "Ouvre une session SSH dans le Terminal.")
        static let sftpHint     = t("qa.sftp.hint",       "Ouvre une connexion SFTP dans le Finder.")
        static let smbHint      = t("qa.smb.hint",        "Monte le partage SMB/Windows dans le Finder.")
        static let afpHint      = t("qa.afp.hint",        "Monte le partage AFP (Apple Filing Protocol) dans le Finder.")
        static let vncHint      = t("qa.vnc.hint",        "Ouvre l'écran distant dans Screen Sharing.")
        static let ftpHint      = t("qa.ftp.hint",        "Ouvre une connexion FTP dans le Finder.")
    }

    // MARK: - Certificat SSL (A2)
    enum Certificate {
        static let sectionTitle    = t("cert.section",          "CERTIFICAT SSL")
        static let labelSubject    = t("cert.label.subject",    "Sujet")
        static let labelIssuer     = t("cert.label.issuer",     "Émetteur")
        static let labelValidFrom  = t("cert.label.valid_from", "Valide depuis")
        static let labelValidTo    = t("cert.label.valid_to",   "Expire le")
        static let badgeTrusted    = t("cert.badge.trusted",    "Approuvé")
        static let badgeUntrusted  = t("cert.badge.untrusted",  "Non approuvé")
        static let badgeSelfSigned = t("cert.badge.self_signed","Auto-signé")
        static let badgeExpired    = t("cert.badge.expired",    "Expiré")
        static let badgeNearExpiry = t("cert.badge.near_expiry","Bientôt expiré")
        static func daysLeft(_ n: Int) -> String {
            t("cert.days_left", "%d jour(s) restant(s)", n)
        }
        // A3 — bouton « Voir le certificat »
        static let viewButton     = t("cert.view_button",       "Voir le certificat")
        static let viewButtonHint = t("cert.view_button.hint",
                                      "Ouvre le panneau système macOS avec tous les détails du certificat SSL.")
        static let fetchFailed    = t("cert.fetch_failed",
                                      "Impossible de récupérer le certificat (appareil hors ligne ?).")
    }

    // MARK: - Forcer le type (override utilisateur)
    enum Override {
        static let autoDetect  = t("override.auto",         "Auto-détecté")
        static let forcedBadge = t("override.forced_badge", "Forcé")
        static let menuHint    = t("override.menu.hint",
                                   "Choisis manuellement le type si l'auto-détection est incorrecte. « Auto-détecté » revient au type deviné par NetGuard.")
    }

    // MARK: - Annotations utilisateur (nom + notes)
    enum UserAnnotation {
        static let aliasPlaceholder = t("user.alias.placeholder",
                                        "Nom personnalisé (ex : Mon NAS)")
        static let notesSection     = t("user.notes.section",     "NOTES")
        static let notesPlaceholder = t("user.notes.placeholder",
                                        "Ajouter une note…")
    }

    // MARK: - Audit de sécurité
    enum Audit {
        static let sectionTitle   = t("audit.section",          "AUDIT DE SÉCURITÉ")
        static let launch         = t("audit.launch",           "Lancer l'audit")
        static let running        = t("audit.running",          "Audit en cours…")
        static let scoreLabel     = t("audit.score",            "Score")
        static let safe           = t("audit.level.safe",       "Sûr")
        static let moderate       = t("audit.level.moderate",   "Modéré")
        static let risky          = t("audit.level.risky",      "Risqué")
        static let critical       = t("audit.level.critical",   "Critique")
        static let credsTested    = t("audit.creds.tested",     "Identifiants par défaut testés")
        static let credsNotTested = t("audit.creds.not_tested", "Aucun port web — identifiants non testés")
    }

    // MARK: - Actions sur le panneau détail
    enum DetailActions {
        static let sectionTitle  = t("detail.actions.section",        "ACTIONS")
        static let scanPorts     = t("detail.actions.scan_ports",     "Scanner les ports")
        static let enrich        = t("detail.actions.enrich",         "Enrichir")
        static let checkVuln     = t("detail.actions.check_vuln",     "Vulnérabilités")
        static let running       = t("detail.actions.running",        "En cours…")
        // Hints accessibilité
        static let scanPortsHint = t("detail.actions.scan_ports.hint",
                                     "Scanne tous les ports communs de cet appareil.")
        static let enrichHint    = t("detail.actions.enrich.hint",
                                     "Récupère OS, nom Bonjour, NetBIOS, bannière HTTP et latence.")
        static let checkVulnHint = t("detail.actions.check_vuln.hint",
                                     "Analyse les vulnérabilités à partir des ports déjà scannés.")
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
        static let appletv   = t("device.type.appletv",  "Apple TV / HomePod")
        static let iot       = t("device.type.iot",      "Objet connecté")
        static let gaming    = t("device.type.gaming",   "Console")
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

    // MARK: - Historique des scans
    enum History {
        static let tabNetwork    = t("history.tab.network",   "Réseau")
        static let tabHistory    = t("history.tab.history",   "Historique")
        static let empty         = t("history.empty",         "Aucun scan enregistré.\nLancez un scan pour commencer.")
        static let devices       = t("history.devices",       "appareils")
        static let alerts        = t("history.alerts",        "alertes")
        static let newDevices    = t("history.new_devices",   "nouveaux")
        static let delete        = t("history.delete",        "Supprimer")
        static func duration(_ s: Double) -> String {
            s < 60
                ? t("history.duration.seconds", "%.0f s", s)
                : t("history.duration.minutes", "%.1f min", s / 60)
        }
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

    // MARK: - Portée réseau (deviceIP sentinelle des alertes globales)
    enum Scope {
        static let network = t("scope.network", "Réseau")
        static let wifi    = t("scope.wifi",    "WiFi")
    }

    // MARK: - Raisons de risque des ports (PortScanner.CommonPort)
    enum Port {
        static let ftp             = t("port.risk.ftp",               "Transfert de fichiers non chiffré")
        static let telnet          = t("port.risk.telnet",            "Protocole non chiffré (obsolète)")
        static let http            = t("port.risk.http",              "Trafic web non chiffré")
        static let pop3            = t("port.risk.pop3",              "Mail non chiffré")
        static let msrpc           = t("port.risk.msrpc",             "Windows RPC exposé")
        static let netbios         = t("port.risk.netbios",           "Partage réseau Windows non sécurisé")
        static let snmp            = t("port.risk.snmp",              "Peut exposer des infos système")
        static let smb             = t("port.risk.smb",               "Partage Windows (cible ransomwares)")
        static let rtsp            = t("port.risk.rtsp",              "Caméra/stream non sécurisé")
        static let dbExposed       = t("port.risk.db_exposed",        "Base de données exposée")
        static let pptp            = t("port.risk.pptp",              "VPN obsolète et cassé")
        static let nfs             = t("port.risk.nfs",               "Partage de fichiers réseau")
        static let rdp             = t("port.risk.rdp",               "Bureau distant exposé")
        static let upnp            = t("port.risk.upnp",              "Service UPnP exposé")
        static let vnc             = t("port.risk.vnc",               "Bureau distant non chiffré")
        static let winrm           = t("port.risk.winrm",             "Gestion Windows non chiffrée")
        static let httpAlt         = t("port.risk.http_alt",          "Interface admin non sécurisée")
        static let httpProxy       = t("port.risk.http_proxy",        "Proxy ou service non chiffré")
        static let dbExposedNoAuth = t("port.risk.db_exposed_noauth", "Base de données exposée sans auth")
    }

    // MARK: - Alertes de vulnérabilités (VulnerabilityChecker)
    enum Vuln {
        // Progression
        static let progressAnalyzing = t("vuln.progress.analyzing", "Analyse des vulnérabilités…")
        static func progressChecking(_ ip: String) -> String { t("vuln.progress.checking", "Vérification %@…", ip) }
        static let progressWifi      = t("vuln.progress.wifi",      "Analyse sécurité WiFi…")
        static let progressUnknown   = t("vuln.progress.unknown",   "Détection appareils inconnus…")
        static let progressConfig    = t("vuln.progress.config",    "Vérification configuration…")
        static let progressDone      = t("vuln.progress.done",      "Analyse terminée")
        // Ports
        static func portOpenTitle(_ port: Int, _ service: String) -> String { t("vuln.port.title", "Port %1$d ouvert (%2$@)", port, service) }
        static func onDevice(_ ip: String, _ notes: String) -> String { t("vuln.on_device", "Sur %1$@ — %2$@", ip, notes) }
        // Telnet
        static let telnetTitle = t("vuln.telnet.title", "Telnet actif — protocole non chiffré")
        static func telnetDesc(_ ip: String) -> String { t("vuln.telnet.desc", "Sur %@ — Toutes les communications sont en clair", ip) }
        static let telnetReco  = t("vuln.telnet.reco",  "Désactiver Telnet et utiliser SSH (port 22) à la place")
        // VNC
        static let vncTitle = t("vuln.vnc.title", "VNC exposé — bureau distant")
        static func vncDesc(_ ip: String) -> String { t("vuln.vnc.desc", "Sur %@ — Accès bureau à distance potentiellement non sécurisé", ip) }
        static let vncReco  = t("vuln.vnc.reco",  "Protéger VNC par un mot de passe fort ou utiliser SSH tunneling")
        // Base de données exposée
        static func dbTitle(_ service: String) -> String { t("vuln.db.title", "%@ exposé sur le réseau", service) }
        static func dbDesc(_ ip: String) -> String { t("vuln.db.desc", "Sur %@ — Base de données accessible depuis le réseau local", ip) }
        static func dbReco(_ service: String) -> String { t("vuln.db.reco", "Limiter l'accès à %@ à 127.0.0.1 uniquement (bind-address)", service) }
        // Certificat
        static let certExpiredTitle = t("vuln.cert.expired.title", "Certificat SSL expiré")
        static func certExpiredDesc(_ ip: String, _ date: String) -> String { t("vuln.cert.expired.desc", "Sur %1$@ — Expiré le %2$@", ip, date) }
        static let certExpiredReco  = t("vuln.cert.expired.reco", "Renouveler le certificat du service web. Un certificat expiré rend les communications vulnérables.")
        static let certNearTitle = t("vuln.cert.near.title", "Certificat SSL bientôt expiré")
        static func certNearDesc(_ ip: String, _ days: Int) -> String { t("vuln.cert.near.desc", "Sur %1$@ — Expire dans %2$d jour(s)", ip, days) }
        static let certNearReco  = t("vuln.cert.near.reco", "Planifier le renouvellement du certificat avant expiration.")
        static let certSelfTitle = t("vuln.cert.self.title", "Certificat SSL auto-signé")
        static func certSelfDesc(_ ip: String) -> String { t("vuln.cert.self.desc", "Sur %@ — Le certificat n'est pas signé par une autorité reconnue", ip) }
        static let certSelfReco  = t("vuln.cert.self.reco", "Utiliser un certificat émis par Let's Encrypt ou installer le certificat racine sur les clients de confiance.")
        static let certInvalidTitle = t("vuln.cert.invalid.title", "Certificat SSL invalide")
        static func certInvalidDesc(_ ip: String, _ reason: String) -> String { t("vuln.cert.invalid.desc", "Sur %1$@ — %2$@", ip, reason) }
        static let certInvalidReco  = t("vuln.cert.invalid.reco", "Vérifier la configuration TLS du service. Le certificat n'est pas accepté par les clients standards.")
        static let certReasonUnknown = t("vuln.cert.reason_unknown", "raison inconnue")
        // WiFi
        static let wepTitle = t("vuln.wifi.wep.title", "Chiffrement WEP détecté")
        static func wepDesc(_ ssid: String) -> String { t("vuln.wifi.wep.desc", "Réseau « %@ » — WEP est cassé et ne protège plus vos données", ssid) }
        static let wepReco  = t("vuln.wifi.wep.reco", "Passer immédiatement à WPA2 ou WPA3 dans les paramètres du routeur")
        static let openTitle = t("vuln.wifi.open.title", "Réseau WiFi ouvert (sans mot de passe)")
        static func openDesc(_ ssid: String) -> String { t("vuln.wifi.open.desc", "Réseau « %@ » — Aucun chiffrement actif", ssid) }
        static let openReco  = t("vuln.wifi.open.reco", "Activer WPA3 ou WPA2 avec un mot de passe fort")
        static let wpa1Title = t("vuln.wifi.wpa1.title", "Chiffrement WPA (v1) obsolète")
        static func wpa1Desc(_ ssid: String) -> String { t("vuln.wifi.wpa1.desc", "Réseau « %@ » — WPA v1 est vulnérable", ssid) }
        static let wpa1Reco  = t("vuln.wifi.wpa1.reco", "Passer à WPA2 ou WPA3")
        static func weakSignalTitle(_ rssi: Int) -> String { t("vuln.wifi.weak.title", "Signal WiFi très faible (%d dBm)", rssi) }
        static func weakSignalDesc(_ ssid: String) -> String { t("vuln.wifi.weak.desc", "Réseau « %@ » — Signal faible, risque de déconnexion", ssid) }
        static let weakSignalReco  = t("vuln.wifi.weak.reco", "Rapprocher le routeur ou ajouter un point d'accès")
        // Appareil inconnu
        static let unknownTitle = t("vuln.unknown.title", "Appareil non identifié")
        static func unknownDesc(_ ip: String, _ mac: String) -> String { t("vuln.unknown.desc", "IP %1$@ — MAC : %2$@ — Aucun fournisseur reconnu", ip, mac) }
        static let unknownMac   = t("vuln.unknown.mac", "inconnu")
        static let unknownReco  = t("vuln.unknown.reco", "Vérifier l'appareil dans les logs du routeur et bloquer si non reconnu")
        // Configuration réseau
        static func manyRiskyTitle(_ count: Int) -> String { t("vuln.config.many_risky.title", "%d appareils avec ports vulnérables", count) }
        static let manyRiskyDesc = t("vuln.config.many_risky.desc", "Plusieurs appareils exposent des services non sécurisés")
        static let manyRiskyReco = t("vuln.config.many_risky.reco", "Activer le firewall sur chaque appareil et fermer les services inutilisés")
        static func manyDevicesTitle(_ count: Int) -> String { t("vuln.config.many_devices.title", "%d appareils détectés", count) }
        static let manyDevicesDesc = t("vuln.config.many_devices.desc", "Nombre élevé d'appareils sur le réseau")
        static let manyDevicesReco = t("vuln.config.many_devices.reco", "Segmenter le réseau avec des VLANs pour isoler les appareils IoT")
        // Recommandations par port
        static let recoFtp     = t("vuln.reco.ftp",     "Utiliser SFTP ou FTPS à la place de FTP")
        static let recoTelnet  = t("vuln.reco.telnet",  "Désactiver Telnet, utiliser SSH")
        static let recoHttp    = t("vuln.reco.http",    "Rediriger HTTP vers HTTPS")
        static let recoSmb     = t("vuln.reco.smb",     "Désactiver le partage SMB/NetBIOS si non nécessaire")
        static let recoSnmp    = t("vuln.reco.snmp",    "Désactiver SNMP ou utiliser SNMPv3 avec authentification")
        static let recoRdp     = t("vuln.reco.rdp",     "Restreindre RDP à un VPN uniquement")
        static let recoVnc     = t("vuln.reco.vnc",     "Désactiver VNC ou utiliser un tunnel SSH")
        static let recoMysql   = t("vuln.reco.mysql",   "Restreindre MySQL à localhost uniquement")
        static let recoMongo   = t("vuln.reco.mongo",   "Activer l'authentification MongoDB")
        static let recoElastic = t("vuln.reco.elastic", "Restreindre Elasticsearch avec un firewall")
        static let recoPptp    = t("vuln.reco.pptp",    "Remplacer PPTP par WireGuard ou OpenVPN")
        static let recoDefault = t("vuln.reco.default", "Désactiver ce service s'il n'est pas nécessaire")
    }

    // MARK: - Findings de l'audit de sécurité (SecurityAuditor)
    enum AuditFinding {
        static let telnetTitle  = t("af.telnet.title",  "Telnet détecté (port 23)")
        static let telnetDetail = t("af.telnet.detail", "Protocole non chiffré — toutes les communications transitent en clair.")
        static let ftpTitle     = t("af.ftp.title",     "FTP non chiffré (port 21)")
        static let ftpDetail    = t("af.ftp.detail",    "Préférer SFTP sur le port 22.")
        static let httpTitle    = t("af.http.title",    "Interface web non chiffrée (port 80)")
        static let httpDetail   = t("af.http.detail",   "Les identifiants et données transitent en clair.")
        static let certExpiredTitle  = t("af.cert.expired.title",  "Certificat SSL expiré")
        static let certExpiredDetail = t("af.cert.expired.detail", "Les connexions HTTPS ne sont plus sécurisées.")
        static let certSelfTitle  = t("af.cert.self.title",  "Certificat auto-signé")
        static let certSelfDetail = t("af.cert.self.detail", "Impossible de vérifier l'authenticité du serveur.")
        static func manyPortsTitle(_ count: Int) -> String { t("af.many_ports.title", "%d ports ouverts", count) }
        static let manyPortsDetail = t("af.many_ports.detail", "Réduire la surface d'attaque en fermant les services inutilisés.")
        static let unknownTitle  = t("af.unknown.title",  "Appareil non identifié")
        static let unknownDetail = t("af.unknown.detail", "Vérifier manuellement l'origine de cet appareil.")
        static let defaultCredsTitle = t("af.creds.title", "Identifiants par défaut actifs")
        static func defaultCredsDetail(_ user: String) -> String { t("af.creds.detail", "Login « %@ » accepté avec un mot de passe par défaut. Changez les identifiants immédiatement.", user) }
        static let noVulnTitle  = t("af.none.title",  "Aucune vulnérabilité détectée")
        static let noVulnDetail = t("af.none.detail", "L'appareil semble correctement configuré.")
    }

    // MARK: - Statut & progression du scan (AppState, NetworkScanner, DeviceEnricher, ScanResult)
    enum Scan {
        static let statusReady = t("scan.status.ready", "Prêt")
        static func statusDone(_ seconds: Double) -> String { t("scan.status.done", "Scan terminé en %.1fs", seconds) }
        static func statusError(_ msg: String) -> String { t("scan.status.error", "Erreur : %@", msg) }
        static let noInterface     = t("scan.no_interface",        "Aucune interface réseau active")
        static let progressNetInfo = t("scan.progress.net_info",   "Récupération des informations réseau…")
        static let quickScan       = t("scan.progress.quick",      "Scan rapide…")
        static let bonjourDiscovering = t("scan.progress.bonjour",      "Découverte des services Bonjour…")
        static let bonjourDone        = t("scan.progress.bonjour_done", "Services Bonjour découverts")
        static let analysisDone    = t("scan.progress.analysis_done", "Analyse terminée")
        // NetworkScanner
        static let arpRead          = t("scan.progress.arp_read",          "Lecture table ARP…")
        static let resolveNames     = t("scan.progress.resolve_names",     "Résolution noms d'hôtes…")
        static func pingSweep(_ from: Int, _ to: Int) -> String { t("scan.progress.ping_sweep", "Ping sweep %1$d–%2$d…", from, to) }
        static let ssdp             = t("scan.progress.ssdp",              "Découverte UPnP/SSDP…")
        static let arpUpdate        = t("scan.progress.arp_update",        "Mise à jour table ARP…")
        static let resolveHostnames = t("scan.progress.resolve_hostnames", "Résolution hostnames…")
        static let buildMap         = t("scan.progress.build_map",         "Construction de la carte réseau…")
        static let discoveryDone    = t("scan.progress.discovery_done",    "Découverte terminée")
        // PortScanner
        static func portsSweep(_ from: Int, _ to: Int) -> String { t("scan.progress.ports_sweep", "Scan ports %1$d–%2$d…", from, to) }
        static func portsHost(_ ip: String) -> String { t("scan.progress.ports_host", "Scan ports : %@…", ip) }
        static let portsDone = t("scan.progress.ports_done", "Scan des ports terminé")
    }

    // MARK: - Détection d'intrusion (nouveaux appareils — alerte + notification)
    enum Intrusion {
        static let title = t("intrusion.title", "Nouvel appareil détecté")
        static func description(_ name: String, _ ip: String) -> String { t("intrusion.desc", "%1$@ (%2$@) apparaît pour la première fois sur ce réseau.", name, ip) }
        static let recommendation = t("intrusion.reco", "Vérifiez que cet appareil est autorisé sur votre réseau.")
        static func notifMultiple(_ count: Int) -> String { t("intrusion.notif.multiple", "%d nouveaux appareils détectés", count) }
    }

    // MARK: - Sécurité WiFi (NetworkInfoService) — libellés affichés
    enum WifiSecurity {
        static let open    = t("wifi.sec.open",    "Ouvert")
        static let wep     = t("wifi.sec.wep",     "WEP (obsolète)")
        static let unknown = t("wifi.sec.unknown", "Inconnu")
    }
}
