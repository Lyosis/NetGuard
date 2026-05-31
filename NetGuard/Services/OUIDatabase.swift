import Foundation

// MARK: - OUIDatabase
/// Base IEEE des préfixes MAC bundlée (~57 000 entrées, source Wireshark `manuf`).
/// Gère les sous-allocations /24, /28, /36 — un OUI partagé entre plusieurs
/// fabricants est résolu en cherchant le préfixe le plus long d'abord.
///
/// Format de `manuf.txt` (3 colonnes tab-séparées) :
/// ```
/// 48:E1:E9         	MerossTechno	Chengdu Meross Technology Co., Ltd.
/// 00:1B:C5:00:00/36	Converging  	Converging Systems Inc.
/// ```
actor OUIDatabase {

    static let shared = OUIDatabase()
    private init() {}

    // MARK: - État
    private var prefixToVendor: [String: String] = [:]
    private var prefixLengths: [Int] = []   // triées décroissantes pour le lookup
    private var loaded = false

    // MARK: - Lookup
    /// Renvoie le nom du fabricant pour ce MAC, ou nil si introuvable.
    /// Le premier appel déclenche le chargement (~100-200 ms, en mémoire).
    func lookup(mac: String) -> String? {
        loadIfNeeded()
        let hex = normalize(mac)
        guard !hex.isEmpty else { return nil }

        for length in prefixLengths {
            guard hex.count >= length else { continue }
            let prefix = String(hex.prefix(length))
            if let vendor = prefixToVendor[prefix] { return vendor }
        }
        return nil
    }

    /// Précharge la base en arrière-plan pour éviter la latence au premier scan.
    /// À appeler au démarrage de l'app.
    func preload() async {
        loadIfNeeded()
    }

    // MARK: - Chargement (au premier accès)
    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true   // évite tout double chargement même si load() est lent

        guard let url = Bundle.main.url(forResource: "manuf", withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }

        var lengths = Set<Int>()
        for rawLine in content.split(whereSeparator: { $0.isNewline }) {
            // Ignorer commentaires et lignes vides
            let line = rawLine
            if line.first == "#" || line.isEmpty { continue }

            // Tab-separated : MAC \t short \t long
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 2 else { continue }

            let macField  = String(fields[0]).trimmingCharacters(in: .whitespaces)
            let shortName = String(fields[1]).trimmingCharacters(in: .whitespaces)
            let longName  = fields.count >= 3
                ? String(fields[2]).trimmingCharacters(in: .whitespaces)
                : ""
            let vendor = longName.isEmpty ? shortName : longName
            guard !vendor.isEmpty else { continue }

            let (prefix, hexChars) = parseMacField(macField)
            guard hexChars > 0, !prefix.isEmpty else { continue }

            prefixToVendor[prefix] = vendor
            lengths.insert(hexChars)
        }
        // Plus le préfixe est long, plus il est spécifique → lookup en premier
        prefixLengths = lengths.sorted(by: >)
    }

    // MARK: - Helpers

    /// Normalise une MAC en hex pur uppercase : `48:e1:e9:bc:a2:8b` → `48E1E9BCA28B`.
    private func normalize(_ mac: String) -> String {
        mac.replacingOccurrences(of: ":", with: "")
           .replacingOccurrences(of: "-", with: "")
           .uppercased()
    }

    /// Parse le champ MAC du fichier manuf :
    /// - `48:E1:E9` → (`48E1E9`, 6)        [/24 implicite, 24 bits = 6 hex chars]
    /// - `00:1B:C5:00:00/36` → (`001BC50000`, 9) [36 bits = 9 hex chars]
    private func parseMacField(_ field: String) -> (String, Int) {
        let macPart: Substring
        let bits: Int
        if let slash = field.firstIndex(of: "/") {
            macPart = field[..<slash]
            bits = Int(field[field.index(after: slash)...]) ?? 24
        } else {
            macPart = Substring(field)
            bits = 24
        }
        let hexChars = bits / 4
        let hex = macPart
            .replacingOccurrences(of: ":", with: "")
            .uppercased()
        return (String(hex.prefix(hexChars)), hexChars)
    }
}
