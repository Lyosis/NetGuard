import Foundation

// MARK: - UserAnnotationsStore
/// Persistance des annotations utilisateur (nom personnalisé + notes) sur les
/// appareils, indexées par adresse MAC (identifiant stable entre les scans).
///
/// Stop-gap **UserDefaults** en attendant la persistance SwiftData (A5 du CDC).
/// La clé est `netguard.user_annotations.v1` — le `.v1` permet une migration
/// future sans casser les données existantes.
@MainActor
final class UserAnnotationsStore {

    static let shared = UserAnnotationsStore()
    private init() {}

    // MARK: Modèle interne
    private struct Annotation: Codable {
        var alias: String
        var note: String
    }

    // MARK: État
    private let defaultsKey = "netguard.user_annotations.v1"
    private var cache: [String: Annotation] = [:]   // clé = MAC normalisée
    private var loaded = false

    // MARK: API publique

    /// Renvoie (alias, note) pour le MAC donné, ou ("", "") si absent.
    func annotation(for mac: String) -> (alias: String, note: String) {
        loadIfNeeded()
        guard let key = normalize(mac), let a = cache[key] else { return ("", "") }
        return (a.alias, a.note)
    }

    /// Sauvegarde l'annotation. Si alias et note sont vides → supprime l'entrée.
    /// Si le MAC est vide → ne persiste rien (pas d'identifiant stable).
    func save(mac: String, alias: String, note: String) {
        loadIfNeeded()
        guard let key = normalize(mac) else { return }
        if alias.isEmpty && note.isEmpty {
            cache.removeValue(forKey: key)
        } else {
            cache[key] = Annotation(alias: alias, note: note)
        }
        persist()
    }

    // MARK: Helpers

    /// Normalise le MAC pour servir de clé stable : minuscules, sans séparateurs.
    /// « CE:E6:4D:1F:DA:82 » → « cee64d1fda82 ».
    private func normalize(_ mac: String) -> String? {
        let cleaned = mac
            .lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        return cleaned.isEmpty ? nil : cleaned
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: Annotation].self, from: data)
        else { return }
        cache = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
