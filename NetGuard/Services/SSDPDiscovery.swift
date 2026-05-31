import Foundation
import Network

// MARK: - SSDPDiscovery
/// Découverte d'appareils UPnP via SSDP M-SEARCH (multicast UDP 239.255.255.250:1900).
///
/// Complète le sweep ICMP/TCP pour identifier les appareils qui n'exposent aucun
/// port admin standard mais répondent au protocole UPnP : Xbox, consoles
/// PlayStation, smart TVs (Samsung, LG, Sony Bravia), Sonos, Chromecast, Hue
/// Bridge, imprimantes pro, NAS UPnP, routeurs IGD, etc.
///
/// Mécanisme : on envoie un paquet `M-SEARCH * HTTP/1.1` avec `ST: ssdp:all` ;
/// chaque appareil UPnP répond en unicast avec ses headers `LOCATION:`, `ST:`,
/// `USN:`, `SERVER:`. On fetch ensuite chaque LOCATION (descripteur XML) pour
/// extraire `friendlyName`, `modelName`, `manufacturer`, `deviceType`.
actor SSDPDiscovery {

    /// Lance un sweep SSDP. Retourne un dict `IP → UPnPInfo` agrégé par IP.
    /// - Parameter timeout: durée totale d'écoute (multicast + retransmissions).
    func discover(timeout: TimeInterval = 3.0) async -> [String: UPnPInfo] {
        let raw = await collectResponses(timeout: timeout)
        guard !raw.isEmpty else { return [:] }

        var result: [String: UPnPInfo] = [:]
        await withTaskGroup(of: (String, UPnPInfo).self) { group in
            for (ip, headers) in raw {
                group.addTask { (ip, await Self.buildInfo(headers: headers)) }
            }
            for await (ip, info) in group {
                if let existing = result[ip] {
                    result[ip] = existing.merging(other: info)
                } else {
                    result[ip] = info
                }
            }
        }
        return result
    }

    // MARK: - 1. Collect raw M-SEARCH responses

    private func collectResponses(timeout: TimeInterval) async -> [String: [String: String]] {
        await withCheckedContinuation { (cont: CheckedContinuation<[String: [String: String]], Never>) in
            let storage = ResponseStorage()
            let resumed = ResumeFlag()

            // 1a. Build multicast group descriptor
            let descriptor: NWMulticastGroup
            do {
                descriptor = try NWMulticastGroup(
                    for: [.hostPort(host: "239.255.255.250", port: 1900)]
                )
            } catch {
                cont.resume(returning: [:])
                return
            }

            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            let group = NWConnectionGroup(with: descriptor, using: params)

            group.setReceiveHandler(maximumMessageSize: 65536,
                                    rejectOversizedMessages: true) { msg, content, _ in
                guard let data = content,
                      let text = String(data: data, encoding: .utf8),
                      let ip   = Self.extractIP(from: msg.remoteEndpoint) else { return }
                let headers = Self.parseHeaders(text)
                guard !headers.isEmpty else { return }
                storage.append(ip: ip, headers: headers)
            }

            group.stateUpdateHandler = { state in
                if case .ready = state {
                    Self.sendMSearch(via: group)
                    // Retransmission après 800 ms pour récupérer les appareils
                    // qui ont raté le premier paquet (Wi-Fi peu fiable).
                    Task {
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        Self.sendMSearch(via: group)
                    }
                }
            }

            group.start(queue: .global(qos: .userInitiated))

            // Timeout terminal : on annule le groupe et on rend la main.
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                group.cancel()
                if resumed.set() {
                    cont.resume(returning: storage.snapshot())
                }
            }
        }
    }

    private nonisolated static func sendMSearch(via group: NWConnectionGroup) {
        let msearch =
            "M-SEARCH * HTTP/1.1\r\n" +
            "HOST: 239.255.255.250:1900\r\n" +
            "MAN: \"ssdp:discover\"\r\n" +
            "MX: 2\r\n" +
            "ST: ssdp:all\r\n" +
            "\r\n"
        guard let data = msearch.data(using: .utf8) else { return }
        group.send(content: data, completion: { _ in })
    }

    // MARK: - 2. Parse helpers

    /// Headers HTTP-like → dict, clés en minuscules. Ignore la première ligne
    /// `HTTP/1.1 200 OK` (pas de `:` séparateur valide).
    private nonisolated static func parseHeaders(_ raw: String) -> [String: String] {
        var dict: [String: String] = [:]
        for line in raw.split(whereSeparator: { $0 == "\r" || $0 == "\n" }) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else { continue }
            // Garde le premier (cohérent avec RFC HTTP)
            if dict[key] == nil { dict[key] = value }
        }
        return dict
    }

    /// Extrait l'IPv4 depuis le NWEndpoint distant.
    private nonisolated static func extractIP(from endpoint: NWEndpoint?) -> String? {
        guard let endpoint else { return nil }
        if case .hostPort(let host, _) = endpoint {
            switch host {
            case .ipv4(let v4):
                // debugDescription = "192.168.1.176" éventuellement suffixé "%en0"
                return v4.debugDescription.components(separatedBy: "%").first
            case .name(let name, _):
                return name
            default:
                return nil
            }
        }
        return nil
    }

    // MARK: - 3. UPnP descriptor fetch + parse

    private nonisolated static func buildInfo(headers: [String: String]) async -> UPnPInfo {
        let server = headers["server"]
        let st     = headers["st"]
        let location = headers["location"]

        guard let urlString = location, let url = URL(string: urlString) else {
            return UPnPInfo(friendlyName: nil, modelName: nil,
                            manufacturer: nil, deviceType: st, server: server)
        }

        guard let xml = await fetchXML(url: url) else {
            return UPnPInfo(friendlyName: nil, modelName: nil,
                            manufacturer: nil, deviceType: st, server: server)
        }
        let parsed = parseDescriptor(xml: xml)
        return UPnPInfo(
            friendlyName: parsed.friendlyName,
            modelName:    parsed.modelName,
            manufacturer: parsed.manufacturer,
            deviceType:   parsed.deviceType ?? st,
            server:       server
        )
    }

    private nonisolated static func fetchXML(url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0
        request.httpMethod = "GET"
        request.setValue("close", forHTTPHeaderField: "Connection")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private nonisolated static func parseDescriptor(xml: String) -> SSDPDescriptorParser.Result {
        let delegate = SSDPDescriptorParser()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = delegate
        parser.parse()
        return delegate.result
    }
}

