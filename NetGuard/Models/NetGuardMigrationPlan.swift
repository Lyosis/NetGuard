import SwiftData

// MARK: - NetGuardMigrationPlan
/// Migrations du schéma SwiftData, explicites plutôt qu'inférées.
///
/// Ne couvre que la **structure**. La réécriture des clés de persistance au format
/// porté par réseau reste dans `AppState.migrateDeviceIdentityIfNeeded()` : elle a
/// besoin de la MAC de la passerelle, inconnue au moment où le conteneur s'ouvre.
enum NetGuardMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [NetGuardSchemaV1.self, NetGuardSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [v1ToV2]
    }

    /// Ajout de `networkID`, avec une valeur par défaut : migration légère.
    static let v1ToV2 = MigrationStage.lightweight(
        fromVersion: NetGuardSchemaV1.self,
        toVersion: NetGuardSchemaV2.self
    )
}
