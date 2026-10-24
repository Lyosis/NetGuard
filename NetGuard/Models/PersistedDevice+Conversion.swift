import Foundation

// MARK: - NetworkDevice → clé de persistance

extension NetworkDevice {

    /// MAC normalisée : minuscules, sans séparateurs. Vide si absente.
    var normalizedMAC: String {
        mac.lowercased().filter(\.isHexDigit)
    }

    /// Identité de l'appareil, indépendante du réseau.
    ///
    /// La MAC, constructeur ou privée : c'est la seule donnée que **tous** les scans
    /// mesurent, dès la découverte. Une clé ne doit dépendre que de ce type de donnée et
    /// ne jamais changer au cours d'un scan. Une version antérieure se rabattait sur le
    /// nom mDNS pour les MAC privées : ce nom n'étant mesuré qu'à l'enrichissement d'un
    /// scan complet, la clé changeait en cours de scan — fausse alerte d'intrusion et
    /// fiche en double.
    ///
    /// Une MAC privée (iOS, Android) peut tourner : l'appareil réapparaît alors comme
    /// nouveau. Mesuré sur un réseau réel, elles restent stables plusieurs mois ; le
    /// rapprochement par nom, s'il devient nécessaire, se fera au moment de l'alerte,
    /// jamais dans la clé.
    var deviceIdentity: String {
        let mac = normalizedMAC
        if !mac.isEmpty { return "mac:\(mac)" }
        return "ip:\(ip)"
    }

    /// Clé de persistance, portée par réseau.
    ///
    /// Le même appareil vu sur deux réseaux différents donne deux entrées distinctes :
    /// c'est voulu. Sans cette portée, brancher la machine sur un autre réseau signalait
    /// chacun de ses appareils comme une intrusion.
    func persistenceKey(networkID: String) -> String {
        "\(networkID)|\(deviceIdentity)"
    }
}

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

// MARK: - PersistedDevice ↔ NetworkDevice

extension PersistedDevice {

    // MARK: NetworkDevice → PersistedDevice (factory)

    static func make(from device: NetworkDevice, networkID: String) -> PersistedDevice {
        let enc = JSONEncoder()
        return PersistedDevice(
            persistenceKey:      device.persistenceKey(networkID: networkID),
            networkID:           networkID,
            mac:                 device.mac,
            ip:                  device.ip,
            hostname:            device.hostname,
            mdnsName:            device.mdnsName,
            netbiosName:         device.netbiosName,
            vendor:              device.vendor,
            typeRaw:             device.type.rawValue,
            osGuessRaw:          device.osGuess.rawValue,
            httpBanner:          device.httpBanner,
            httpTitle:           device.httpTitle,
            firstSeen:           device.firstSeen,
            lastSeen:            device.lastSeen,
            parentIP:            device.parentIP,
            bonjourServices:     device.bonjourServices,
            userAlias:           device.userAlias,
            userNote:            device.userNote,
            userOverrideTypeRaw: device.userOverrideType?.rawValue,
            openPortsJSON:       (try? enc.encode(device.openPorts)) ?? Data(),
            upnpJSON:            device.upnp.flatMap { try? enc.encode($0) },
            sslJSON:             device.sslCertificate.flatMap { try? enc.encode($0) },
            isCurrentDevice:     device.isCurrentDevice,
            responseTime:        device.responseTime,
            ttlValue:            device.ttl
        )
    }

    // MARK: Mise à jour in-place depuis un NetworkDevice (scan suivant)

    func update(from device: NetworkDevice) {
        let enc = JSONEncoder()
        ip                  = device.ip
        hostname            = device.hostname
        mdnsName            = device.mdnsName
        netbiosName         = device.netbiosName
        vendor              = device.vendor
        typeRaw             = device.type.rawValue
        osGuessRaw          = device.osGuess.rawValue
        httpBanner          = device.httpBanner
        httpTitle           = device.httpTitle
        lastSeen            = device.lastSeen
        parentIP            = device.parentIP
        bonjourServices     = device.bonjourServices
        userAlias           = device.userAlias
        userNote            = device.userNote
        userOverrideTypeRaw = device.userOverrideType?.rawValue
        openPortsJSON       = (try? enc.encode(device.openPorts)) ?? Data()
        upnpJSON            = device.upnp.flatMap { try? enc.encode($0) }
        sslJSON             = device.sslCertificate.flatMap { try? enc.encode($0) }
        isCurrentDevice     = device.isCurrentDevice
        responseTime        = device.responseTime
        ttlValue            = device.ttl
        // firstSeen : jamais écrasé — date du premier contact conservée
    }

    // MARK: PersistedDevice → NetworkDevice (chargement au démarrage)

    func toNetworkDevice() -> NetworkDevice {
        let dec = JSONDecoder()
        let ports   = (try? dec.decode([OpenPort].self,       from: openPortsJSON)) ?? []
        let upnpInfo = upnpJSON.flatMap { try? dec.decode(UPnPInfo.self,         from: $0) }
        let ssl      = sslJSON.flatMap  { try? dec.decode(CertificateInfo.self,  from: $0) }

        let device = NetworkDevice(
            ip:              ip,
            mac:             mac,
            hostname:        hostname,
            mdnsName:        mdnsName,
            netbiosName:     netbiosName,
            vendor:          vendor,
            type:            DeviceType(rawValue: typeRaw)  ?? .unknown,
            status:          .unknown,
            openPorts:       ports,
            isCurrentDevice: isCurrentDevice,
            responseTime:    responseTime,
            ttl:             ttlValue,
            osGuess:         OSGuess(rawValue: osGuessRaw)  ?? .unknown,
            httpBanner:      httpBanner,
            httpTitle:       httpTitle,
            parentIP:        parentIP,
            bonjourServices: bonjourServices,
            userAlias:       userAlias,
            userNote:        userNote,
            sslCertificate:  ssl,
            upnp:            upnpInfo,
            userOverrideType: userOverrideTypeRaw.flatMap { DeviceType(rawValue: $0) }
        )
        device.firstSeen  = firstSeen
        device.lastSeen   = lastSeen
        device.scanState  = .cached
        return device
    }
}
