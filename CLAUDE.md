# NetGuard — Contexte projet

App macOS SwiftUI de scan et sécurité réseau local. **Open source (MIT), dépôt public** — contributions externes possibles.  
Dépôt : `git@github.com:Lyosis/NetGuard.git`  
**CDC complet** : `CDC.md` à la racine du projet.

## Stack technique

- **macOS 15.0+** (deployment target), **macOS 26+ Liquid Glass + FoundationModels** via `#available`, Universal Binary (arm64 + x86_64), SwiftUI, **no sandbox**
- ⚠️ **Concurrence : mode langage Swift 5** (`SWIFT_VERSION = 5.0`) et `SWIFT_STRICT_CONCURRENCY` **non défini** → vérification `minimal`. Le code *suit* les conventions Swift 6 (actors, `MainActor.run`) mais **rien n'est vérifié par le compilateur** : ne pas conclure d'un build vert que l'isolation est correcte. Passage à `complete` suivi dans l'issue #31 (~32 diagnostics réels).
- Architecture : `HSplitView` 3 colonnes (Sidebar | NetworkMapView | DeviceDetailView)
- Services : `actor` NetworkScanner, PortScanner, DeviceEnricher, VulnerabilityChecker, SecurityAuditor, SSDPDiscovery ; AppState (`@MainActor`)
- Réseau : `NWConnection` (port scan), `NWPathMonitor` (changements réseau), `NWBrowser` (Bonjour ✅), `NWMulticastGroup` (SSDP/UPnP), URLSession (HTTP banners)
- Enrichissement : ping TTL, `NWBrowser` (mDNS/Bonjour), `nmblookup` (NetBIOS), OUI vendor lookup (`manuf.txt`), SSDP/UPnP
- Persistance : **SwiftData** (`PersistedDevice`, `ScanSnapshot`) ✅ — Keychain non implémenté (aucun secret à stocker à ce jour)
- Localisation : **`Localizable.xcstrings` + `InfoPlist.xcstrings` (FR + EN complets)** ✅ + `Utils/L10n.swift` (enum type-safe). ⚠️ `L10n.t()` passe la clé via une variable → les clés doivent être en `extractionState: "manual"` dans le catalogue, sinon Xcode émet 100+ warnings « References to this key could not be found ». Ne **pas** mettre les clés format auto-extraites (`%@`, `%lld`) en `manual` : erreur « Unable to derive a symbol name ».
- Sécurité réseau : garde `IPv4.isValid` avant tout `Process` (ping/nmblookup), `isLANURL` + `NoRedirectDelegate` sur le fetch UPnP (une redirection contournerait la restriction LAN), sessions `URLSessionConfiguration.ephemeral`

## Améliorations — état réel

> ⚠️ **Les specs détaillées ci-dessous datent d'avant l'implémentation.** Statut vérifié dans le code au 14/06/2026 — se fier à ce tableau, pas aux « à implémenter » des sections suivantes.

| Item | Statut |
|---|---|
| A1 NWBrowser (Bonjour) | ✅ livré — `dns-sd` supprimé |
| A2 SecCertificate / SecTrust | ✅ livré (`CertificateInspector`) |
| A3 SFCertificatePanel | ✅ livré |
| A4 Diagnostiquer le réseau | ✅ livré |
| A5 Persistance SwiftData | ✅ livré — Keychain non nécessaire (aucun secret) |
| A6 Historique des scans | ✅ livré (`ScanSnapshot`, limite 30) |
| A7 Notifications intrusion | ✅ livré — ⏳ **scan planifié** (`NSBackgroundActivityScheduler`) reste à faire |
| A8 Accessibilité VoiceOver | ✅ livré (labels + `AccessibilityNotification`) |
| A9 String Catalogs | ✅ livré (FR + EN complets) |
| A12 Fingerprinting avancé | ✅ livré (UPnP > Bonjour > HTTP > vendor > heuristics) |
| A13 Notes utilisateur | ✅ livré (`userNote`) |
| **A10 Swift Testing** | ❌ **aucune cible de test** — le principal manque du projet |
| **A11 FoundationModels** | ❌ non commencé |
| **#31 Strict concurrency** | ❌ `complete` non activé (~32 diagnostics à traiter) |

### Specs détaillées (historiques — voir `CDC.md`)

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
- API (macOS 13+, modernes) : `SecTrustEvaluateWithError` + `SecTrustCopyCertificateChain` + `SecCertificateCopyNotValidBeforeDate` / `…AfterDate` + `SecCertificateCopySubjectSummary`
- ⚠️ Ne pas utiliser `SecTrustGetCertificateAtIndex` (déprécié, remplacé par `SecTrustCopyCertificateChain`)
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
