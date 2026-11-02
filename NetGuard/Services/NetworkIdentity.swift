import Foundation

// MARK: - Identité du réseau courant

enum NetworkIdentity {

    /// Identifiant du réseau courant.
    ///
    /// La MAC de la passerelle est préférée au SSID : elle existe aussi en Ethernet,
    /// survit à un renommage du réseau, et distingue deux réseaux qui partageraient
    /// le même plan d'adressage — `192.168.1.0/24` étant tout sauf discriminant.
    ///
    /// - Parameter knownDevices: résultat d'un scan, si disponible. Évite un appel
    ///   à `arp` quand la passerelle vient d'être vue.
    static func identifier(
        gatewayIP: String,
        subnetCIDR: String,
        knownDevices: [NetworkDevice] = []
    ) -> String {
        if let mac = knownDevices.first(where: { $0.ip == gatewayIP })?.normalizedMAC,
           !mac.isEmpty {
            return "gw:\(mac)"
        }
        if let mac = gatewayMAC(gatewayIP), !mac.isEmpty {
            return "gw:\(mac)"
        }
        // Repli faible mais borné : deux réseaux au même plan d'adressage seraient
        // confondus. N'arrive que si la passerelle n'a pas encore répondu à l'ARP.
        return "net:\(subnetCIDR)"
    }

    /// Lit la MAC de la passerelle dans la table ARP du système.
    ///
    /// Doublon du lecteur de `NetworkScanner.readARPTable()`, assumé le temps que le
    /// lecteur ARP commun de la branche `feature/arp-helper` les remplace tous les deux.
    private static func gatewayMAC(_ ip: String) -> String? {
        // Défense en profondeur (cf. #30) : jamais d'argument non validé dans un argv.
        guard IPv4.isValid(ip) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-n", ip]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard let regex = try? NSRegularExpression(pattern: #"at ([0-9a-f:]+)"#, options: .caseInsensitive) else {
            return nil
        }
        let ns = output as NSString
        guard let match = regex.firstMatch(in: output, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges == 2 else { return nil }
        let mac = ns.substring(with: match.range(at: 1)).lowercased().filter(\.isHexDigit)
        return mac.isEmpty ? nil : mac
    }
}
