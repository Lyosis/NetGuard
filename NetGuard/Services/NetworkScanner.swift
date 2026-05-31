import Foundation
import Network

// MARK: - NetworkScanner
/// Découvre les hôtes actifs sur le réseau local via ARP + ping
actor NetworkScanner {

    // MARK: - Discover hosts
    /// Retourne la liste des IP actives sur le sous-réseau
    func discoverHosts(
        subnet: String,
        localIP: String,
        gateway: String,
        progressHandler: @Sendable @escaping (Double, String) async -> Void
    ) async -> [NetworkDevice] {

        var devices: [NetworkDevice] = []

        // 1. Parse le sous-réseau (ex: 192.168.1.0/24)
        let (baseIP, hostCount) = parseSubnet(subnet)
        guard hostCount > 0 else { return [] }

        // 2. Ajouter d'abord les hôtes connus (gateway, local)
        var knownIPs: [String] = []
        if !gateway.isEmpty && gateway != "—" { knownIPs.append(gateway) }
        if !localIP.isEmpty  && localIP != "—"  { knownIPs.append(localIP) }

        // 3. Lire la table ARP (rapide)
        await progressHandler(0.05, "Lecture table ARP…")
        let arpDevices = readARPTable()

        // Merge ARP
        var arpMap: [String: (mac: String, hostname: String)] = [:]
        for (ip, mac) in arpDevices {
            arpMap[ip] = (mac: mac, hostname: "")
        }

        // 4. Résoudre les noms d'hôtes depuis le cache DNS
        await progressHandler(0.10, "Résolution noms d'hôtes…")

        // 5. Ping sweep sur le sous-réseau /24 (256 hôtes max, par lots de 32)
        let allIPs = generateIPs(base: baseIP, count: min(hostCount, 254))
        let chunkSize = 32
        var activeIPs: Set<String> = []

        // Toujours inclure l'IP locale
        activeIPs.insert(localIP)

        for (chunkIdx, chunk) in allIPs.chunked(into: chunkSize).enumerated() {
            let progress = 0.10 + Double(chunkIdx * chunkSize) / Double(allIPs.count) * 0.60
            await progressHandler(progress, "Ping sweep \(chunkIdx * chunkSize + 1)–\(min((chunkIdx + 1) * chunkSize, allIPs.count))…")

            await withTaskGroup(of: String?.self) { group in
                for ip in chunk {
                    group.addTask {
                        await self.pingHost(ip)
                    }
                }
                for await result in group {
                    if let ip = result {
                        activeIPs.insert(ip)
                    }
                }
            }
        }

        // 6. Rafraîchir la table ARP après le ping pour avoir les MAC
        await progressHandler(0.72, "Mise à jour table ARP…")
        let freshARP = readARPTable()
        for (ip, mac) in freshARP {
            if arpMap[ip] == nil {
                arpMap[ip] = (mac: mac, hostname: "")
            }
        }

        // 7. Résoudre les hostnames
        await progressHandler(0.75, "Résolution hostnames…")
        var hostnameMap: [String: String] = [:]
        for ip in activeIPs {
            if let hostname = await resolveHostname(ip) {
                hostnameMap[ip] = hostname
            }
        }

        // 8. Construire les objets NetworkDevice
        await progressHandler(0.85, "Construction de la carte réseau…")
        for ip in activeIPs.sorted() {
            let mac      = arpMap[ip]?.mac ?? ""
            let hostname = hostnameMap[ip] ?? ""
            let vendor   = await OUIDatabase.shared.lookup(mac: mac) ?? lookupVendor(mac: mac)
            let isCurrent = ip == localIP
            let isGW      = ip == gateway

            let deviceType: DeviceType
            if isGW {
                deviceType = .router
            } else if isCurrent {
                deviceType = .mac
            } else {
                deviceType = guessDeviceType(vendor: vendor, hostname: hostname, mac: mac)
            }

            let device = NetworkDevice(
                ip: ip,
                mac: mac,
                hostname: hostname,
                vendor: vendor,
                type: deviceType,
                status: .unknown,
                isCurrentDevice: isCurrent,
                responseTime: 0,
                parentIP: isGW ? nil : gateway
            )
            devices.append(device)
        }

        await progressHandler(1.0, "Découverte terminée")
        return devices
    }

    // MARK: - Ping
    private func pingHost(_ ip: String) async -> String? {
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            process.arguments = ["-c", "1", "-W", "500", "-t", "1", ip]
            process.standardOutput = Pipe()
            process.standardError  = Pipe()
            process.terminationHandler = { p in
                continuation.resume(returning: p.terminationStatus == 0 ? ip : nil)
            }
            do { try process.run() }
            catch { continuation.resume(returning: nil) }
        }
    }

    // MARK: - ARP Table
    private func readARPTable() -> [(ip: String, mac: String)] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-a"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = Pipe()
        try? process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        var results: [(String, String)] = []
        // Format: hostname (ip) at mac on interface
        let regex = try? NSRegularExpression(pattern: #"\((\d+\.\d+\.\d+\.\d+)\) at ([0-9a-f:]+)"#)
        let ns = output as NSString
        regex?.enumerateMatches(in: output, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let m = match, m.numberOfRanges == 3 else { return }
            let ip  = ns.substring(with: m.range(at: 1))
            let mac = ns.substring(with: m.range(at: 2))
            if mac != "(incomplete)" {
                results.append((ip, mac))
            }
        }
        return results
    }

    // MARK: - Hostname resolution
    private func resolveHostname(_ ip: String) async -> String? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .background).async {
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)
                inet_pton(AF_INET, ip, &addr.sin_addr)

                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size),
                                    &hostname, socklen_t(hostname.count),
                                    nil, 0, NI_NAMEREQD)
                    }
                }
                if result == 0 {
                    let name = String(cString: hostname)
                    continuation.resume(returning: name == ip ? nil : name)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Subnet parsing
    private func parseSubnet(_ cidr: String) -> (base: String, count: Int) {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              prefix >= 8, prefix <= 30 else {
            return (cidr, 0)
        }
        let hostBits = 32 - prefix
        let count    = (1 << hostBits) - 2
        // Compute base IP (network address + 1)
        let ipParts = parts[0].split(separator: ".").compactMap { Int($0) }
        guard ipParts.count == 4 else { return (String(parts[0]), count) }
        let base = "\(ipParts[0]).\(ipParts[1]).\(ipParts[2]).1"
        return (base, count)
    }

    private func generateIPs(base: String, count: Int) -> [String] {
        let components = base.split(separator: ".").compactMap { Int($0) }
        guard components.count == 4 else { return [] }
        let prefix = "\(components[0]).\(components[1]).\(components[2])"
        return (1...min(count, 254)).map { "\(prefix).\($0)" }
    }

    // MARK: - Vendor lookup (OUI prefix)
    private func lookupVendor(mac: String) -> String {
        let oui = mac.components(separatedBy: ":").prefix(3).joined(separator: ":")
                      .uppercased()
        let vendors: [String: String] = [
            "00:03:93": "Apple", "00:0A:27": "Apple", "00:0A:95": "Apple",
            "00:1C:B3": "Apple", "00:1E:52": "Apple", "00:1F:F3": "Apple",
            "00:21:E9": "Apple", "00:22:41": "Apple", "00:23:12": "Apple",
            "00:23:32": "Apple", "00:23:6C": "Apple", "00:24:36": "Apple",
            "00:25:00": "Apple", "00:25:4B": "Apple", "00:25:BC": "Apple",
            "00:26:08": "Apple", "00:26:4A": "Apple", "00:26:B0": "Apple",
            "00:26:BB": "Apple", "A4:5E:60": "Apple", "AC:BC:32": "Apple",
            "B8:8D:12": "Apple", "DC:A9:04": "Apple", "E0:F5:C6": "Apple",
            "F8:27:93": "Apple", "F8:1E:DF": "Apple",
            "00:50:56": "VMware", "00:0C:29": "VMware",
            "00:1A:11": "Google", "54:60:09": "Google",
            "B0:BE:76": "Synology", "00:11:32": "Synology",
            "18:A6:F7": "Ubiquiti", "24:A4:3C": "Ubiquiti", "DC:9F:DB": "Ubiquiti",
            "CC:40:D0": "Cisco", "00:17:0E": "Cisco", "00:1B:8F": "Cisco",
            "C4:E9:84": "TP-Link", "50:C7:BF": "TP-Link", "54:AF:97": "TP-Link",
            "B0:4E:26": "Netgear", "C0:FF:D4": "Netgear", "20:0C:C8": "Netgear",
            "00:26:37": "Brother", "00:1B:A9": "Brother",
        ]
        return vendors[oui] ?? ""
    }

    // MARK: - Device type guess
    private func guessDeviceType(vendor: String, hostname: String, mac: String) -> DeviceType {
        let v = vendor.lowercased()
        let h = hostname.lowercased()
        if v.contains("apple") || h.contains("macbook") || h.contains("mac-mini") || h.contains("imac") {
            if h.contains("iphone") { return .iphone }
            if h.contains("ipad")   { return .ipad }
            return .mac
        }
        if h.contains("iphone") { return .iphone }
        if h.contains("ipad")   { return .ipad }
        if v.contains("synology") || h.contains("nas") || h.contains("diskstation") { return .nas }
        if v.contains("brother") || h.contains("print") { return .printer }
        if v.contains("ubiquiti") || v.contains("cisco") { return .firewall }
        if h.contains("switch") { return .switch }
        return .unknown
    }
}

// MARK: - Array chunked helper
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
