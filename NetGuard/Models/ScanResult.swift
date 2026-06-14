import Foundation

// MARK: - Scan Status
enum ScanStatus {
    case idle
    case scanning(progress: Double, message: String)
    case completed(duration: Double)
    case failed(error: String)

    var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }

    var progress: Double {
        if case .scanning(let p, _) = self { return p }
        return 0
    }

    var message: String {
        switch self {
        case .idle:                      return L10n.Scan.statusReady
        case .scanning(_, let msg):      return msg
        case .completed(let d):          return L10n.Scan.statusDone(d)
        case .failed(let err):           return L10n.Scan.statusError(err)
        }
    }
}

// MARK: - WiFi Security Info
struct WiFiSecurityInfo {
    var ssid: String
    var bssid: String
    var security: String          // WPA2, WPA3, WEP, Open...
    var channel: Int
    var rssi: Int                  // signal strength dBm
    var isSecure: Bool

    var securityColor: String {
        switch security.uppercased() {
        case let s where s.contains("WPA3"): return "green"
        case let s where s.contains("WPA2"): return "green"
        case let s where s.contains("WPA"):  return "yellow"
        case let s where s.contains("WEP"):  return "red"
        default: return "red"
        }
    }

    static let unknown = WiFiSecurityInfo(
        ssid: "—", bssid: "—", security: "—",
        channel: 0, rssi: 0, isSecure: false
    )
}

// MARK: - Network Info
struct NetworkInfo {
    var interfaceName: String     // en0, en1...
    var interfaceType: String     // WiFi, Ethernet
    var localIP: String
    var gateway: String
    var subnet: String
    var dns: [String]
    var macAddress: String
    var wifiInfo: WiFiSecurityInfo?

    var subnetCIDR: String {
        // Convert subnet mask to CIDR notation
        guard !subnet.isEmpty && subnet != "—" else { return "" }
        let parts = subnet.split(separator: ".").compactMap { Int($0) }
        let bits = parts.reduce(0) { acc, byte in
            acc + (0..<8).reduce(0) { a, i in a + ((byte >> i) & 1) }
        }
        let base = localIP.split(separator: ".").dropLast().joined(separator: ".")
        return "\(base).0/\(bits)"
    }

    static let empty = NetworkInfo(
        interfaceName: "—",
        interfaceType: "—",
        localIP: "—",
        gateway: "—",
        subnet: "—",
        dns: [],
        macAddress: "—",
        wifiInfo: nil
    )
}
