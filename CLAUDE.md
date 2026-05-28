# NetGuard — Contexte projet

App macOS SwiftUI de scan et sécurité réseau local. Usage personnel, open source éventuel.  
Dépôt : `git@github.com:Lyosis/NetGuard.git`  
**CDC complet** : `CDC.md` à la racine du projet.

## Stack technique

- **macOS 26+**, Apple Silicon, SwiftUI, **no sandbox**
- **Swift 6** strict concurrency
- Architecture : `HSplitView` 3 colonnes (Sidebar | NetworkMapView | DeviceDetailView)
- Services : `actor` NetworkScanner, PortScanner, DeviceEnricher, VulnerabilityChecker, AppState (@MainActor)
- Réseau : `NWConnection` (port scan), `NWPathMonitor` (changements réseau), `NWBrowser` (Bonjour — à implémenter), URLSession (HTTP banners)
- Enrichissement : ping TTL, `dns-sd` subprocess (mDNS — à remplacer par NWBrowser), `nmblookup` (NetBIOS), OUI vendor lookup
- Persistance : SwiftData (à implémenter), Keychain (à implémenter)
- Localisation : `fr.lproj` + `en.lproj` Localizable.strings → migration `.xcstrings` prévue + `Utils/L10n.swift` (enum type-safe)

## Améliorations à implémenter (ordre recommandé)

> Voir `CDC.md` pour le détail complet de chaque point.

### 🟢 Qualité / maintenance (faire en premier)

**A9. String Catalogs (.xcstrings)**
- Migrer `fr.lproj/Localizable.strings` + `en.lproj/Localizable.strings` → `.xcstrings`
- Xcode : Edit → Convert to String Catalog

**A8. Accessibility — labels VoiceOver**
- `.accessibilityLabel` + `.accessibilityElement(children: .combine)` sur NetworkMapView et DeviceDetailView
- `AccessibilityNotification.Announcement("Scan terminé — X appareils, Y alertes").post()` dans AppState
- Doc Cupertino : `apple-docs://updates/accessibility`

### 🔴 Priorité haute

**A1. NWBrowser — remplacer le subprocess `dns-sd`**
- `DeviceEnricher.resolveMDNS()` → `NWBrowser` (Network framework, déjà importé)
- ⚠️ Ne pas utiliser `CFNetServiceBrowser` (ancienne API) — utiliser `NWBrowser`
- Services à scanner : `_http._tcp.`, `_ssh._tcp.`, `_smb._tcp.`, `_afpovertcp._tcp.`, `_raop._tcp.`, `_airplay._tcp.`, etc.
- Nouveau champ `bonjourServices: [String]` sur `NetworkDevice`
- Info.plist : `NSBonjourServices` + `NSLocalNetworkUsageDescription`
- Doc Cupertino : `apple-docs://network/nwbrowser`

**A2. SecCertificate / SecTrust — inspection SSL**
- `DeviceEnricher.grabHTTP()` → capturer + analyser le certificat SSL pendant le GET HTTPS
- Nouveau champ `sslCertificate: CertificateInfo?` sur `NetworkDevice`
- Nouvelles alertes : cert expiré (critical), cert auto-signé (medium)
- API : `SecTrustCreateWithCertificates` → `SecTrustEvaluateWithError` → `SecTrustGetCertificateAtIndex`
- Doc Cupertino : `apple-docs://security/sectrustevaluatewitherror(_:_:)`

**A3. SFCertificatePanel — bouton "Voir le certificat"**
- Dans `DeviceDetailView` (section Réseau), bouton visible si `sslCertificate != nil`
- `SFCertificatePanel.shared().runModal(for: trust, showGroup: true)`
- Doc Cupertino : `apple-docs://securityinterface/sfcertificatepanel`

### 🟡 Priorité moyenne

**A4. Diagnostiquer le réseau**
- ⚠️ `CFNetDiagnosticDiagnoseProblemInteractively()` est **déprécié depuis macOS 10.13** — ne pas utiliser
- Alternative : bouton "Diagnostiquer le réseau" quand `devices.isEmpty` → `NSWorkspace.shared.open(...)` vers les Préférences Réseau ou l'assistant réseau
- URL scheme exacte à confirmer lors de l'implémentation

**A5. Persistance complète — SwiftData + Keychain**
- Sauvegarder l'intégralité de chaque `NetworkDevice` entre les sessions
- SwiftData pour appareils connus + historique
- Détecter "nouvel appareil" → alerte `.intrusion` + notification macOS
- Option "Oublier cet appareil" dans DeviceDetailView

**A6. Historique des scans** *(nouveau)*
- Onglet "Historique" dans la sidebar (sélecteur Réseau | Historique)
- `ScanSnapshot` : date, durée, nb appareils, nb alertes, nb nouveaux
- Clic sur un snapshot → charge en lecture seule dans NetworkMapView + DeviceDetailView
- Limite : 30 derniers scans (configurable)
- Dépend de A5 (persistance SwiftData)

**A7. Scan planifié** *(nouveau)*
- Configuration : fréquence (15 min / 30 min / 1 h / 4 h / 24 h / désactivé)
- Type : scan rapide ou scan complet
- Détection changement → **notification macOS** (UserNotifications) + **alerte in-app**
- `NSBackgroundActivityScheduler` pour background
- Dépend de A5 (persistance) pour comparer avec les appareils connus

### 🟢 Qualité (faire après les features stables)

**A12. Fingerprinting avancé — identification automatique**
- Croiser services Bonjour (NWBrowser) + OUI + TTL + HTTP banner pour identifier précisément le type
- Règles : `_airplay._tcp.` → Apple TV/HomePod, `_companion-link._tcp.` → iPhone/iPad, `_ipp._tcp.` → imprimante, `_homekit._tcp.` → domotique, `_googlecast._tcp.` → Chromecast, banner "Synology" → NAS, etc.
- Nouvelle méthode `DeviceEnricher.inferType(device:)` après enrichissement complet
- Objectif : réduire fortement les appareils de type `.unknown`
- Dépend de A1 (NWBrowser — services Bonjour disponibles)

**A13. Notes utilisateur**
- Champ texte libre sur chaque appareil ("Mon NAS", "Tablette de ma fille"...)
- Affiché et éditable dans `DeviceDetailView` (inline, pas de sheet)
- Persisté via SwiftData (dépend de A5)
- Nouveau champ `var userNote: String` sur `NetworkDevice`

**A10. Swift Testing**
- Tests unitaires avec `@Test` / `#expect` pour `VulnerabilityChecker` et `NetworkScanner`
- Doc : `apple-docs://testing/addingcomments`

**A11. FoundationModels — recommandations LLM on-device** *(macOS 26 + Apple Intelligence)*
- Remplacer les recommandations statiques de `VulnerabilityChecker` par du LLM on-device
- Guard : `FoundationModels.isAvailable` → fallback statique sinon
- Doc : `~/.claude/docs/foundation-models.md`

## ❌ Non pertinent pour NetGuard

- EndpointSecurity : entitlement Apple restreint + System Extension, trop lourd
- HealthKit, Visual Intelligence, MLX/Metal : sans rapport avec un scanner réseau
