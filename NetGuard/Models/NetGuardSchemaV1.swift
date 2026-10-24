import Foundation
import SwiftData

// MARK: - NetGuardSchemaV1
/// Schéma **figé** des versions 1.0 à 1.1.3 — identique sur toute cette période
/// (`git diff v1.0 v1.1.3` vide sur les modèles).
///
/// Ne jamais modifier ce fichier : SwiftData reconnaît une base existante à l'empreinte
/// de son schéma. Un attribut, un type, une optionalité ou un `.unique` différent, et
/// les bases des utilisateurs en 1.x ne sont plus reconnues — le `ModelContainer` échoue.
///
/// Les modèles sont imbriqués dans l'enum de version, comme le veut SwiftData : exception
/// assumée à la règle « un type par fichier ».
enum NetGuardSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [PersistedDevice.self, ScanSnapshot.self]
    }

    @Model
    final class PersistedDevice {
        @Attribute(.unique) var persistenceKey: String

        var mac: String
        var ip: String
        var hostname: String
        var mdnsName: String
        var netbiosName: String
        var vendor: String
        var typeRaw: String
        var osGuessRaw: String
        var httpBanner: String
        var httpTitle: String
        var firstSeen: Date
        var lastSeen: Date
        var parentIP: String?
        var bonjourServices: [String]
        var userAlias: String
        var userNote: String
        var userOverrideTypeRaw: String?
        var openPortsJSON: Data
        var upnpJSON: Data?
        var sslJSON: Data?
        var isCurrentDevice: Bool
        var responseTime: Double
        var ttlValue: Int

        init(persistenceKey: String, mac: String, ip: String) {
            self.persistenceKey      = persistenceKey
            self.mac                 = mac
            self.ip                  = ip
            self.hostname            = ""
            self.mdnsName            = ""
            self.netbiosName         = ""
            self.vendor              = ""
            self.typeRaw             = "unknown"
            self.osGuessRaw          = "unknown"
            self.httpBanner          = ""
            self.httpTitle           = ""
            self.firstSeen           = .now
            self.lastSeen            = .now
            self.parentIP            = nil
            self.bonjourServices     = []
            self.userAlias           = ""
            self.userNote            = ""
            self.userOverrideTypeRaw = nil
            self.openPortsJSON       = Data()
            self.upnpJSON            = nil
            self.sslJSON             = nil
            self.isCurrentDevice     = false
            self.responseTime        = 0
            self.ttlValue            = 0
        }
    }

    @Model
    final class ScanSnapshot {
        var id: UUID
        var date: Date
        var durationSeconds: Double
        var deviceCount: Int
        var alertCount: Int
        var newDeviceCount: Int

        init(date: Date, durationSeconds: Double, deviceCount: Int, alertCount: Int, newDeviceCount: Int) {
            self.id              = UUID()
            self.date            = date
            self.durationSeconds = durationSeconds
            self.deviceCount     = deviceCount
            self.alertCount      = alertCount
            self.newDeviceCount  = newDeviceCount
        }
    }
}
