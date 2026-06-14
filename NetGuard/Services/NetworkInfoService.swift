import Foundation
import SystemConfiguration
import CoreWLAN

// MARK: - NetworkInfoService
/// Récupère les informations réseau locales (IP, passerelle, DNS, WiFi)
class NetworkInfoService {

    static let shared = NetworkInfoService()
    private init() {}

    // MARK: - Fetch all network info
    func fetchNetworkInfo() -> NetworkInfo {
        // Try WiFi first (en0), then Ethernet (en1, en2...)
        let interfaces = getNetworkInterfaces()

        // Prioritize active interface
        for iface in interfaces {
            if let info = buildNetworkInfo(for: iface) {
                return info
            }
        }
        return .empty
    }

    func fetchAllInterfaces() -> [NetworkInfo] {
        let interfaces = getNetworkInterfaces()
        return interfaces.compactMap { buildNetworkInfo(for: $0) }
    }

    // MARK: - Private helpers

    private func getNetworkInterfaces() -> [String] {
        var names: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let current = ptr {
            let name = String(cString: current.pointee.ifa_name)
            let family = current.pointee.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) && (name.hasPrefix("en") || name.hasPrefix("bridge")) {
                if !names.contains(name) {
                    names.append(name)
                }
            }
            ptr = current.pointee.ifa_next
        }
        return names
    }

    private func buildNetworkInfo(for interface: String) -> NetworkInfo? {
        guard let ip = getIPAddress(for: interface),
              ip != "127.0.0.1" else { return nil }

        let mask    = getSubnetMask(for: interface) ?? "—"
        let gateway = getGateway(for: interface) ?? "—"
        let dns     = getDNSServers()
        let mac     = getMACAddress(for: interface) ?? "—"
        let ifType  = interface == "en0" ? "WiFi" : "Ethernet"
        let wifi    = interface == "en0" ? getWiFiInfo() : nil

        return NetworkInfo(
            interfaceName: interface,
            interfaceType: ifType,
            localIP: ip,
            gateway: gateway,
            subnet: mask,
            dns: dns,
            macAddress: mac,
            wifiInfo: wifi
        )
    }

    // MARK: IP Address
    private func getIPAddress(for interface: String) -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let current = ptr {
            let name = String(cString: current.pointee.ifa_name)
            if name == interface,
               current.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var addr = current.pointee.ifa_addr.pointee
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(&addr, socklen_t(addr.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: hostname)
                }
            }
            ptr = current.pointee.ifa_next
        }
        return nil
    }

    // MARK: Subnet Mask
    private func getSubnetMask(for interface: String) -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let current = ptr {
            let name = String(cString: current.pointee.ifa_name)
            if name == interface,
               current.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET),
               let netmask = current.pointee.ifa_netmask {
                var addr = netmask.pointee
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(&addr, socklen_t(addr.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: hostname)
                }
            }
            ptr = current.pointee.ifa_next
        }
        return nil
    }

    // MARK: Gateway (default route)
    private func getGateway(for interface: String) -> String? {
        let result = runCommand("/usr/sbin/netstat", args: ["-rn", "-f", "inet"])
        for line in result.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 4,
               parts[0] == "default",
               parts[3] == Substring(interface) {
                return String(parts[1])
            }
        }
        // Fallback: first default route
        for line in result.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2, parts[0] == "default" {
                let gw = String(parts[1])
                if !gw.contains(":") { return gw }  // skip IPv6
            }
        }
        return nil
    }

    // MARK: DNS Servers
    private func getDNSServers() -> [String] {
        let store = SCDynamicStoreCreate(nil, "NetGuard" as CFString, nil, nil)
        let key = SCDynamicStoreKeyCreateNetworkGlobalEntity(
            nil, kSCDynamicStoreDomainState, kSCEntNetDNS
        )
        guard let val = SCDynamicStoreCopyValue(store, key) as? [String: Any],
              let servers = val["ServerAddresses"] as? [String] else {
            return []
        }
        return servers
    }

    // MARK: MAC Address
    private func getMACAddress(for interface: String) -> String? {
        let result = runCommand("/sbin/ifconfig", args: [interface])
        for line in result.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("ether ") {
                return trimmed.replacingOccurrences(of: "ether ", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    // MARK: WiFi Info (CoreWLAN)
    private func getWiFiInfo() -> WiFiSecurityInfo? {
        guard let client = CWWiFiClient.shared().interface() else { return nil }
        let ssid     = client.ssid() ?? "—"
        let bssid    = client.bssid() ?? "—"
        let rssi     = client.rssiValue()
        let channel  = client.wlanChannel()?.channelNumber ?? 0
        let security = client.security()

        let secString: String
        switch security {
        case .none:            secString = L10n.WifiSecurity.open
        case .WEP:             secString = L10n.WifiSecurity.wep
        case .wpaPersonal:     secString = "WPA"
        case .wpa2Personal:    secString = "WPA2"
        case .wpa3Personal:    secString = "WPA3"
        case .enterprise:      secString = "WPA2-Enterprise"
        case .wpa3Enterprise:  secString = "WPA3-Enterprise"
        default:               secString = L10n.WifiSecurity.unknown
        }

        let isSecure = security == .wpa2Personal || security == .wpa3Personal
                    || security == .enterprise || security == .wpa3Enterprise

        return WiFiSecurityInfo(
            ssid: ssid, bssid: bssid, security: secString,
            channel: channel, rssi: rssi, isSecure: isSecure
        )
    }

    // MARK: Run shell command
    @discardableResult
    func runCommand(_ path: String, args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
