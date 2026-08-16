import Foundation

// MARK: - ScanThrottle
/// Plafond de concurrence **global**, partagé par toutes les étapes de scan.
///
/// Contexte — issue #41 : un scan complet ouvrait ~1 500 connexions en 9 s
/// (~165/s). Certains pare-feux tiers résolvent le nom d'hôte de chaque IP
/// observée de façon synchrone, sur le pool dispatch global. À ce débit leur
/// pool sature (limite de 64 threads contraints), ils cessent de rendre des
/// verdicts, et `connect()` ne rend plus la main : toute la pile socket de la
/// machine se fige jusqu'au redémarrage.
///
/// Borner la concurrence *par étape* ne suffisait pas — deux étapes qui se
/// recouvrent cumulent leurs plafonds. Le jeton est donc unique et global.
///
/// - Important: ne **jamais** imbriquer deux `run { }`. Le second attendrait un
///   jeton que seul le premier peut libérer → interblocage. Un seul niveau, au
///   plus près de la connexion réseau.
actor ScanThrottle {

    /// Instance partagée par `NetworkScanner` et `PortScanner`.
    ///
    /// 16 jetons : au-delà, le débit d'adresses distinctes par seconde repasse
    /// dans la zone qui fait saturer les pare-feux tiers (mesures de l'issue
    /// #41). En dessous, le scan s'allonge sans bénéfice observé.
    static let shared = ScanThrottle(limit: 16)

    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    /// Exécute `operation` en occupant un jeton, après attente s'il n'en reste aucun.
    func run<T: Sendable>(_ operation: @Sendable () async -> T) async -> T {
        await acquire()
        defer { release() }
        return await operation()
    }

    private func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
        // Jeton transmis directement par `release()` : `active` reste inchangé.
    }

    private func release() {
        if waiters.isEmpty {
            active -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
