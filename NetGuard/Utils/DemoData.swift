#if DEBUG
import Foundation

// MARK: - DemoData
/// Réseau fictif pour screenshots / démos — aucune donnée réelle.
/// Activé via le menu Debug → "Charger le réseau démo".
/// Compilé en build DEBUG uniquement.
enum DemoData {

    // MARK: - NetworkInfo

    static let networkInfo = NetworkInfo(
        interfaceName: "en0",
        interfaceType: "WiFi",
        localIP: "192.168.1.10",
        gateway: "192.168.1.1",
        subnet: "255.255.255.0",
        dns: ["1.1.1.1", "8.8.8.8"],
        macAddress: "A4:CF:99:1B:3E:52",
        wifiInfo: WiFiSecurityInfo(
            ssid: "Maison_5G",
            bssid: "C4:AD:34:9F:12:01",
            security: "WPA3",
            channel: 100,
            rssi: -48,
            isSecure: true
        )
    )

    // MARK: - Devices

    static var devices: [NetworkDevice] {
        [
            router,
            macBookPro,
            macBookAir,
            iphone15Pro,
            iphoneSE,
            ipadPro,
            appleTv4K,
            homePodMini,
            nasDS923,
            hpPrinter,
            samsungTV,
            ps5,
            huebridge,
            amazonEcho,
            chromecast,
            windowsPC,
            esp32Unknown,
            raspberryPi
        ]
    }

    // MARK: Routeur

    private static let router: NetworkDevice = {
        let d = NetworkDevice(
            ip: "192.168.1.1",
            mac: "C4:AD:34:9F:12:01",
            hostname: "routeur.local",
            mdnsName: "NETGEAR-Orbi",
            vendor: "NETGEAR",
            type: .router,
            status: .safe,
            openPorts: [
                OpenPort(port: 80,  service: "HTTP",  notes: "Interface d'admin"),
                OpenPort(port: 443, service: "HTTPS", notes: "Interface d'admin (SSL)"),
                OpenPort(port: 53,  service: "DNS",   notes: "Résolveur local")
            ],
            isCurrentDevice: false,
            responseTime: 1.2,
            ttl: 64,
            osGuess: .router,
            httpBanner: "Netgear/1.0",
            httpTitle: "NETGEAR Orbi",
            bonjourServices: ["_http._tcp."],
            upnp: UPnPInfo(
                friendlyName: "Orbi Router (RBR850)",
                modelName: "RBR850",
                manufacturer: "NETGEAR",
                deviceType: "urn:schemas-upnp-org:device:InternetGatewayDevice:2",
                server: "UPnP/2.0 MiniUPnPd/2.3.5"
            )
        )
        return d
    }()

    // MARK: MacBook Pro (appareil courant)

    private static let macBookPro: NetworkDevice = {
        let d = NetworkDevice(
            ip: "192.168.1.10",
            mac: "A4:CF:99:1B:3E:52",
            hostname: "MacBook-Pro-de-Thomas.local",
            mdnsName: "MacBook Pro de Thomas",
            vendor: "Apple Inc.",
            type: .mac,
            status: .safe,
            openPorts: [
                OpenPort(port: 22,   service: "SSH",        notes: "Partage à distance actif"),
                OpenPort(port: 5000, service: "AirPlay",    notes: "Réception AirPlay")
            ],
            isCurrentDevice: true,
            responseTime: 0.4,
            ttl: 64,
            osGuess: .macOS,
            bonjourServices: ["_ssh._tcp.", "_airplay._tcp.", "_companion-link._tcp."]
        )
        return d
    }()

    // MARK: MacBook Air

    private static let macBookAir: NetworkDevice = {
        let d = NetworkDevice(
            ip: "192.168.1.14",
            mac: "F8:FF:C2:44:A1:09",
            hostname: "MacBook-Air-de-Sophie.local",
            mdnsName: "MacBook Air de Sophie",
            vendor: "Apple Inc.",
            type: .mac,
            status: .safe,
            openPorts: [
                OpenPort(port: 5000, service: "AirPlay", notes: "Réception AirPlay")
            ],
            isCurrentDevice: false,
            responseTime: 2.1,
            ttl: 64,
            osGuess: .macOS,
            bonjourServices: ["_airplay._tcp.", "_companion-link._tcp."]
        )
        return d
    }()

