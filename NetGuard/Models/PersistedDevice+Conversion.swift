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
        Self.deviceIdentity(mac: mac, ip: ip)
    }

    /// Formule unique de l'identité, partagée avec `PersistedDevice.deviceIdentity`.
    static func deviceIdentity(mac: String, ip: String) -> String {
        let normalized = mac.lowercased().filter(\.isHexDigit)
        if !normalized.isEmpty { return "mac:\(normalized)" }
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

// MARK: - PersistedDevice ↔ NetworkDevice

extension PersistedDevice {

    /// Identité de l'appareil, lue sur les colonnes de la fiche — sans décoder ses JSON.
    var deviceIdentity: String {
        NetworkDevice.deviceIdentity(mac: mac, ip: ip)
    }

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
