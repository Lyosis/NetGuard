import Foundation

// MARK: - NetworkDevice → clé de persistance

extension NetworkDevice {
    /// Clé stable pour la persistance : MAC normalisée (minuscules, sans séparateurs),
    /// ou "ip:<ip>" si la MAC est absente (gateway sans ARP, device virtuel…).
    var persistenceKey: String {
        let normalized = mac
            .lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        return normalized.isEmpty ? "ip:\(ip)" : normalized
    }
}

// MARK: - PersistedDevice ↔ NetworkDevice

extension PersistedDevice {

    // MARK: NetworkDevice → PersistedDevice (factory)

    static func make(from device: NetworkDevice) -> PersistedDevice {
        let enc = JSONEncoder()
        return PersistedDevice(
            persistenceKey:      device.persistenceKey,
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
