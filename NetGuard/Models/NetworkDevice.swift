import Foundation
import SwiftUI

// MARK: - Device Type
enum DeviceType: String, Codable, CaseIterable {
    // rawValues = identifiants stables pour Codable (ne pas changer)
    case router      = "router"
    case mac         = "mac"
    case iphone      = "iphone"
    case ipad        = "ipad"
    case nas         = "nas"
    case printer     = "printer"
    case wifi        = "wifi_ap"
    case firewall    = "firewall"
    case `switch`    = "switch"
    case unknown     = "unknown"
    case internet    = "internet"

    /// Nom affiché, localisé via L10n
    var localizedName: String {
        switch self {
        case .router:   return L10n.DeviceType.router
        case .mac:      return L10n.DeviceType.mac
        case .iphone:   return L10n.DeviceType.iphone
        case .ipad:     return L10n.DeviceType.ipad
        case .nas:      return L10n.DeviceType.nas
        case .printer:  return L10n.DeviceType.printer
        case .wifi:     return L10n.DeviceType.wifi
        case .firewall: return L10n.DeviceType.firewall
        case .switch:   return L10n.DeviceType.switch
        case .unknown:  return L10n.DeviceType.unknown
        case .internet: return L10n.DeviceType.internet
        }
    }

    var icon: String {
        switch self {
        case .router:   return "wifi.router.fill"
        case .mac:      return "desktopcomputer"
        case .iphone:   return "iphone"
        case .ipad:     return "ipad"
        case .nas:      return "externaldrive.fill"
        case .printer:  return "printer.fill"
        case .wifi:     return "wifi"
        case .firewall: return "shield.fill"
        case .switch:   return "network"
        case .unknown:  return "questionmark.circle.fill"
        case .internet: return "globe"
        }
    }

    var color: Color {
        switch self {
        case .router:   return .blue
        case .mac:      return .green
        case .iphone:   return .green
        case .ipad:     return .green
        case .nas:      return Color(red: 0.5, green: 0.8, blue: 1.0)
        case .printer:  return .orange
        case .firewall: return .purple
        case .wifi:     return .cyan
        case .switch:   return .teal
        case .unknown:  return .gray
        case .internet: return .blue
        }
    }
}

// MARK: - Device Status
enum DeviceStatus: String, Codable {
    case safe    = "safe"
    case unknown = "unknown"
    case alert   = "alert"
    case offline = "offline"

    var localizedName: String {
        switch self {
        case .safe:    return L10n.DeviceStatus.safe
        case .unknown: return L10n.DeviceStatus.unknown
        case .alert:   return L10n.DeviceStatus.alert
        case .offline: return L10n.DeviceStatus.offline
        }
    }

    var color: Color {
        switch self {
        case .safe:    return Color(red: 0.2, green: 0.8, blue: 0.4)
        case .unknown: return Color(red: 1.0, green: 0.6, blue: 0.0)
        case .alert:   return Color(red: 0.9, green: 0.2, blue: 0.2)
        case .offline: return Color.gray.opacity(0.5)
        }
    }

    var dot: String {
        switch self {
        case .safe:    return "●"
        case .unknown: return "●"
        case .alert:   return "●"
        case .offline: return "○"
        }
    }
}

// MARK: - Open Port
struct OpenPort: Identifiable, Codable {
    let id: UUID
    let port: Int
    let service: String
    let isVulnerable: Bool
    let notes: String

    init(port: Int, service: String, isVulnerable: Bool = false, notes: String = "") {
        self.id = UUID()
        self.port = port
        self.service = service
        self.isVulnerable = isVulnerable
        self.notes = notes
    }
}

// MARK: - OS Guess
enum OSGuess: String, Codable {
    case macOS   = "macos"
    case windows = "windows"
    case linux   = "linux"
    case ios     = "ios"
    case router  = "router_fw"
    case unknown = "unknown"

    var localizedName: String {
        switch self {
        case .macOS:   return L10n.OS.macOS
        case .windows: return L10n.OS.windows
        case .linux:   return L10n.OS.linux
        case .ios:     return L10n.OS.ios
        case .router:  return L10n.OS.router
        case .unknown: return L10n.OS.unknown
        }
    }

    var icon: String {
        switch self {
        case .macOS:   return "apple.logo"
        case .windows: return "pc"
        case .linux:   return "terminal"
        case .ios:     return "iphone"
        case .router:  return "wifi.router.fill"
        case .unknown: return "questionmark"
        }
    }
}

// MARK: - Network Device
class NetworkDevice: ObservableObject, Identifiable, Codable {
    let id: UUID
    @Published var ip: String
    @Published var mac: String
    @Published var hostname: String
    @Published var mdnsName: String       // Bonjour/mDNS name
    @Published var netbiosName: String    // NetBIOS name (Windows)
    @Published var vendor: String
    @Published var type: DeviceType
    @Published var status: DeviceStatus
    @Published var openPorts: [OpenPort]
    @Published var isCurrentDevice: Bool
    @Published var responseTime: Double   // ms
    @Published var ttl: Int               // TTL from ping → OS fingerprint
    @Published var osGuess: OSGuess       // deduced from TTL + vendor
    @Published var httpBanner: String     // HTTP Server header
    @Published var httpTitle: String      // HTML <title> from web interface
    @Published var firstSeen: Date
    @Published var lastSeen: Date
    @Published var parentIP: String?
    @Published var bonjourServices: [String]   // services Bonjour découverts via NWBrowser

