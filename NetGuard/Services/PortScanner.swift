import Foundation
import Network

// MARK: - Common Ports
struct CommonPort {
    let number: Int
    let service: String
    let isRisky: Bool
    let riskReason: String

    static let all: [CommonPort] = [
        CommonPort(number: 21,   service: "FTP",           isRisky: true,  riskReason: "Transfert de fichiers non chiffré"),
        CommonPort(number: 22,   service: "SSH",           isRisky: false, riskReason: ""),
        CommonPort(number: 23,   service: "Telnet",        isRisky: true,  riskReason: "Protocole non chiffré (obsolète)"),
        CommonPort(number: 25,   service: "SMTP",          isRisky: false, riskReason: ""),
        CommonPort(number: 53,   service: "DNS",           isRisky: false, riskReason: ""),
        CommonPort(number: 80,   service: "HTTP",          isRisky: true,  riskReason: "Trafic web non chiffré"),
        CommonPort(number: 110,  service: "POP3",          isRisky: true,  riskReason: "Mail non chiffré"),
        CommonPort(number: 135,  service: "MS-RPC",        isRisky: true,  riskReason: "Windows RPC exposé"),
        CommonPort(number: 139,  service: "NetBIOS",       isRisky: true,  riskReason: "Partage réseau Windows non sécurisé"),
        CommonPort(number: 143,  service: "IMAP",          isRisky: false, riskReason: ""),
        CommonPort(number: 161,  service: "SNMP",          isRisky: true,  riskReason: "Peut exposer des infos système"),
        CommonPort(number: 443,  service: "HTTPS",         isRisky: false, riskReason: ""),
        CommonPort(number: 445,  service: "SMB",           isRisky: true,  riskReason: "Partage Windows (cible ransomwares)"),
        CommonPort(number: 548,  service: "AFP",           isRisky: false, riskReason: ""),
        CommonPort(number: 554,  service: "RTSP",          isRisky: true,  riskReason: "Caméra/stream non sécurisé"),
        CommonPort(number: 631,  service: "IPP",           isRisky: false, riskReason: ""),
        CommonPort(number: 993,  service: "IMAPS",         isRisky: false, riskReason: ""),
        CommonPort(number: 995,  service: "POP3S",         isRisky: false, riskReason: ""),
        CommonPort(number: 1433, service: "MSSQL",         isRisky: true,  riskReason: "Base de données exposée"),
        CommonPort(number: 1723, service: "PPTP VPN",      isRisky: true,  riskReason: "VPN obsolète et cassé"),
        CommonPort(number: 2049, service: "NFS",           isRisky: true,  riskReason: "Partage de fichiers réseau"),
        CommonPort(number: 3306, service: "MySQL",         isRisky: true,  riskReason: "Base de données exposée"),
        CommonPort(number: 3389, service: "RDP",           isRisky: true,  riskReason: "Bureau distant exposé"),
        CommonPort(number: 5000, service: "UPnP/Dev",      isRisky: true,  riskReason: "Service UPnP exposé"),
        CommonPort(number: 5900, service: "VNC",           isRisky: true,  riskReason: "Bureau distant non chiffré"),
        CommonPort(number: 5985, service: "WinRM HTTP",    isRisky: true,  riskReason: "Gestion Windows non chiffrée"),
        CommonPort(number: 6881, service: "BitTorrent",    isRisky: false, riskReason: ""),
        CommonPort(number: 8080, service: "HTTP Alt",      isRisky: true,  riskReason: "Interface admin non sécurisée"),
        CommonPort(number: 8443, service: "HTTPS Alt",     isRisky: false, riskReason: ""),
        CommonPort(number: 8888, service: "HTTP Proxy",    isRisky: true,  riskReason: "Proxy ou service non chiffré"),
        CommonPort(number: 9100, service: "JetDirect",     isRisky: false, riskReason: ""),
        CommonPort(number: 9200, service: "Elasticsearch", isRisky: true,  riskReason: "Base de données exposée sans auth"),
        CommonPort(number: 27017, service: "MongoDB",      isRisky: true,  riskReason: "Base de données exposée sans auth"),
    ]
}

// MARK: - Port Scanner
actor PortScanner {

    // MARK: - Scan single host
    func scanPorts(
        host: String,
        ports: [Int] = CommonPort.all.map(\.number),
        timeout: TimeInterval = 1.0,
        progressHandler: @Sendable @escaping (Double, String) async -> Void
    ) async -> [OpenPort] {

        var openPorts: [OpenPort] = []
        let portInfoMap = Dictionary(uniqueKeysWithValues: CommonPort.all.map { ($0.number, $0) })
        let chunkSize = 20

        for (idx, chunk) in ports.chunked(into: chunkSize).enumerated() {
            let progress = Double(idx * chunkSize) / Double(ports.count)
            await progressHandler(progress, "Scan ports \(idx * chunkSize + 1)–\(min((idx + 1) * chunkSize, ports.count))…")

            let results = await withTaskGroup(of: (Int, Bool).self) { group in
                for port in chunk {
                    group.addTask {
                        let isOpen = await self.checkPort(host: host, port: port, timeout: timeout)
                        return (port, isOpen)
                    }
                }
                var r: [(Int, Bool)] = []
                for await result in group { r.append(result) }
                return r
            }

            for (port, isOpen) in results where isOpen {
                let info = portInfoMap[port]
                let service = info?.service ?? "Unknown"
                let isVulnerable = info?.isRisky ?? false
                let notes = info?.riskReason ?? ""
                openPorts.append(OpenPort(port: port, service: service,
                                          isVulnerable: isVulnerable, notes: notes))
            }
        }

        return openPorts.sorted { $0.port < $1.port }
    }

    // MARK: - Scan multiple hosts
    func scanMultipleHosts(
        devices: [NetworkDevice],
        progressHandler: @Sendable @escaping (Double, String) async -> Void
    ) async {
        let total = devices.count
        for (idx, device) in devices.enumerated() {
            let progress = Double(idx) / Double(max(total, 1))
            await progressHandler(progress, "Scan ports: \(device.ip)…")
            let ports = await scanPorts(host: device.ip) { _, _ in }
            // Compute status on the actor before switching to MainActor
            let newStatus = computeStatus(ports: ports)
            await MainActor.run {
                device.openPorts = ports
                device.status = newStatus
            }
        }
        await progressHandler(1.0, "Scan des ports terminé")
    }

    // MARK: - TCP connect check
    private func checkPort(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        return await withCheckedContinuation { continuation in
            // Use a class-based box to safely share the "resumed" flag across closures
            final class ResumeBox: @unchecked Sendable {
                var resumed = false
            }
            let box = ResumeBox()
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port))
            )
            let connection = NWConnection(to: endpoint, using: .tcp)
            let q = DispatchQueue(label: "port-check.\(port)")

            let timer = DispatchWorkItem {
                q.sync {
                    guard !box.resumed else { return }
                    box.resumed = true
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    timer.cancel()
                    q.sync {
                        guard !box.resumed else { return }
                        box.resumed = true
                        connection.cancel()
                        continuation.resume(returning: true)
                    }
                case .failed, .cancelled:
                    timer.cancel()
                    q.sync {
                        guard !box.resumed else { return }
                        box.resumed = true
                        continuation.resume(returning: false)
                    }
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    // MARK: - Compute device status from ports (no device reference needed)
    private func computeStatus(ports: [OpenPort]) -> DeviceStatus {
        if ports.contains(where: { $0.isVulnerable }) { return .alert }
        return .safe
    }
}
