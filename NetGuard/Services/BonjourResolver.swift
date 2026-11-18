import Foundation
import dnssd

// MARK: - BonjourResolver
/// Adresse IPv4 d'un service Bonjour, **sans aucune connexion vers l'appareil**.
///
/// Jusqu'à la 1.1.5, NetGuard ouvrait une connexion TCP vers chaque service découvert pour
/// lire l'adresse du chemin. L'adresse contactée était celle que l'appareil annonce
/// lui-même : un appareil hostile du réseau local pouvait faire ouvrir à NetGuard une
/// connexion vers Internet. Mesuré le 2026-11-18 dans le journal Network.framework :
/// 35 connexions pour 35 services avec l'ancienne méthode, 0 avec celle-ci, pour les mêmes
/// 35 services résolus.
///
/// Deux requêtes au service Bonjour du système (mDNSResponder) :
/// 1. `DNSServiceResolve` : nom d'hôte cible du service (`NAS-218.local.`) ;
/// 2. `DNSServiceGetAddrInfo`, restreint à l'IPv4 : adresse de cet hôte.
///
/// Seules les cibles en `.local.` sont résolues : une cible hors `.local.` partirait en DNS
/// unicast, vers le résolveur configuré sur le Mac (souvent extérieur), avec un nom choisi
/// par l'appareil qui l'annonce.
enum BonjourResolver {

    /// Adresses IPv4 de l'hôte du service, en notation pointée. Vide si la cible n'est pas
    /// en `.local.`, en cas d'échec, ou si rien n'est arrivé avant le délai.
    ///
    /// **Toutes** les adresses sont rendues : un hôte en a souvent plusieurs. Mesuré le
    /// 2026-11-18 pour ce Mac : `127.0.0.1`, `10.211.55.2` et `10.37.129.2` (Parallels),
    /// puis `192.168.1.96` en dernier. Ne garder que la première perdait l'adresse du LAN.
    static func ipv4Addresses(
        name: String,
        type: String,
        domain: String,
        timeout: TimeInterval = 2.0
    ) async -> [String] {
        let lookup = Lookup()
        return await withCheckedContinuation { continuation in
            lookup.queue.async { lookup.start(name: name, type: type, domain: domain,
                                              timeout: timeout, continuation: continuation) }
        }
    }

    /// Vrai si le nom d'hôte cible est un nom mDNS du lien local.
    static func isLinkLocalHost(_ hostTarget: String) -> Bool {
        let host = hostTarget.lowercased()
        return host.hasSuffix(".local.") || host.hasSuffix(".local")
    }

    /// Adresse IPv4 en notation pointée, construite à partir de ses octets.
    ///
    /// La description texte de `NWIPv4Address` portait la portée de l'interface
    /// (`192.168.1.73%en0`) : indexée telle quelle, elle ne correspondait jamais à l'IP
    /// d'un appareil. Les octets n'ont pas ce défaut.
    static func dottedQuad(_ bytes: Data) -> String? {
        guard bytes.count == 4 else { return nil }
        return bytes.map { String($0) }.joined(separator: ".")
    }

    // MARK: - Une résolution

    /// État d'une résolution, partagé avec les rappels C de `dnssd`.
    ///
    /// Tout se passe sur `queue` : démarrage, rappels (`DNSServiceSetDispatchQueue`),
    /// délai, libération des `DNSServiceRef`. Le résultat n'est rendu qu'une fois (`done`).
    /// Le rappel reçoit l'objet par un pointeur non géré : une référence est retenue au
    /// démarrage et rendue à un seul endroit, l'expiration du délai, qui s'exécute toujours
    /// et après laquelle aucun rappel ne peut plus arriver (références libérées).
    private final class Lookup: @unchecked Sendable {
        let queue = DispatchQueue(label: "netguard.bonjour.resolve", qos: .utility)
        private var ref: DNSServiceRef?
        private var done = false
        private var continuation: CheckedContinuation<[String], Never>?
        private var addresses: [String] = []

        func start(name: String, type: String, domain: String, timeout: TimeInterval,
                   continuation: CheckedContinuation<[String], Never>) {
            self.continuation = continuation
            let context = Unmanaged.passRetained(self).toOpaque()
            queue.asyncAfter(deadline: .now() + timeout) {
                // Délai dépassé : rendre ce qui est arrivé, même incomplet.
                let lookup = Unmanaged<Lookup>.fromOpaque(context).takeRetainedValue()
                lookup.finish()
            }

            var newRef: DNSServiceRef?
            let error = DNSServiceResolve(&newRef, 0, 0, name, type, domain,
                                          Lookup.resolveReply, context)
            guard error == kDNSServiceErr_NoError, let newRef else { finish(); return }
            attach(newRef)
        }

        /// Rend les adresses reçues une seule fois et libère la requête en cours.
        fileprivate func finish() {
            releaseRef()
            guard !done else { return }
            done = true
            continuation?.resume(returning: addresses)
            continuation = nil
        }

        private func attach(_ newRef: DNSServiceRef) {
            ref = newRef
            if DNSServiceSetDispatchQueue(newRef, queue) != kDNSServiceErr_NoError { finish() }
        }

        private func releaseRef() {
            if let current = ref {
                DNSServiceRefDeallocate(current)
                ref = nil
            }
        }

        /// Étape 1 : cible du service. Enchaîne sur l'adresse IPv4 de la cible.
        private static let resolveReply: DNSServiceResolveReply = {
            _, _, _, error, _, hostTarget, _, _, _, context in
            guard let context else { return }
            let lookup = Unmanaged<Lookup>.fromOpaque(context).takeUnretainedValue()
            guard !lookup.done else { return }
            guard error == kDNSServiceErr_NoError, let hostTarget,
                  BonjourResolver.isLinkLocalHost(String(cString: hostTarget)) else {
                lookup.finish()
                return
            }
            lookup.releaseRef()
            var addressRef: DNSServiceRef?
            let status = DNSServiceGetAddrInfo(&addressRef, 0, 0,
                                               DNSServiceProtocol(kDNSServiceProtocol_IPv4),
                                               hostTarget, Lookup.addressReply, context)
            guard status == kDNSServiceErr_NoError, let addressRef else {
                lookup.finish()
                return
            }
            lookup.attach(addressRef)
        }

        /// Étape 2 : adresses IPv4 de la cible, une par rappel. Le dernier rappel d'une
        /// série n'a plus l'indicateur `MoreComing` : c'est là que la résolution se termine.
        private static let addressReply: DNSServiceGetAddrInfoReply = {
            _, flags, _, error, _, address, _, context in
            guard let context else { return }
            let lookup = Unmanaged<Lookup>.fromOpaque(context).takeUnretainedValue()
            guard !lookup.done else { return }
            if error == kDNSServiceErr_NoError, let address,
               flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0,
               address.pointee.sa_family == sa_family_t(AF_INET) {
                let ipv4 = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                let bytes = withUnsafeBytes(of: ipv4) { Data($0) }
                if let dotted = BonjourResolver.dottedQuad(bytes), !lookup.addresses.contains(dotted) {
                    lookup.addresses.append(dotted)
                }
            }
            if flags & DNSServiceFlags(kDNSServiceFlagsMoreComing) == 0, !lookup.addresses.isEmpty {
                lookup.finish()
            }
        }
    }
}