    // MARK: iPhone 15 Pro

    private static let iphone15Pro: NetworkDevice = {
        let d = NetworkDevice(
            ip: "192.168.1.11",
            mac: "BE:D4:12:7A:33:F1",
            hostname: "iPhone-de-Thomas.local",
            mdnsName: "iPhone 15 Pro de Thomas",
            vendor: "Apple Inc.",
            type: .iphone,
            status: .safe,
            openPorts: [],
            isCurrentDevice: false,
            responseTime: 3.8,
            ttl: 64,
            osGuess: .ios,
            bonjourServices: ["_companion-link._tcp.", "_homekit._tcp."]
        )
        d.userNote = "iPhone principal"
        return d
    }()

    // MARK: iPhone SE

    private static let iphoneSE: NetworkDevice = {
        let d = NetworkDevice(
            ip: "192.168.1.12",
            mac: "DA:F3:88:0C:21:44",
            hostname: "iPhone-de-Sophie.local",
            mdnsName: "iPhone SE de Sophie",
            vendor: "Apple Inc.",
            type: .iphone,
            status: .safe,
            openPorts: [],
            isCurrentDevice: false,
            responseTime: 5.2,
            ttl: 64,
            osGuess: .ios,
            bonjourServices: ["_companion-link._tcp."]
        )
        return d
    }()

    // MARK: iPad Pro

    private static let ipadPro: NetworkDevice = {
        let d = NetworkDevice(
            ip: "192.168.1.13",
            mac: "C2:A1:F9:03:7B:DE",
            hostname: "iPad-Pro.local",
            mdnsName: "iPad Pro 12,9\"",
            vendor: "Apple Inc.",
            type: .ipad,
            status: .safe,
            openPorts: [],
            isCurrentDevice: false,
            responseTime: 4.1,
            ttl: 64,
            osGuess: .ios,
            bonjourServices: ["_companion-link._tcp.", "_airplay._tcp."]
        )
        return d
    }()

    // MARK: Apple TV 4K

    private static let appleTv4K: NetworkDevice = {
        let d = NetworkDevice(
            ip: "192.168.1.20",
            mac: "98:10:E8:AB:CD:34",
            hostname: "Apple-TV.local",
            mdnsName: "Apple TV 4K",
            vendor: "Apple Inc.",
            type: .appletv,
            status: .safe,
            openPorts: [
                OpenPort(port: 7000, service: "AirPlay",   notes: "Réception AirPlay"),
                OpenPort(port: 49152, service: "HomeKit",  notes: "Pont HomeKit")
            ],
            isCurrentDevice: false,
            responseTime: 2.7,
            ttl: 64,
            osGuess: .ios,
            bonjourServices: ["_airplay._tcp.", "_raop._tcp.", "_homekit._tcp."]
        )
        return d
    }()

    // MARK: HomePod mini

    private static let homePodMini: NetworkDevice = {
        let d = NetworkDevice(
            ip: "192.168.1.21",
            mac: "3C:06:30:FF:AA:11",
            hostname: "HomePod-mini.local",
            mdnsName: "HomePod mini — Salon",
            vendor: "Apple Inc.",
            type: .iot,
            status: .safe,
            openPorts: [
                OpenPort(port: 7000, service: "AirPlay", notes: "Réception AirPlay audio")
            ],
            isCurrentDevice: false,
            responseTime: 1.9,
            ttl: 64,
            osGuess: .ios,
            bonjourServices: ["_airplay._tcp.", "_raop._tcp.", "_homekit._tcp."]
        )
        d.userNote = "Salon — musique"
        return d
    }()

    // MARK: NAS Synology DS923+