    init(
        ip: String,
        mac: String = "",
        hostname: String = "",
        mdnsName: String = "",
        netbiosName: String = "",
        vendor: String = "",
        type: DeviceType = .unknown,
        status: DeviceStatus = .unknown,
        openPorts: [OpenPort] = [],
        isCurrentDevice: Bool = false,
        responseTime: Double = 0,
        ttl: Int = 0,
        osGuess: OSGuess = .unknown,
        httpBanner: String = "",
        httpTitle: String = "",
        parentIP: String? = nil,
        bonjourServices: [String] = []
    ) {
        self.id = UUID()
        self.ip = ip
        self.mac = mac
        self.hostname = hostname
        self.mdnsName = mdnsName
        self.netbiosName = netbiosName
        self.vendor = vendor
        self.type = type
        self.status = status
        self.openPorts = openPorts
        self.isCurrentDevice = isCurrentDevice
        self.responseTime = responseTime
        self.ttl = ttl
        self.osGuess = osGuess
        self.httpBanner = httpBanner
        self.httpTitle = httpTitle
        self.firstSeen = Date()
        self.lastSeen = Date()
        self.parentIP = parentIP
        self.bonjourServices = bonjourServices
    }

    var displayName: String {
        if !mdnsName.isEmpty  { return mdnsName }
        if !hostname.isEmpty  { return hostname }
        if isCurrentDevice    { return "Ce Mac" }
        return ip
    }

    var shortIP: String {
        ip.components(separatedBy: ".").last.map { ".\($0)" } ?? ip
    }

    var alertCount: Int {
        openPorts.filter { $0.isVulnerable }.count
    }

    // MARK: Codable
    enum CodingKeys: String, CodingKey {
        case id, ip, mac, hostname, mdnsName, netbiosName, vendor, type, status,
             openPorts, isCurrentDevice, responseTime, ttl, osGuess,
             httpBanner, httpTitle, firstSeen, lastSeen, parentIP, bonjourServices
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self,        forKey: .id)
        ip              = try c.decode(String.self,      forKey: .ip)
        mac             = try c.decode(String.self,      forKey: .mac)
        hostname        = try c.decode(String.self,      forKey: .hostname)
        mdnsName        = (try? c.decode(String.self,    forKey: .mdnsName))   ?? ""
        netbiosName     = (try? c.decode(String.self,    forKey: .netbiosName)) ?? ""
        vendor          = try c.decode(String.self,      forKey: .vendor)
        type            = try c.decode(DeviceType.self,  forKey: .type)
        status          = try c.decode(DeviceStatus.self,forKey: .status)
        openPorts       = try c.decode([OpenPort].self,  forKey: .openPorts)
        isCurrentDevice = try c.decode(Bool.self,        forKey: .isCurrentDevice)
        responseTime    = try c.decode(Double.self,      forKey: .responseTime)
        ttl             = (try? c.decode(Int.self,       forKey: .ttl))        ?? 0
        osGuess         = (try? c.decode(OSGuess.self,   forKey: .osGuess))    ?? .unknown
        httpBanner      = (try? c.decode(String.self,    forKey: .httpBanner)) ?? ""
        httpTitle       = (try? c.decode(String.self,    forKey: .httpTitle))  ?? ""
        firstSeen       = (try? c.decode(Date.self,      forKey: .firstSeen))  ?? Date()
        lastSeen        = try c.decode(Date.self,        forKey: .lastSeen)
        parentIP        = try c.decodeIfPresent(String.self, forKey: .parentIP)
        bonjourServices = (try? c.decode([String].self,      forKey: .bonjourServices)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,              forKey: .id)
        try c.encode(ip,              forKey: .ip)
        try c.encode(mac,             forKey: .mac)
        try c.encode(hostname,        forKey: .hostname)
        try c.encode(mdnsName,        forKey: .mdnsName)
        try c.encode(netbiosName,     forKey: .netbiosName)
        try c.encode(vendor,          forKey: .vendor)
        try c.encode(type,            forKey: .type)
        try c.encode(status,          forKey: .status)
        try c.encode(openPorts,       forKey: .openPorts)
        try c.encode(isCurrentDevice, forKey: .isCurrentDevice)
        try c.encode(responseTime,    forKey: .responseTime)
        try c.encode(ttl,             forKey: .ttl)
        try c.encode(osGuess,         forKey: .osGuess)
        try c.encode(httpBanner,      forKey: .httpBanner)
        try c.encode(httpTitle,       forKey: .httpTitle)
        try c.encode(firstSeen,       forKey: .firstSeen)
        try c.encode(lastSeen,        forKey: .lastSeen)
        try c.encode(parentIP,        forKey: .parentIP)
        try c.encode(bonjourServices, forKey: .bonjourServices)
    }
}
