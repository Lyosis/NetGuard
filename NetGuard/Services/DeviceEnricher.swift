import Foundation
import Network

// MARK: - DeviceEnricher
/// Enrichit chaque appareil avec OS, mDNS, NetBIOS, HTTP banner, latence précise
actor DeviceEnricher {

    static let shared = DeviceEnricher()
    private init() {}

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
        async let mdns    = resolveMDNS(ip: device.ip)
        async let nb      = resolveNetBIOS(ip: device.ip)
        async let http    = grabHTTP(ip: device.ip, ports: device.openPorts.map(\.port))

        let (pingResult, mdnsName, nbName, httpInfo) = await (ping, mdns, nb, http)

        // Compute OS guess on the actor before switching to MainActor
        let (vendor, devType, hostname) = await MainActor.run {
            (device.vendor, device.type, device.hostname)
        }
        let os = guessOS(ttl: pingResult.ttl, vendor: vendor, type: devType, hostname: hostname)

        await MainActor.run {
            device.responseTime = pingResult.ms
            device.ttl          = pingResult.ttl
            device.osGuess      = os
            if !mdnsName.isEmpty  { device.mdnsName   = mdnsName }
            if !nbName.isEmpty    { device.netbiosName = nbName }
            if !httpInfo.banner.isEmpty { device.httpBanner = httpInfo.banner }
            if !httpInfo.title.isEmpty  { device.httpTitle  = httpInfo.title }
            device.lastSeen = Date()
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

    // MARK: - mDNS / Bonjour resolution
    private func resolveMDNS(ip: String) async -> String {
        return await withCheckedContinuation { continuation in
            // dns-sd lookup by address
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
            process.arguments = ["-Q", ip + ".in-addr.arpa.", "PTR"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError  = Pipe()

            // dns-sd runs indefinitely, kill after 1.5s
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                process.terminate()
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
                // Parse hostname from output
                let lines = out.components(separatedBy: "\n")
                for line in lines {
                    if line.contains("PTR") {
                        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                        if let last = parts.last {
                            let name = String(last).trimmingCharacters(in: .whitespaces)
                                        .replacingOccurrences(of: ".local.", with: "")
                                        .replacingOccurrences(of: ".", with: "")
                            if !name.isEmpty && !name.hasPrefix("_") {
                                continuation.resume(returning: name)
                                return
                            }
                        }
                    }
                }
                continuation.resume(returning: "")
            }
            try? process.run()
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
