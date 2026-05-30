import Foundation
import Security

// MARK: - CertificateInspector
/// Extrait un `CertificateInfo` depuis un `SecTrust` reçu via
/// `URLSessionDelegate.urlSession(_:didReceive challenge:)`.
///
/// Toutes les APIs utilisées sont disponibles dès macOS 13 (cible NetGuard
/// = macOS 26). Aucune méthode n'est isolée par un acteur — `inspect(trust:)`
/// peut être appelée depuis un acteur ou un contexte non isolé.
enum CertificateInspector {

    /// Analyse un `SecTrust` et renvoie un snapshot de son certificat leaf.
    /// Renvoie `nil` si la chaîne est vide ou inaccessible.
    static func inspect(trust: SecTrust) -> CertificateInfo? {
        // 1. Validation : SecTrustEvaluateWithError (macOS 10.14+)
        var cfError: CFError?
        let isTrusted = SecTrustEvaluateWithError(trust, &cfError)
        let errorDescription: String? = cfError.map { CFErrorCopyDescription($0) as String }

        // 2. Chaîne complète (macOS 12+, remplace SecTrustGetCertificateAtIndex)
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf  = chain.first else {
            return nil
        }

        // 3. Sujet (CN ou résumé déjà formaté)
        let subject = (SecCertificateCopySubjectSummary(leaf) as String?) ?? "—"

        // 4. Émetteur (best-effort via SecCertificateCopyValues)
        let issuer = extractIssuerCN(from: leaf) ?? "—"

        // 5. Dates de validité (macOS 13+)
        let validFrom = (SecCertificateCopyNotValidBeforeDate(leaf) as Date?) ?? .distantPast
        let validTo   = (SecCertificateCopyNotValidAfterDate(leaf)  as Date?) ?? .distantFuture

        // 6. Auto-signé : comparaison des séquences DER normalisées (robuste)
        let isSelfSigned = isCertSelfSigned(leaf, chainLength: chain.count)

        // 7. Expiré : dérivé
        let isExpired = validTo < Date()

        return CertificateInfo(
            subject: subject,
            issuer: issuer,
            validFrom: validFrom,
            validTo: validTo,
            isSelfSigned: isSelfSigned,
            isExpired: isExpired,
            isTrusted: isTrusted,
            trustErrorDescription: errorDescription
        )
    }

    // MARK: - Helpers privés

    /// Compare les séquences DER normalisées du sujet et de l'émetteur.
    /// Si elles sont identiques (ou si la chaîne ne contient qu'un certificat),
    /// le certificat est auto-signé.
    private static func isCertSelfSigned(_ cert: SecCertificate, chainLength: Int) -> Bool {
        let subjectDER = SecCertificateCopyNormalizedSubjectSequence(cert) as Data?
        let issuerDER  = SecCertificateCopyNormalizedIssuerSequence(cert)  as Data?
        if let s = subjectDER, let i = issuerDER, s == i { return true }
        return chainLength == 1
    }

    /// Extrait le Common Name (CN) du champ Issuer via `SecCertificateCopyValues`.
    /// La structure renvoyée est un dictionnaire imbriqué selon l'OID demandé ;
    /// on parcourt la séquence pour trouver l'entrée CN.
    private static func extractIssuerCN(from cert: SecCertificate) -> String? {
        let keys = [kSecOIDX509V1IssuerName] as CFArray
        guard let values = SecCertificateCopyValues(cert, keys, nil) as? [String: Any],
              let entry    = values[kSecOIDX509V1IssuerName as String] as? [String: Any],
              let sequence = entry["value"] as? [[String: Any]]
        else { return nil }

        let cnKey = kSecOIDCommonName as String
        for item in sequence {
            if let label = item["label"] as? String, label == cnKey,
               let value = item["value"] as? String {
                return value
            }
        }
        // Fallback : premier composant lisible (Organisation par exemple)
        for item in sequence {
            if let value = item["value"] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

// MARK: - CertificateCapturingDelegate
/// `URLSessionDelegate` qui :
///   1. Accepte le challenge SSL (pour permettre la connexion sur le réseau
///      local, certificats auto-signés inclus).
///   2. Stocke le `SecTrust` reçu, indexé par hôte, pour analyse a posteriori
///      par `CertificateInspector`.
///
/// Marqué `@unchecked Sendable` : l'accès au dictionnaire interne passe par
/// une `DispatchQueue` sérialisée.
final class CertificateCapturingDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {

    private let queue = DispatchQueue(label: "netguard.cert.capture", qos: .utility)
    private var trustByHost: [String: SecTrust] = [:]

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        queue.async { self.trustByHost[host] = trust }

        // Toujours accepter — le but est de capter le cert, pas de bloquer
        // (NetGuard scanne le réseau local où les self-signed sont la norme).
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    /// Renvoie le `SecTrust` capté pour cet hôte (ou nil si rien capté).
    func capturedTrust(for host: String) -> SecTrust? {
        queue.sync { trustByHost[host] }
    }
}
