import Foundation
import Network

// MARK: - BonjourInfo
/// Informations Bonjour associées à un appareil (indexées par IPv4)
private struct BonjourInfo {
    var instanceName: String        // ex: "Mon NAS" (nom Bonjour instance)
    var services: [String]          // ex: ["_smb._tcp", "_afpovertcp._tcp"]
}

// MARK: - DeviceEnricher
/// Enrichit chaque appareil avec OS, Bonjour (NWBrowser), NetBIOS, HTTP banner, latence précise
actor DeviceEnricher {

    static let shared = DeviceEnricher()
    private init() {}

    // MARK: - Bonjour state (partagé entre discoverBonjourServices et enrichDevice)
    private var bonjourTable: [String: BonjourInfo] = [:]

    /// Types de services Bonjour à découvrir
    private static let bonjourServiceTypes: [String] = [
        "_http._tcp",
        "_https._tcp",
        "_ssh._tcp",
        "_smb._tcp",
        "_afpovertcp._tcp",
        "_raop._tcp",
        "_airplay._tcp",
        "_ipp._tcp",
        "_printer._tcp",
        "_homekit._tcp",
        "_googlecast._tcp",
        "_companion-link._tcp",
        "_sleep-proxy._tcp",
        "_rfb._tcp",
        "_ftp._tcp",
        "_daap._tcp",
    ]

    // MARK: - Enrich all devices
    func enrichAll(
        devices: [NetworkDevice],
        progressHandler: @Sendable @escaping (Double, String) async -> Void
    ) async {
        let total = Double(devices.count)
        for (idx, device) in devices.enumerated() {
            await progressHandler(Double(idx) / total, "Analyse \(device.ip)…")
            await enrichDevice(device)
        }
        await progressHandler(1.0, "Analyse terminée")
    }

    // MARK: - Enrich single device
    func enrichDevice(_ device: NetworkDevice) async {
        async let ping    = precisePing(ip: device.ip)
        async let nb      = resolveNetBIOS(ip: device.ip)
        async let http    = grabHTTP(ip: device.ip, ports: device.openPorts.map(\.port))

        let (pingResult, nbName, httpInfo) = await (ping, nb, http)

        // Récupérer les infos Bonjour depuis la table déjà remplie
        let bonjour = bonjourTable[device.ip]

        // Compute OS guess on the actor before switching to MainActor
        let (vendor, devType, hostname) = await MainActor.run {
            (device.vendor, device.type, device.hostname)
        }
        let os = guessOS(ttl: pingResult.ttl, vendor: vendor, type: devType, hostname: hostname)

        await MainActor.run {
            device.responseTime = pingResult.ms
            device.ttl          = pingResult.ttl
            device.osGuess      = os
            if let b = bonjour {
                if !b.instanceName.isEmpty { device.mdnsName = b.instanceName }
                device.bonjourServices = b.services
            }
            if !nbName.isEmpty    { device.netbiosName = nbName }
            if !httpInfo.banner.isEmpty { device.httpBanner = httpInfo.banner }
            if !httpInfo.title.isEmpty  { device.httpTitle  = httpInfo.title }
            device.lastSeen = Date()
        }
    }

    // MARK: - Bonjour Discovery (NWBrowser)

    /// Lance la découverte Bonjour pour tous les types de services en parallèle,
    /// résout les endpoints en IPv4, puis popule `bonjourTable`.
    /// Durée totale : ~3s browse + ~2s resolve (en parallèle).
    func discoverBonjourServices() async {
        // 1. Découverte de tous les types en parallèle (3s timeout)
        let allResults: [BrowseResult] = await withTaskGroup(of: [BrowseResult].self) { group in
            for serviceType in Self.bonjourServiceTypes {
                group.addTask {
                    await self.browse(serviceType, timeout: 3.0)
                }
            }
            var combined: [BrowseResult] = []
            for await partial in group {
                combined.append(contentsOf: partial)
            }
            return combined
        }

        // 2. Résolution des endpoints en IPv4 en parallèle (2s timeout par connexion)
        var table: [String: BonjourInfo] = [:]
        await withTaskGroup(of: (String?, BrowseResult).self) { group in
            for result in allResults {
                group.addTask {
                    let ip = await self.resolveToIP(result.endpoint)
                    return (ip, result)
                }
            }
            for await (ip, result) in group {
                guard let ip else { continue }
                if var existing = table[ip] {
                    if !existing.services.contains(result.serviceType) {
                        existing.services.append(result.serviceType)
                    }
                    if existing.instanceName.isEmpty {
                        existing.instanceName = result.instanceName
                    }
                    table[ip] = existing
                } else {
                    table[ip] = BonjourInfo(instanceName: result.instanceName,
                                            services: [result.serviceType])
                }
            }
        }

        bonjourTable = table
    }

    // MARK: - NWBrowser (un type de service, retourne tous les résultats en ~timeout secondes)

    private struct BrowseResult {
        var instanceName: String
        var serviceType: String
        var endpoint: NWEndpoint
    }

    private func browse(_ serviceType: String, timeout: TimeInterval) async -> [BrowseResult] {
        // NWBrowser doit être utilisé depuis une DispatchQueue — on utilise une queue sérialisée
        // par type de service pour éviter les conflits de concurrence Swift 6.
        let queueLabel = "netguard.bonjour.\(serviceType.filter { $0.isLetter || $0 == "." })"
        let queue = DispatchQueue(label: queueLabel, qos: .utility)

        // Box @unchecked Sendable : manipulée exclusivement sur `queue`
        final class Box: @unchecked Sendable {
            var results: [BrowseResult] = []
        }
        let box = Box()

        return await withCheckedContinuation { (continuation: CheckedContinuation<[BrowseResult], Never>) in
            // Utiliser un flag pour éviter le double-resume
            final class Flag: @unchecked Sendable { var done = false }
            let flag = Flag()

            let browser = NWBrowser(
                for: .bonjourWithTXTRecord(type: serviceType, domain: "local."),
                using: NWParameters()
            )

            browser.browseResultsChangedHandler = { currentResults, _ in
                // Appelé sur queue (NWBrowser hérite de la queue passée à start)
                box.results = currentResults.compactMap { result -> BrowseResult? in
                    guard case let .service(name, type, _, _) = result.endpoint else { return nil }
                    // Normaliser le type : supprimer le point final éventuel ("_ssh._tcp." → "_ssh._tcp")
                    let normalizedType = type.hasSuffix(".") ? String(type.dropLast()) : type
                    return BrowseResult(instanceName: name,
                                        serviceType: normalizedType,
                                        endpoint: result.endpoint)
                }
            }

            browser.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                guard !flag.done else { return }
                flag.done = true
                browser.cancel()
                continuation.resume(returning: box.results)
            }
        }
    }

    // MARK: - Résolution endpoint → IPv4 via NWConnection

    private func resolveToIP(_ endpoint: NWEndpoint) async -> String? {
        let queue = DispatchQueue(label: "netguard.resolve", qos: .utility)

        final class State: @unchecked Sendable {
            var resumed = false
        }
        let state = State()

        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let conn = NWConnection(to: endpoint, using: .tcp)

            conn.stateUpdateHandler = { newState in
                guard !state.resumed else { return }
                switch newState {
                case .ready:
                    state.resumed = true
                    // Lire l'adresse réelle depuis le chemin courant
                    if let path = conn.currentPath,
                       case let .hostPort(host, _) = path.remoteEndpoint {
                        let ipString: String?
                        switch host {
                        case .ipv4(let addr):
                            // NWIPv4Address n'est pas directement StringConvertible en Swift 6
                            // On passe par debugDescription : "192.168.1.5"
                            ipString = "\(addr)"
                        case .name(let name, _):
                            // Fallback si on récupère un nom plutôt qu'une IP
                            ipString = name.isEmpty ? nil : name
                        default:
                            ipString = nil
                        }
                        conn.cancel()
                        continuation.resume(returning: ipString)
                    } else {
                        conn.cancel()
                        continuation.resume(returning: nil)
                    }
                case .failed, .cancelled:
                    state.resumed = true
                    continuation.resume(returning: nil)
                default:
                    break
                }
            }

            conn.start(queue: queue)

            // Timeout de 2s par résolution
            queue.asyncAfter(deadline: .now() + 2.0) {
                guard !state.resumed else { return }
                state.resumed = true
                conn.cancel()
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Precise Ping (parses TTL + RTT)
    private struct PingResult { var ms: Double; var ttl: Int }

    private func precisePing(ip: String) async -> PingResult {
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            process.arguments = ["-c", "3", "-W", "1000", ip]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError  = Pipe()
            process.terminationHandler = { _ in
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
                continuation.resume(returning: Self.parsePing(out))
            }
            try? process.run()
        }
    }

    private static func parsePing(_ output: String) -> PingResult {
        var ttl = 0
        var ms  = 0.0

        // Parse TTL from "ttl=64" or "TTL=64"
        if let r = output.range(of: #"ttl=(\d+)"#, options: .regularExpression) {
            let s = output[r].replacingOccurrences(of: "ttl=", with: "", options: .caseInsensitive)
            ttl = Int(s) ?? 0
        }

        // Parse avg RTT from "round-trip min/avg/max/stddev = 0.123/0.456/0.789/0.123 ms"
        if let r = output.range(of: #"min/avg/max[^=]+=\s*[\d.]+/([\d.]+)"#,
                                  options: .regularExpression) {
            let matched = String(output[r])
            let parts = matched.components(separatedBy: "/")
            if parts.count >= 2 { ms = Double(parts[1]) ?? 0 }
        }
        // Fallback: parse "time=X.X ms"
        if ms == 0, let r = output.range(of: #"time=([\d.]+) ms"#, options: .regularExpression) {
            let s = output[r]
                .replacingOccurrences(of: "time=", with: "")
                .replacingOccurrences(of: " ms", with: "")
            ms = Double(s) ?? 0
        }
        return PingResult(ms: ms, ttl: ttl)
    }

    // MARK: - OS Guess from TTL
    private func guessOS(ttl: Int, vendor: String, type: DeviceType, hostname: String) -> OSGuess {
        let v = vendor.lowercased()
        let h = hostname.lowercased()

        // Vendor-based hints
        if v.contains("apple") {
            if h.contains("iphone") || h.contains("ipad") { return .ios }
            return .macOS
        }
        if v.contains("microsoft") { return .windows }

        // TTL-based fingerprint (accounting for hops: ±10)
        switch ttl {
        case 1...65:   return .macOS   // macOS/Linux default 64
        case 66...130: return .windows // Windows default 128
        case 131...255:
            if type == .router || type == .firewall || type == .switch { return .router }
            return .linux
        default: return .unknown
        }
    }

    // MARK: - NetBIOS name (nmblookup)
    private func resolveNetBIOS(ip: String) async -> String {
        return await withCheckedContinuation { continuation in
            let nmb = Process()
            nmb.executableURL = URL(fileURLWithPath: "/usr/bin/nmblookup")
            nmb.arguments = ["-A", ip]
            let pipe = Pipe()
            nmb.standardOutput = pipe
            nmb.standardError  = Pipe()
            nmb.terminationHandler = { _ in
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
                // Format: "   HOSTNAME         <00> -         B <ACTIVE>"
                let regex = try? NSRegularExpression(pattern: #"^\s+(\S+)\s+<00>"#,
                                                      options: .anchorsMatchLines)
                let ns = out as NSString
                if let m = regex?.firstMatch(in: out, range: NSRange(location: 0, length: ns.length)),
                   m.numberOfRanges > 1 {
                    let name = ns.substring(with: m.range(at: 1))
                    continuation.resume(returning: name)
                } else {
                    continuation.resume(returning: "")
                }
            }
            do { try nmb.run() }
            catch { continuation.resume(returning: "") }
        }
    }

    // MARK: - HTTP Banner + Title grabbing
    private struct HTTPInfo { var banner: String; var title: String }

    private func grabHTTP(ip: String, ports: [Int]) async -> HTTPInfo {
        let httpPorts = [80, 8080, 8888, 443, 8443].filter { ports.contains($0) }
        guard let port = httpPorts.first else { return HTTPInfo(banner: "", title: "") }

        let scheme = (port == 443 || port == 8443) ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(ip):\(port)/") else {
            return HTTPInfo(banner: "", title: "")
        }

        return await withCheckedContinuation { continuation in
            var request = URLRequest(url: url, timeoutInterval: 3.0)
            request.httpMethod = "GET"
            request.setValue("NetGuard/1.0", forHTTPHeaderField: "User-Agent")

            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest  = 3
            config.timeoutIntervalForResource = 3
            let session = URLSession(configuration: config,
                                     delegate: InsecureDelegate(),
                                     delegateQueue: nil)

            session.dataTask(with: request) { data, response, _ in
                let banner = (response as? HTTPURLResponse)?
                    .value(forHTTPHeaderField: "Server") ?? ""

                var title = ""
                if let d = data, let html = String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1) {
                    if let r = html.range(of: #"<title[^>]*>([^<]+)</title>"#,
                                          options: [.regularExpression, .caseInsensitive]) {
                        title = String(html[r])
                            .replacingOccurrences(of: #"<title[^>]*>"#, with: "",
                                                  options: .regularExpression)
                            .replacingOccurrences(of: "</title>", with: "",
                                                  options: .caseInsensitive)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                continuation.resume(returning: HTTPInfo(banner: banner, title: title))
            }.resume()
        }
    }
}

// MARK: - InsecureDelegate (accept self-signed certs on local network)
private class InsecureDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
