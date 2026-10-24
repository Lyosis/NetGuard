import SwiftData

// MARK: - NetGuardSchemaV2
/// Schéma courant : ajoute `PersistedDevice.networkID` (identité d'appareil portée par
/// réseau).
///
/// Référence les modèles vivants. Au prochain changement de schéma, **figer d'abord
/// cette version** — copier ici les modèles tels qu'ils sont, comme dans
/// `NetGuardSchemaV1` — avant de modifier les modèles vivants.
enum NetGuardSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [PersistedDevice.self, ScanSnapshot.self]
    }
}