    private static let nasDS923: NetworkDevice = {
        let cert = CertificateInfo(
            subject: "DiskStation",
            issuer: "DiskStation",
            validFrom: Calendar.current.date(byAdding: .year, value: -1, to: Date())!,
            validTo: Calendar.current.date(byAdding: .month, value: 8, to: Date())!,
            isSelfSigned: true,
            isExpired: false,
            isTrusted: false,
            trustErrorDescription: "Le certificat est auto-signé et n'est pas approuvé par une autorité de certification reconnue."
        )
        let d = NetworkDevice(
            ip: "192.168.1.30",
            mac: "00:11:32:A1:BC:44",
            hostname: "DiskStation.local",
            mdnsName: "DiskStation",
            vendor: "Synology Inc.",
            type: .nas,
            status: .alert,
            openPorts: [
                OpenPort(port: 22,   service: "SSH",   notes: "Administration SSH"),
                OpenPort(port: 80,   service: "HTTP",  notes: "DSM (redirection vers 5001)"),
                OpenPort(port: 443,  service: "HTTPS", notes: "DSM sécurisé"),
                OpenPort(port: 5000, service: "DSM",   notes: "DiskStation Manager"),
                OpenPort(port: 5001, service: "DSM",   notes: "DiskStation Manager (HTTPS)"),
                OpenPort(port: 139,  service: "SMB",   notes: "Partage de fichiers"),
                OpenPort(port: 445,  service: "SMB",   notes: "Partage de fichiers"),
            ],
            isCurrentDevice: false,
            responseTime: 1.1,
            ttl: 64,
            osGuess: .linux,
            httpBanner: "nginx",
            httpTitle: "DiskStation Manager",
            bonjourServices: ["_http._tcp.", "_ssh._tcp.", "_smb._tcp.", "_afpovertcp._tcp."],
            sslCertificate: cert,
            upnp: UPnPInfo(
                friendlyName: "Synology DS923+",
                modelName: "DS923+",
                manufacturer: "Synology Inc.",
                deviceType: "urn:schemas-upnp-org:device:MediaServer:1",
                server: "Linux/5.10 UPnP/1.0 Synology/1.0"
            )
        )
        d.userNote = "Stockage photos + backups Time Machine"
        return d
    }()

    // MARK: HP LaserJet Pro M404dn

    private static let hpPrinter: NetworkDevice = {
        let d = NetworkDevice(
            ip: "192.168.1.40",
            mac: "D8:9D:67:A3:12:CC",
            hostname: "HP-LaserJet-Pro.local",
            mdnsName: "HP LaserJet Pro M404dn",
            vendor: "HP Inc.",
            type: .printer,
            status: .alert,
            openPorts: [
                OpenPort(port: 21,   service: "FTP",       isVulnerable: true,  notes: "FTP activé — non recommandé"),
                OpenPort(port: 80,   service: "HTTP",      notes: "Interface web imprimante"),
                OpenPort(port: 443,  service: "HTTPS",     notes: "Interface web sécurisée"),
                OpenPort(port: 9100, service: "RAW Print", notes: "Impression réseau directe")
            ],
            isCurrentDevice: false,
            responseTime: 3.3,
            ttl: 60,
            osGuess: .unknown,
            httpBanner: "HP HTTP Server; HP LaserJet Pro M404dn",
            httpTitle: "HP LaserJet Pro M404dn",
            bonjourServices: ["_ipp._tcp.", "_printer._tcp.", "_http._tcp."]
        )
        return d
    }()

    // MARK: Samsung Smart TV

    private static let samsungTV: NetworkDevice = {
        let d = NetworkDevice(
            ip: "192.168.1.50",
            mac: "78:AB:BB:44:F1:09",
            hostname: "Samsung-TV.local",
            mdnsName: "",
            vendor: "Samsung Electronics Co., Ltd.",
            type: .iot,
            status: .unknown,
            openPorts: [
                OpenPort(port: 8080, service: "HTTP Alt",   notes: "API SmartTV"),
                OpenPort(port: 8443, service: "HTTPS Alt",  notes: "API SmartTV sécurisée"),
                OpenPort(port: 7676, service: "Samsung",    notes: "AllShare / DLNA")
            ],
            isCurrentDevice: false,
            responseTime: 6.4,
            ttl: 64,
            osGuess: .linux,
            upnp: UPnPInfo(
                friendlyName: "Samsung TV QN85A",
                modelName: "QN85A",
                manufacturer: "Samsung Electronics",
                deviceType: "urn:samsung.com:device:MainTVServer2:1",
                server: "SHP, UPnP/1.0, Samsung UPnP SDK/1.0"
            )
        )
        return d
    }()

