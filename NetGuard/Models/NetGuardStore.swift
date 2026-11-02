import Foundation
import SwiftData

// MARK: - Emplacement et ouverture du store SwiftData

/// Store SwiftData propre à NetGuard.
///
/// NetGuard n'est pas sandboxé : sans emplacement explicite, SwiftData écrit dans
/// `~/Library/Application Support/default.store`, **le même fichier que toute autre app
/// non sandboxée** qui laisse l'emplacement par défaut. Constaté le 2026-10-27 : ce
/// fichier a été remplacé par celui d'une autre app (table `ZAPIREQUESTMODEL`), et les
/// appareils connus ont disparu. Le store vit donc dans un dossier à l'identifiant de l'app.
enum NetGuardStore {

    /// Résultat de l'ouverture. `failure` non nil : le store sur disque n'a pas pu être
    /// ouvert, le conteneur est en mémoire et rien ne survivra au lancement.
    struct Opening {
        let container: ModelContainer
        let failure: Error?
    }

    private static let schema = Schema(versionedSchema: NetGuardSchemaV2.self)

    /// Fichiers d'une base SQLite en mode WAL : sans `-wal`, les dernières écritures
    /// seraient perdues à la copie.
    private static let sqliteSuffixes = ["", "-wal", "-shm"]

    static func open() -> Opening {
        let fm = FileManager.default
        let directory = URL.applicationSupportDirectory.appending(
            path: Bundle.main.bundleIdentifier ?? "com.wilfrid.B.netguard.app",
            directoryHint: .isDirectory
        )
        let storeURL = directory.appending(path: "NetGuard.store")

        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return Opening(container: inMemoryContainer(), failure: error)
        }

        let adopted = !fm.fileExists(atPath: storeURL.path) && adoptLegacyStore(at: storeURL)
        do {
            return Opening(container: try diskContainer(at: storeURL), failure: nil)
        } catch {
            guard adopted else {
                // Le store dédié existe mais ne s'ouvre pas : ne jamais l'effacer, ce
                // sont les données de l'utilisateur. Fonctionner en mémoire, et le dire.
                print("[NetGuard] Store illisible, fonctionnement en mémoire : \(error)")
                return Opening(container: inMemoryContainer(), failure: error)
            }
            // L'ancien store n'était pas celui de NetGuard : retirer notre copie et
            // repartir d'un store vide. L'original n'a jamais été touché.
            print("[NetGuard] default.store n'appartient pas à NetGuard, ignoré : \(error)")
            removeStoreFiles(at: storeURL)
            do {
                return Opening(container: try diskContainer(at: storeURL), failure: nil)
            } catch {
                return Opening(container: inMemoryContainer(), failure: error)
            }
        }
    }

    /// Reprise unique de l'ancien emplacement (versions 1.0 à 1.1.3).
    ///
    /// **Copie**, jamais déplacement : `default.store` peut appartenir à une autre app.
    /// C'est l'ouverture de la copie avec le schéma de NetGuard qui dira s'il était le
    /// sien — un store étranger est refusé par le plan de migration, sans écriture.
    /// Retourne vrai si une copie a été faite.
    private static func adoptLegacyStore(at storeURL: URL) -> Bool {
        let fm = FileManager.default
        let legacyURL = URL.applicationSupportDirectory.appending(path: "default.store")
        guard fm.fileExists(atPath: legacyURL.path) else { return false }
        do {
            for suffix in sqliteSuffixes {
                let source = URL(filePath: legacyURL.path + suffix)
                guard fm.fileExists(atPath: source.path) else { continue }
                try fm.copyItem(at: source, to: URL(filePath: storeURL.path + suffix))
            }
            print("[NetGuard] Ancien store copié vers \(storeURL.path)")
            return true
        } catch {
            print("[NetGuard] Copie de l'ancien store impossible : \(error)")
            removeStoreFiles(at: storeURL)
            return false
        }
    }

    private static func removeStoreFiles(at storeURL: URL) {
        for suffix in sqliteSuffixes {
            try? FileManager.default.removeItem(at: URL(filePath: storeURL.path + suffix))
        }
    }

    private static func diskContainer(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: NetGuardMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
    }

    /// Repli : l'app reste utilisable, sans persistance. Un schéma qui ne se charge même
    /// pas en mémoire est un défaut du build lui-même, pas une situation à rattraper.
    private static func inMemoryContainer() -> ModelContainer {
        do {
            return try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
        } catch {
            fatalError("[NetGuard] Schéma SwiftData inutilisable, même en mémoire : \(error)")
        }
    }
}
