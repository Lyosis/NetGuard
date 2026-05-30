import Foundation

// MARK: - CertificateInfo
/// Snapshot des informations extraites d'un certificat SSL serveur lors d'un
/// `GET HTTPS` (voir `CertificateInspector`).
struct CertificateInfo: Codable, Equatable {

    /// Sujet (CN ou résumé) du certificat leaf.
    var subject: String

    /// Émetteur (autorité de certification). Best-effort, peut être « — » si
    /// extraction impossible.
    var issuer: String

    /// Dates de validité issues de `SecCertificateCopyNotValidBefore/AfterDate`.
    var validFrom: Date
    var validTo: Date

    /// Vrai si l'émetteur normalisé == sujet normalisé (DER comparison).
    var isSelfSigned: Bool

    /// Dérivé : `validTo < Date()`.
    var isExpired: Bool

    /// Vrai si `SecTrustEvaluateWithError` renvoie `true`.
    var isTrusted: Bool

    /// Description lisible de l'erreur de trust si `!isTrusted`. Tirée de
    /// `CFErrorCopyDescription`.
    var trustErrorDescription: String?

    // MARK: - Helpers d'affichage

    /// Nombre de jours restants avant expiration. Négatif si déjà expiré.
    var daysUntilExpiry: Int {
        Int(validTo.timeIntervalSince(Date()) / 86_400)
    }

    /// Vrai si expire dans moins de 30 jours.
    var isNearExpiry: Bool {
        !isExpired && daysUntilExpiry <= 30
    }
}