    // MARK: PlayStation 5

    private static let ps5: NetworkDevice = {
        let d = NetworkDevice(
            ip: "192.168.1.60",
            mac: "BC:60:A7:91:44:2B",
            hostname: "PS5.local",
            mdnsName: "PS5-de-Thomas",
            vendor: "Sony Interactive Entertainment",
            type: .gaming,
            status: .safe,
            openPorts: [
                OpenPort(port: 9295, service: "PS Remote Play", notes: "Remote Play"),
                OpenPort(port: 9296, service: "PS Remote Play", notes: "Remote Play"),
                OpenPort(port: 9304, service: "PSN",            notes: "PlayStation Network")
            ],
            isCurrentDevice: false,
            responseTime: 4.0,
            ttl: 128,
            osGuess: .unknown,
            upnp: UPnPInfo(
                friendlyName: "PS5-de-Thomas",
                modelName: "PlayStation 5",
                manufacturer: "Sony Interactive Entertainment",
                deviceType: "urn:schemas-sony-com:device:SonyInteractiveEntertainment:1",
                server: nil
            )
        )
        return d
    }()

    // MARK: Philips Hue Bridge

    private static let huebridge: NetworkDevice = {
        let d = NetworkDevice(
            ip: "192.168.1.70",
            mac: "EC:B5:FA:12:44:90",
            hostname: "Philips-hue.local",
            mdnsName: "Philips hue",
            vendor: "Philips Lighting BV",
            type: .iot,
            status: .safe,
            openPorts: [
                OpenPort(port: 80,  service: "HTTP",  notes: "API locale Hue (CLIP)"),
                OpenPort(port: 443, service: "HTTPS", notes: "API locale Hue (CLIP v2)")
            ],
            isCurrentDevice: false,
            responseTime: 1.6,
            ttl: 64,
            osGuess: .linux,
            httpBanner: "nginx",
            httpTitle: "Philips hue",
            bonjourServices: ["_hap._tcp.", "_http._tcp."]
        )
        return d
    }()

    // MARK: Amazon Echo Dot

    private static let amazonEcho: NetworkDevice = {
        let d = NetworkDevice(
            ip: "192.168.1.71",
            mac: "44:65:0D:AB:12:F3",
            hostname: "Amazon-Echo-Dot.local",
            mdnsName: "",
            vendor: "Amazon Technologies Inc.",
            type: .iot,
            status: .safe,
            openPorts: [
                OpenPort(port: 4070, service: "Spotify",    notes: "Spotify Connect"),
                OpenPort(port: 55443, service: "Alexa",     notes: "Service Alexa")
            ],
            isCurrentDevice: false,
            responseTime: 7.1,
            ttl: 64,
            osGuess: .linux
        )
        d.userNote = "Cuisine"
        return d
    }()

    // MARK: Chromecast

    private static let chromecast: NetworkDevice = {
        let d = NetworkDevice(
            ip: "192.168.1.72",
            mac: "54:60:09:C1:33:EE",
            hostname: "Chromecast.local",
            mdnsName: "Chromecast — Chambre",
            vendor: "Google LLC",
            type: .iot,
            status: .safe,
            openPorts: [
                OpenPort(port: 8008, service: "Cast",  notes: "Google Cast"),
                OpenPort(port: 8009, service: "Cast",  notes: "Google Cast TLS")
            ],
            isCurrentDevice: false,
            responseTime: 2.9,
            ttl: 64,
            osGuess: .linux,
            bonjourServices: ["_googlecast._tcp."]
        )
        return d
    }()

    // MARK: PC Windows (gaming)

