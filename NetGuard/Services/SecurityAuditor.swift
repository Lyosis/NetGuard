import Foundation

// MARK: - SecurityAuditor
/// Audit de sécurité passif + actif léger sur un appareil du réseau local.
/// Actif uniquement sur le LAN — jamais utilisé hors du réseau local de l'utilisateur.
actor SecurityAuditor {

    static let shared = SecurityAuditor()

    // MARK: - Types publics

    struct AuditResult {
        let score: Int                  // 0 (critique) → 100 (sûr)
        let findings: [AuditFinding]
        let credentialsTested: Bool     // true si un port web était disponible
    }

    struct AuditFinding: Identifiable {
        let id = UUID()
        let severity: AlertSeverity
        let title: String
        let detail: String
    }

    // MARK: - Credentials par défaut à tester

    private let defaultCredentials: [(user: String, pass: String)] = [
        ("admin",  "admin"),
        ("admin",  "password"),
        ("admin",  ""),
        ("admin",  "1234"),
        ("admin",  "12345"),
        ("root",   "root"),
        ("user",   "user"),
        ("admin",  "admin123"),
    ]

    // MARK: - Audit principal

    func audit(device: NetworkDevice) async -> AuditResult {
        var score = 100
        var findings: [AuditFinding] = []

        let portNumbers = Set(device.openPorts.map(\.port))

        // Telnet
        if portNumbers.contains(23) {
            score -= 30
            findings.append(.init(severity: .critical,
                                  title: L10n.AuditFinding.telnetTitle,
                                  detail: L10n.AuditFinding.telnetDetail))
        }

        // FTP
        if portNumbers.contains(21) {
            score -= 20
            findings.append(.init(severity: .high,
                                  title: L10n.AuditFinding.ftpTitle,
                                  detail: L10n.AuditFinding.ftpDetail))
        }

        // HTTP sans HTTPS
        let hasHTTP  = portNumbers.contains(80)  || portNumbers.contains(8080)
        let hasHTTPS = portNumbers.contains(443) || portNumbers.contains(8443)
        if hasHTTP && !hasHTTPS {
            score -= 10
            findings.append(.init(severity: .medium,
                                  title: L10n.AuditFinding.httpTitle,
                                  detail: L10n.AuditFinding.httpDetail))
        }

        // Certificat SSL
        if let cert = device.sslCertificate {
            if cert.isExpired {
                score -= 20
                findings.append(.init(severity: .high,
                                      title: L10n.AuditFinding.certExpiredTitle,
                                      detail: L10n.AuditFinding.certExpiredDetail))
            }
            if cert.isSelfSigned {
                score -= 10
                findings.append(.init(severity: .medium,
                                      title: L10n.AuditFinding.certSelfTitle,
                                      detail: L10n.AuditFinding.certSelfDetail))
            }
        }

        // Trop de ports ouverts
        if device.openPorts.count > 5 {
            score -= 10
            findings.append(.init(severity: .low,
                                  title: L10n.AuditFinding.manyPortsTitle(device.openPorts.count),
                                  detail: L10n.AuditFinding.manyPortsDetail))
        }

        // Appareil inconnu
        if device.effectiveType == .unknown {
            score -= 5
            findings.append(.init(severity: .low,
                                  title: L10n.AuditFinding.unknownTitle,
                                  detail: L10n.AuditFinding.unknownDetail))
        }

        // Identifiants par défaut (test actif — LAN uniquement)
        let webPorts = portNumbers.intersection([80, 8080, 443, 8443])
        var credentialsTested = false
        if !webPorts.isEmpty {
            credentialsTested = true
            if let found = await checkDefaultCredentials(ip: device.ip, webPorts: webPorts) {
                score -= 40
                findings.append(.init(severity: .critical,
                                      title: L10n.AuditFinding.defaultCredsTitle,
                                      detail: L10n.AuditFinding.defaultCredsDetail(found.user)))
            }
        }

        // Aucun problème
        if findings.isEmpty {
            findings.append(.init(severity: .info,
                                  title: L10n.AuditFinding.noVulnTitle,
                                  detail: L10n.AuditFinding.noVulnDetail))
        }

        let sorted = findings.sorted { $0.severity > $1.severity }
        return AuditResult(score: max(0, score), findings: sorted, credentialsTested: credentialsTested)
    }

    // MARK: - Vérification des identifiants par défaut

    /// Tente les credentials par défaut sur le(s) port(s) web.
    /// HTTPS prioritaire (suit les redirections 80→443 automatiquement).
    private func checkDefaultCredentials(
        ip: String, webPorts: Set<Int>
    ) async -> (user: String, pass: String)? {

        // Priorité : HTTPS d'abord, HTTP ensuite
        let ordered = webPorts.sorted { [443, 8443].contains($0) && ![443, 8443].contains($1) }
        guard let port = ordered.first else { return nil }
        let scheme = [443, 8443].contains(port) ? "https" : "http"
        guard let baseURL = URL(string: "\(scheme)://\(ip):\(port)/") else { return nil }

        // Étape 1 : vérifier si l'appareil requiert une authentification Basic Auth
        // (évite de tester des creds sur des appareils sans auth, ou avec auth par formulaire)
        guard await deviceRequiresBasicAuth(url: baseURL) else { return nil }

        // Étape 2 : tester les credentials par défaut
        for cred in defaultCredentials {
            if await testCredential(url: baseURL, username: cred.user, password: cred.pass) {
                return cred
            }
        }
        return nil
    }

    /// Retourne `true` si l'appareil répond 401 sans credentials (Basic Auth requis).
    /// Suit les redirections HTTP→HTTPS grâce à URLSession.
    private func deviceRequiresBasicAuth(url: URL) async -> Bool {
        let delegate = LANTrustDelegate()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        do {
            let (_, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 401
        } catch {
            return false
        }
    }

    /// Teste une paire credentials via le mécanisme de challenge URLSession.
    /// Le delegate gère : acceptation des certs auto-signés + Basic Auth challenge.
    private func testCredential(url: URL, username: String, password: String) async -> Bool {
        let delegate = LANAuthDelegate(username: username, password: password)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            // Vérifier que la réponse est bien une page HTML (pas juste un ping API)
            let preview = String(data: data.prefix(512), encoding: .utf8) ?? ""
            let lower = preview.lowercased()
            // Vérifier une structure HTML réelle (balise ouvrante + contenu)
            let hasHTML = lower.contains("<html") || lower.contains("<body") || lower.contains("<title")
            // Exclure les pages de login (l'auth aurait dû aboutir à une vraie page)
            let isLoginPage = lower.contains("login") || lower.contains("password")
                           || lower.contains("incorrect") || lower.contains("invalid")
                           || lower.contains("denied") || lower.contains("unauthorized")
            return hasHTML && !isLoginPage
        } catch {
            return false
        }
    }
}

// MARK: - URLSession delegates (LAN uniquement)

/// Accepte les certificats auto-signés — uniquement pour le LAN local.
private final class LANTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// Accepte les certs auto-signés ET répond aux challenges Basic/Digest Auth.
private final class LANAuthDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    let username: String
    let password: String

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    // Certificats auto-signés
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    // Basic / Digest Auth — un seul essai, annule si échec
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let method = challenge.protectionSpace.authenticationMethod
        let isBasicOrDigest = (method == NSURLAuthenticationMethodHTTPBasic ||
                               method == NSURLAuthenticationMethodHTTPDigest)
        if isBasicOrDigest && challenge.previousFailureCount == 0 {
            completionHandler(.useCredential,
                              URLCredential(user: username, password: password, persistence: .none))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
