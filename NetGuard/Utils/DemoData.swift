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
                OpenPort(port: 80,  service: "HTTP",  notes: "Admin interface"),
                OpenPort(port: 443, service: "HTTPS", notes: "Admin interface (SSL)"),
                OpenPort(port: 53,  service: "DNS",   notes: "Local resolver")
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
            mdnsName: "Thomas's MacBook Pro",
            vendor: "Apple Inc.",
            type: .mac,
            status: .safe,
            openPorts: [
                OpenPort(port: 22,   service: "SSH",        notes: "Remote sharing enabled"),
                OpenPort(port: 5000, service: "AirPlay",    notes: "AirPlay receiver")
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
            mdnsName: "Sophie's MacBook Air",
            vendor: "Apple Inc.",
            type: .mac,
            status: .safe,
            openPorts: [
                OpenPort(port: 5000, service: "AirPlay", notes: "AirPlay receiver")
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
            mdnsName: "Thomas's iPhone 15 Pro",
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
        d.userNote = "Primary iPhone"
        return d
    }()

    // MARK: iPhone SE

    private static let iphoneSE: NetworkDevice = {
        let d = NetworkDevice(
            ip: "192.168.1.12",
            mac: "DA:F3:88:0C:21:44",
            hostname: "iPhone-de-Sophie.local",
            mdnsName: "Sophie's iPhone SE",
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
                OpenPort(port: 7000, service: "AirPlay",   notes: "AirPlay receiver"),
                OpenPort(port: 49152, service: "HomeKit",  notes: "HomeKit bridge")
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
            mdnsName: "HomePod mini — Living Room",
            vendor: "Apple Inc.",
            type: .iot,
            status: .safe,
            openPorts: [
                OpenPort(port: 7000, service: "AirPlay", notes: "AirPlay audio receiver")
            ],
            isCurrentDevice: false,
            responseTime: 1.9,
            ttl: 64,
            osGuess: .ios,
            bonjourServices: ["_airplay._tcp.", "_raop._tcp.", "_homekit._tcp."]
        )
        d.userNote = "Living room — music"
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
            trustErrorDescription: "The certificate is self-signed and is not trusted by a recognized certificate authority."
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
                OpenPort(port: 22,   service: "SSH",   notes: "SSH administration"),
                OpenPort(port: 80,   service: "HTTP",  notes: "DSM (redirects to 5001)"),
                OpenPort(port: 443,  service: "HTTPS", notes: "DSM (secure)"),
                OpenPort(port: 5000, service: "DSM",   notes: "DiskStation Manager"),
                OpenPort(port: 5001, service: "DSM",   notes: "DiskStation Manager (HTTPS)"),
                OpenPort(port: 139,  service: "SMB",   notes: "File sharing"),
                OpenPort(port: 445,  service: "SMB",   notes: "File sharing"),
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
        d.userNote = "Photo storage + Time Machine backups"
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
                OpenPort(port: 21,   service: "FTP",       isVulnerable: true,  notes: "FTP enabled — not recommended"),
                OpenPort(port: 80,   service: "HTTP",      notes: "Printer web interface"),
                OpenPort(port: 443,  service: "HTTPS",     notes: "Secure web interface"),
                OpenPort(port: 9100, service: "RAW Print", notes: "Direct network printing")
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
                OpenPort(port: 8080, service: "HTTP Alt",   notes: "SmartTV API"),
                OpenPort(port: 8443, service: "HTTPS Alt",  notes: "SmartTV API (secure)"),
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
            mdnsName: "Thomas's PS5",
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
                friendlyName: "Thomas's PS5",
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
                OpenPort(port: 80,  service: "HTTP",  notes: "Local Hue API (CLIP)"),
                OpenPort(port: 443, service: "HTTPS", notes: "Local Hue API (CLIP v2)")
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
                OpenPort(port: 55443, service: "Alexa",     notes: "Alexa service")
            ],
            isCurrentDevice: false,
            responseTime: 7.1,
            ttl: 64,
            osGuess: .linux
        )
        d.userNote = "Kitchen"
        return d
    }()

    // MARK: Chromecast

    private static let chromecast: NetworkDevice = {
        let d = NetworkDevice(
            ip: "192.168.1.72",
            mac: "54:60:09:C1:33:EE",
            hostname: "Chromecast.local",
            mdnsName: "Chromecast — Bedroom",
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
                OpenPort(port: 139,  service: "NetBIOS",  notes: "Network sharing"),
                OpenPort(port: 445,  service: "SMB",      notes: "File sharing"),
                OpenPort(port: 3389, service: "RDP",      isVulnerable: true, notes: "Remote desktop exposed"),
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
                OpenPort(port: 23,  service: "Telnet", isVulnerable: true,  notes: "Insecure Telnet access"),
                OpenPort(port: 80,  service: "HTTP",   notes: "Configuration interface"),
                OpenPort(port: 1883, service: "MQTT",  notes: "MQTT broker")
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
                OpenPort(port: 22,  service: "SSH",   notes: "SSH administration"),
                OpenPort(port: 53,  service: "DNS",   notes: "Pi-hole — DNS filtering"),
                OpenPort(port: 80,  service: "HTTP",  notes: "Pi-hole interface"),
                OpenPort(port: 4711, service: "FTL",  notes: "Faster Than Light — Pi-hole API")
            ],
            isCurrentDevice: false,
            responseTime: 2.3,
            ttl: 64,
            osGuess: .linux,
            httpBanner: "lighttpd/1.4.69",
            httpTitle: "Pi-hole — Admin"
        )
        d.userNote = "Pi-hole — ad blocker"
        return d
    }()

    // MARK: - Alerts

    static var alerts: [NetworkAlert] {
        [
            NetworkAlert(
                severity: .critical,
                category: .openPort,
                title: "Telnet open — 192.168.1.90",
                description: "Port 23 (Telnet) is open on the Espressif device esp32-sensor-01. Telnet transmits data in cleartext, including passwords.",
                deviceIP: "192.168.1.90",
                recommendation: "Disable Telnet and use SSH instead. On ESP-IDF firmware, disable the console_telnet component."
            ),
            NetworkAlert(
                severity: .high,
                category: .openPort,
                title: "RDP exposed — 192.168.1.80",
                description: "Port 3389 (Remote Desktop Protocol) is open on DESKTOP-GAMING. RDP is a frequent target of brute-force attacks on local networks.",
                deviceIP: "192.168.1.80",
                recommendation: "Disable RDP if unused (Settings → System → Remote Desktop). Otherwise, enable NLA authentication and restrict access with a firewall."
            ),
            NetworkAlert(
                severity: .high,
                category: .openPort,
                title: "FTP open — 192.168.1.40",
                description: "Port 21 (FTP) is open on the HP LaserJet Pro M404dn printer. FTP transmits files without encryption.",
                deviceIP: "192.168.1.40",
                recommendation: "Disable FTP in the printer's web interface. Prefer printing via IPP/IPPS (port 631)."
            ),
            NetworkAlert(
                severity: .medium,
                category: .certificate,
                title: "Self-signed certificate — 192.168.1.30",
                description: "The Synology DS923+ NAS uses a self-signed SSL certificate for HTTPS. The connection is encrypted, but the server's identity cannot be verified.",
                deviceIP: "192.168.1.30",
                recommendation: "In DSM → Control Panel → Security → Certificate, request a free Let's Encrypt certificate if the NAS is reachable from outside."
            ),
            NetworkAlert(
                severity: .low,
                category: .unknownDevice,
                title: "Unidentified device — 192.168.1.90",
                description: "An Espressif device (ESP32/ESP8266 firmware) is connected to the network but has no hostname configured. Its role is unknown.",
                deviceIP: "192.168.1.90",
                recommendation: "Identify this device by visiting its web interface (http://192.168.1.90). If unrecognized, block it from your router's interface."
            ),
            NetworkAlert(
                severity: .info,
                category: .configuration,
                title: "NAS — 7 open ports",
                description: "The Synology DS923+ exposes 7 ports (SSH, HTTP, HTTPS, DSM, SMB×2). Each open port increases the potential attack surface.",
                deviceIP: "192.168.1.30",
                recommendation: "Disable unused services in DSM → Control Panel → File Services."
            )
        ]
    }

    // MARK: - Audit Results

    static var auditResults: [String: (score: Int, findings: [(severity: AlertSeverity, title: String, detail: String)])] {
        [
            "192.168.1.90": (
                score: 35,
                findings: [
                    (.critical, "Telnet active (port 23)", "Telnet transmits data in cleartext. An attacker on the local network can capture the traffic, including credentials."),
                    (.medium,   "HTTP without HTTPS (port 80)", "The configuration interface is reachable over unencrypted HTTP. Submitted settings can be intercepted."),
                    (.low,      "Unknown device type", "The device has no clearly identified type, making risk assessment harder.")
                ]
            ),
            "192.168.1.80": (
                score: 55,
                findings: [
                    (.high,   "RDP exposed (port 3389)", "Windows Remote Desktop is enabled and exposed on the local network. A classic target for brute-force attacks."),
                    (.medium, "Outdated SMB version detected", "Ports 139 and 445 are open. SMBv1 has known vulnerabilities (EternalBlue / WannaCry)."),
                    (.low,    "Several Windows ports exposed", "NetBIOS (139), SMB (445), and RPC (135) increase this machine's attack surface.")
                ]
            ),
            "192.168.1.40": (
                score: 70,
                findings: [
                    (.high,   "FTP enabled (port 21)", "The FTP protocol transmits files and credentials in cleartext over the network."),
                    (.low,    "HTTP with no HTTPS redirect", "The printer's web interface is reachable over unencrypted HTTP.")
                ]
            ),
            "192.168.1.30": (
                score: 78,
                findings: [
                    (.medium, "Self-signed SSL certificate", "The HTTPS certificate is self-signed. The connection is encrypted, but the server's identity cannot be verified by a trusted third party."),
                    (.low,    "7 open ports", "The number of exposed ports (22, 80, 443, 5000, 5001, 139, 445) increases the NAS's attack surface.")
                ]
            )
        ]
    }
}
#endif