    private static let windowsPC: NetworkDevice = {
        let d = NetworkDevice(
            ip: "192.168.1.80",
            mac: "24:4B:FE:AA:09:31",
            hostname: "DESKTOP-GAMING.local",
            mdnsName: "",
            netbiosName: "DESKTOP-GAMING",
            vendor: "ASUSTeK COMPUTER INC.",
            type: .mac,       // computer générique
            status: .alert,
            openPorts: [
                OpenPort(port: 135,  service: "RPC",      notes: "Remote Procedure Call"),
                OpenPort(port: 139,  service: "NetBIOS",  notes: "Partage réseau"),
                OpenPort(port: 445,  service: "SMB",      notes: "Partage de fichiers"),
                OpenPort(port: 3389, service: "RDP",      isVulnerable: true, notes: "Bureau à distance exposé"),
                OpenPort(port: 10243, service: "WMP",     notes: "Windows Media Player")
            ],
            isCurrentDevice: false,
            responseTime: 3.5,
            ttl: 128,
            osGuess: .windows
        )
        return d
    }()

    // MARK: Appareil inconnu — ESP32

    private static let esp32Unknown: NetworkDevice = {
        let d = NetworkDevice(
            ip: "192.168.1.90",
            mac: "94:54:C5:07:A1:B2",
            hostname: "",
            mdnsName: "esp32-sensor-01",
            vendor: "Espressif Inc.",
            type: .iot,
            status: .alert,
            openPorts: [
                OpenPort(port: 23,  service: "Telnet", isVulnerable: true,  notes: "Accès Telnet non sécurisé"),
                OpenPort(port: 80,  service: "HTTP",   notes: "Interface de configuration"),
                OpenPort(port: 1883, service: "MQTT",  notes: "Broker MQTT")
            ],
            isCurrentDevice: false,
            responseTime: 8.2,
            ttl: 64,
            osGuess: .unknown,
            httpBanner: "ESP-IDF/5.1",
            httpTitle: "ESP32 Config"
        )
        return d
    }()

    // MARK: Raspberry Pi

    private static let raspberryPi: NetworkDevice = {
        let d = NetworkDevice(
            ip: "192.168.1.91",
            mac: "DC:A6:32:FF:12:03",
            hostname: "raspberrypi.local",
            mdnsName: "pi-hole",
            vendor: "Raspberry Pi Foundation",
            type: .iot,
            status: .safe,
            openPorts: [
                OpenPort(port: 22,  service: "SSH",   notes: "Administration SSH"),
                OpenPort(port: 53,  service: "DNS",   notes: "Pi-hole — filtrage DNS"),
                OpenPort(port: 80,  service: "HTTP",  notes: "Interface Pi-hole"),
                OpenPort(port: 4711, service: "FTL",  notes: "Faster Than Light — Pi-hole API")
            ],
            isCurrentDevice: false,
            responseTime: 2.3,
            ttl: 64,
            osGuess: .linux,
            httpBanner: "lighttpd/1.4.69",
            httpTitle: "Pi-hole — Admin"
        )
        d.userNote = "Pi-hole — bloqueur de pubs"
        return d
    }()

    // MARK: - Alerts

