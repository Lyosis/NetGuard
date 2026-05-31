import Foundation
import SwiftData

// MARK: - PersistedDevice
/// Modèle SwiftData représentant un appareil réseau connu.
/// Seule cette classe touche la base SwiftData — NetworkDevice reste un ViewModel SwiftUI pur.
/// Les types complexes (OpenPort, UPnPInfo, CertificateInfo) sont sérialisés en JSON Data
/// car SwiftData ne supporte pas nativement les tableaux de types Codable non-primitifs.
@Model
final class PersistedDevice {

    /// Clé stable unique : MAC normalisée (minuscules, sans séparateurs),
    /// ou "ip:<ip>" si la MAC est absente (ex : gateway sans ARP response).
    @Attribute(.unique) var persistenceKey: String

    var mac: String
    var ip: String
    var hostname: String
    var mdnsName: String
    var netbiosName: String
    var vendor: String
    var typeRaw: String              // DeviceType.rawValue
    var osGuessRaw: String           // OSGuess.rawValue
    var httpBanner: String
    var httpTitle: String
    var firstSeen: Date
    var lastSeen: Date
    var parentIP: String?
    var bonjourServices: [String]    // [String] supporté nativement par SwiftData
    var userAlias: String
    var userNote: String
    var userOverrideTypeRaw: String? // DeviceType.rawValue, nil = pas d'override
    var openPortsJSON: Data          // JSON [OpenPort]
    var upnpJSON: Data?              // JSON UPnPInfo
    var sslJSON: Data?               // JSON CertificateInfo
    var isCurrentDevice: Bool
    var responseTime: Double
    var ttlValue: Int

    init(
        persistenceKey: String,
        mac: String,
        ip: String,
        hostname: String = "",
        mdnsName: String = "",
        netbiosName: String = "",
        vendor: String = "",
        typeRaw: String = DeviceType.unknown.rawValue,
        osGuessRaw: String = OSGuess.unknown.rawValue,
        httpBanner: String = "",
        httpTitle: String = "",
        firstSeen: Date = Date(),
        lastSeen: Date = Date(),
        parentIP: String? = nil,
        bonjourServices: [String] = [],
        userAlias: String = "",
        userNote: String = "",
        userOverrideTypeRaw: String? = nil,
        openPortsJSON: Data = Data(),
        upnpJSON: Data? = nil,
        sslJSON: Data? = nil,
        isCurrentDevice: Bool = false,
        responseTime: Double = 0,
        ttlValue: Int = 0
    ) {
        self.persistenceKey     = persistenceKey
        self.mac                = mac
        self.ip                 = ip
        self.hostname           = hostname
        self.mdnsName           = mdnsName
        self.netbiosName        = netbiosName
        self.vendor             = vendor
        self.typeRaw            = typeRaw
        self.osGuessRaw         = osGuessRaw
        self.httpBanner         = httpBanner
        self.httpTitle          = httpTitle
        self.firstSeen          = firstSeen
        self.lastSeen           = lastSeen
        self.parentIP           = parentIP
        self.bonjourServices    = bonjourServices
        self.userAlias          = userAlias
        self.userNote           = userNote
        self.userOverrideTypeRaw = userOverrideTypeRaw
        self.openPortsJSON      = openPortsJSON
        self.upnpJSON           = upnpJSON
        self.sslJSON            = sslJSON
        self.isCurrentDevice    = isCurrentDevice
        self.responseTime       = responseTime
        self.ttlValue           = ttlValue
    }
}
