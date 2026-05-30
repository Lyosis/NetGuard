import Foundation

// MARK: - ScanCache
/// Persiste le **dernier scan** (devices + alertes + date) dans un fichier JSON
/// pour que l'app les retrouve au prochain démarrage.
///
/// Stop-gap en attendant SwiftData (A5) qui apportera l'historique complet (A6).
/// Quand A5 arrivera, on lira ce fichier une fois pour migrer puis on le
/// supprimera.
///
/// Emplacement : `~/Library/Application Support/NetGuard/last-scan.json`
@MainActor
final class ScanCache {

    static let shared = ScanCache()

    // MARK: - Snapshot persisté
    private struct Snapshot: Codable {
        var date: Date
        var networkLabel: String       // ex: « WiFi en0 — 192.168.1.0/24 »
        var devices: [NetworkDevice]
        var alerts: [NetworkAlert]
    }

    // MARK: - Emplacement disque
    private let fileURL: URL

    private init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let dir = support.appendingPathComponent("NetGuard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("last-scan.json")
    }

    // MARK: - Sauvegarde
    /// À appeler à la fin de chaque scan (complet ou rapide).
    func save(devices: [NetworkDevice],
              alerts: [NetworkAlert],
              networkLabel: String) {
        let snap = Snapshot(date: Date(),
                            networkLabel: networkLabel,
                            devices: devices,
                            alerts: alerts)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(snap)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Pas critique : on log et on continue
            print("[ScanCache] save failed: \(error)")
        }
    }

    // MARK: - Chargement
    /// À appeler une fois au démarrage. Renvoie `nil` si pas de cache valide.
    func load() -> (date: Date, devices: [NetworkDevice], alerts: [NetworkAlert], networkLabel: String)? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snap = try? decoder.decode(Snapshot.self, from: data) else { return nil }
        return (snap.date, snap.devices, snap.alerts, snap.networkLabel)
    }

    /// Efface le cache. Utile pour debug ou réinit utilisateur.
    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