// MARK: - Thread-safe storage

/// Conteneur thread-safe pour les réponses pendant le sweep multicast.
/// Les callbacks `setReceiveHandler` peuvent arriver concurremment.
private final class ResponseStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var byIP: [String: [String: String]] = [:]

    func append(ip: String, headers: [String: String]) {
        lock.lock(); defer { lock.unlock() }
        if var existing = byIP[ip] {
            for (k, v) in headers where existing[k] == nil { existing[k] = v }
            byIP[ip] = existing
        } else {
            byIP[ip] = headers
        }
    }

    func snapshot() -> [String: [String: String]] {
        lock.lock(); defer { lock.unlock() }
        return byIP
    }
}

/// Garde-fou pour ne resume() la continuation qu'une seule fois.
private final class ResumeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    /// Renvoie `true` la première fois, `false` ensuite.
    func set() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

// MARK: - XML descriptor parser

/// Parser minimal du descripteur UPnP root device. On ne s'intéresse qu'au
/// premier `<device>` (le root), et seulement aux 4 champs utiles.
private final class SSDPDescriptorParser: NSObject, XMLParserDelegate {
    struct Result {
        var friendlyName: String?
        var modelName: String?
        var manufacturer: String?
        var deviceType: String?
    }
    var result = Result()

    private var currentText: String = ""
    private var depth: Int = 0
    private var inRootDevice: Bool = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        if elementName == "device" {
            depth += 1
            if depth == 1 { inRootDevice = true }
        }
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if inRootDevice && depth == 1 && !value.isEmpty {
            switch elementName {
            case "friendlyName": if result.friendlyName == nil { result.friendlyName = value }
            case "modelName":    if result.modelName    == nil { result.modelName    = value }
            case "manufacturer": if result.manufacturer == nil { result.manufacturer = value }
            case "deviceType":   if result.deviceType   == nil { result.deviceType   = value }
            default: break
            }
        }
        if elementName == "device" {
            depth -= 1
            if depth == 0 { inRootDevice = false }
        }
        currentText = ""
    }
}

// MARK: - UPnPInfo merging

extension UPnPInfo {
    /// Fusionne deux relevés (un device peut répondre à plusieurs ST avec des
    /// descripteurs équivalents). On garde la première valeur non-nil rencontrée
    /// par champ.
    func merging(other: UPnPInfo) -> UPnPInfo {
        UPnPInfo(
            friendlyName: friendlyName ?? other.friendlyName,
            modelName:    modelName    ?? other.modelName,
            manufacturer: manufacturer ?? other.manufacturer,
            deviceType:   deviceType   ?? other.deviceType,
            server:       server       ?? other.server
        )
    }
}