    static var alerts: [NetworkAlert] {
        [
            NetworkAlert(
                severity: .critical,
                category: .openPort,
                title: "Telnet ouvert — 192.168.1.90",
                description: "Le port 23 (Telnet) est ouvert sur l'appareil Espressif esp32-sensor-01. Telnet transmet les données en clair, y compris les mots de passe.",
                deviceIP: "192.168.1.90",
                recommendation: "Désactivez Telnet et utilisez SSH à la place. Sur un firmware ESP-IDF, désactivez le composant console_telnet."
            ),
            NetworkAlert(
                severity: .high,
                category: .openPort,
                title: "RDP exposé — 192.168.1.80",
                description: "Le port 3389 (Remote Desktop Protocol) est ouvert sur DESKTOP-GAMING. RDP est une cible fréquente d'attaques par force brute sur les réseaux locaux.",
                deviceIP: "192.168.1.80",
                recommendation: "Désactivez RDP si inutilisé (Paramètres → Système → Bureau à distance). Sinon, activez l'authentification NLA et limitez l'accès par pare-feu."
            ),
            NetworkAlert(
                severity: .high,
                category: .openPort,
                title: "FTP ouvert — 192.168.1.40",
                description: "Le port 21 (FTP) est ouvert sur l'imprimante HP LaserJet Pro M404dn. FTP transmet les fichiers sans chiffrement.",
                deviceIP: "192.168.1.40",
                recommendation: "Désactivez FTP dans l'interface web de l'imprimante. Préférez l'impression via IPP/IPPS (port 631)."
            ),
            NetworkAlert(
                severity: .medium,
                category: .certificate,
                title: "Certificat auto-signé — 192.168.1.30",
                description: "Le NAS Synology DS923+ utilise un certificat SSL auto-signé pour HTTPS. La connexion est chiffrée mais l'identité du serveur ne peut pas être vérifiée.",
                deviceIP: "192.168.1.30",
                recommendation: "Dans DSM → Panneau de configuration → Sécurité → Certificat, demandez un certificat Let's Encrypt gratuit si le NAS est accessible depuis l'extérieur."
            ),
            NetworkAlert(
                severity: .low,
                category: .unknownDevice,
                title: "Appareil non identifié — 192.168.1.90",
                description: "Un appareil Espressif (firmware ESP32/ESP8266) est connecté au réseau mais n'a pas de nom d'hôte configuré. Son rôle est inconnu.",
                deviceIP: "192.168.1.90",
                recommendation: "Identifiez cet appareil en accédant à son interface web (http://192.168.1.90). Si non reconnu, bloquez-le depuis l'interface de votre routeur."
            ),
            NetworkAlert(
                severity: .info,
                category: .configuration,
                title: "NAS — 7 ports ouverts",
                description: "Le Synology DS923+ expose 7 ports (SSH, HTTP, HTTPS, DSM, SMB×2). Chaque port ouvert augmente la surface d'attaque potentielle.",
                deviceIP: "192.168.1.30",
                recommendation: "Désactivez les services inutilisés dans DSM → Panneau de configuration → Services de fichiers."
            )
        ]
    }

    // MARK: - Audit Results

    static var auditResults: [String: (score: Int, findings: [(severity: AlertSeverity, title: String, detail: String)])] {
        [
            "192.168.1.90": (
                score: 35,
                findings: [
                    (.critical, "Telnet actif (port 23)", "Telnet transmet les données en clair. Un attaquant sur le réseau local peut capturer le trafic, y compris les identifiants."),
                    (.medium,   "HTTP sans HTTPS (port 80)", "L'interface de configuration est accessible en HTTP non chiffré. Les paramètres envoyés peuvent être interceptés."),
                    (.low,      "Type d'appareil inconnu", "L'appareil n'a pas de type clairement identifié, ce qui rend l'évaluation des risques plus difficile.")
                ]
            ),
            "192.168.1.80": (
                score: 55,
                findings: [
                    (.high,   "RDP exposé (port 3389)", "Le bureau à distance Windows est activé et exposé sur le réseau local. Cible classique des attaques par force brute."),
                    (.medium, "SMB version ancienne détectée", "Les ports 139 et 445 sont ouverts. SMBv1 présente des vulnérabilités connues (EternalBlue / WannaCry)."),
                    (.low,    "Plusieurs ports Windows exposés", "NetBIOS (139), SMB (445), RPC (135) augmentent la surface d'attaque de ce poste.")
                ]
            ),
            "192.168.1.40": (
                score: 70,
                findings: [
                    (.high,   "FTP activé (port 21)", "Le protocole FTP transmet les fichiers et les identifiants en clair sur le réseau."),
                    (.low,    "HTTP sans redirection HTTPS", "L'interface web de l'imprimante est accessible en HTTP non chiffré.")
                ]
            ),
            "192.168.1.30": (
                score: 78,
                findings: [
                    (.medium, "Certificat SSL auto-signé", "Le certificat HTTPS est auto-signé. La connexion est chiffrée mais l'identité du serveur n'est pas vérifiable par un tiers de confiance."),
                    (.low,    "7 ports ouverts", "Le nombre de ports exposés (22, 80, 443, 5000, 5001, 139, 445) augmente la surface d'attaque du NAS.")
                ]
            )
        ]
    }
}
#endif
