# NetGuard — Cahier des Charges

> Version 1.0 — 2026-05-28  
> Statut : **En cours de développement**

---

## 1. Vue d'ensemble

**NetGuard** est une application macOS de scan et de sécurité réseau local. Elle permet de découvrir tous les appareils connectés au réseau, d'identifier les ports ouverts et les vulnérabilités, et d'alerter l'utilisateur sur les risques de sécurité.

| Propriété | Valeur |
|---|---|
| Plateforme | macOS 26+ (Tahoe), Apple Silicon |
| Distribution | Usage personnel — open source éventuel (GitHub) |
| App Store | Non |
| Sandbox | Non (scan réseau nécessite des accès bas niveau) |
| Bundle ID | `com.wilfrid.B.NetGuard` |
| Langues | Français (principal) + Anglais |

---

## 2. Architecture technique

### Stack
- **SwiftUI** — interface complète (pas d'AppKit direct sauf `SFCertificatePanel`)
- **Swift Concurrency** — `actor` pour les services, `@MainActor` pour AppState
- **Network framework** — `NWConnection` (port scan), `NWPathMonitor` (réseau), `NWBrowser` (Bonjour)
- **Security.framework** — Keychain, `SecCertificate`, `SecTrust`
- **SecurityInterface** — `SFCertificatePanel` (macOS natif)
- **SwiftData** — persistance historique des scans (macOS 14+, disponible sur macOS 26)
- **UserNotifications** — alertes push pour scan planifié
- **FoundationModels** — recommandations LLM on-device (macOS 26 + Apple Intelligence)

### Structure des fichiers
```
NetGuard/
├── NetGuardApp.swift
├── ContentView.swift
├── Models/
│   ├── NetworkDevice.swift       ← entité principale
│   ├── NetworkAlert.swift        ← alertes sécurité
│   ├── ScanResult.swift          ← résultat de scan (persistance)
│   └── ScanSnapshot.swift        ← nouveau : snapshot pour historique
├── Services/
│   ├── AppState.swift            ← ViewModel central (@MainActor)
│   ├── NetworkScanner.swift      ← découverte des hosts (ping sweep)
│   ├── PortScanner.swift         ← scan ports via NWConnection
│   ├── DeviceEnricher.swift      ← OS, mDNS, NetBIOS, HTTP, SSL
│   ├── VulnerabilityChecker.swift← génération des alertes
│   ├── NetworkInfoService.swift  ← interfaces réseau (IP, gateway, WiFi)
│   ├── NetworkMonitor.swift      ← NWPathMonitor (changements réseau)
│   ├── PersistenceService.swift  ← nouveau : Keychain + SwiftData
│   └── ScheduledScanService.swift← nouveau : scan planifié + notifications
├── Views/
│   ├── SidebarView.swift         ← colonne gauche (métriques, alertes, scans)
│   ├── NetworkMapView.swift      ← colonne centrale (carte réseau visuelle)
│   ├── DeviceDetailView.swift    ← colonne droite (détail appareil)
│   └── HistoryView.swift         ← nouveau : onglet historique des scans
└── Utils/
    ├── L10n.swift                ← enum type-safe pour localisation
    └── Localizable.xcstrings     ← remplace fr/en .strings
```

### Architecture des services (flux de données)
```
NWPathMonitor (NetworkMonitor)
    → NetworkChangeBanner dans SidebarView

Bouton "Scan complet" (SidebarView)
    → AppState.startFullScan()
        1. NetworkInfoService   → IP locale, gateway, subnet, WiFi
        2. NetworkScanner       → ping sweep → [NetworkDevice]
        3. PortScanner          → NWConnection → openPorts sur chaque device
        4. DeviceEnricher       → ping TTL, NWBrowser/Bonjour, nmblookup,
                                   HTTP banner, SSL certificate
        5. VulnerabilityChecker → génère [NetworkAlert]
        6. PersistenceService   → sauvegarde snapshot + màj appareils connus
        → AppState.devices, AppState.alerts
        → NotificationService   → push si nouveaux appareils / nouvelles alertes
```

---

## 3. Fonctionnalités existantes (à conserver)

### 3.1 Interface principale — HSplitView 3 colonnes

| Colonne | Contenu |
|---|---|
| **Sidebar** (gauche, 340–440 pt) | Logo, status dot, métriques, infos réseau, alertes, boutons scan |
| **NetworkMapView** (centre) | Carte visuelle du réseau (routeur central + appareils en étoile) |
| **DeviceDetailView** (droite, 300–400 pt) | Détail de l'appareil sélectionné |

### 3.2 Types de scans

**Scan complet** (5 étapes) :
1. Récupération des infos réseau (IP, gateway, CIDR, WiFi)
2. Découverte des hosts (ping sweep ICMP via `/sbin/ping`)
3. Scan des ports (NWConnection, liste de ports courants)
4. Enrichissement (ping TTL précis, mDNS, NetBIOS, HTTP banner, HTTP title)
5. Analyse des vulnérabilités → génération des alertes

**Scan rapide** : étapes 1 + 2 uniquement (hosts, pas de ports)

Barre de progression continue dans la sidebar avec message contextuel.

### 3.3 Modèle NetworkDevice

Champs actuels :
- `ip`, `mac`, `hostname` (DNS), `mdnsName` (Bonjour), `netbiosName`
- `vendor` (OUI lookup), `type` (DeviceType), `status` (DeviceStatus)
- `openPorts` ([OpenPort]), `osGuess` (TTL fingerprint), `ttl`
- `httpBanner`, `httpTitle`
- `responseTime` (ms), `firstSeen`, `lastSeen`
- `isCurrentDevice`, `parentIP`

### 3.4 Alertes de sécurité

Niveaux : `critical` / `high` / `medium` / `low` / `info`  
Catégories : `openPort`, `weakEncryption`, `unknownDevice`, `vulnerability`, `configuration`, `intrusion`

Checks implémentés :
- Ports vulnérables (Telnet, VNC, bases de données exposées, SMB, RDP, PPTP...)
- Chiffrement WiFi faible (WEP, WPA v1, réseau ouvert)
- Appareils non identifiés (type == .unknown)
- Configuration réseau (> 20 appareils, > 3 appareils avec ports vulnérables)

### 3.5 Résolution de noms et enrichissement

| Source | Méthode actuelle | Méthode cible |
|---|---|---|
| mDNS/Bonjour | subprocess `dns-sd` (fragile) | **NWBrowser** (Network framework) |
| NetBIOS | subprocess `nmblookup` | inchangé (pas d'alternative Apple) |
| DNS hostname | `CFHost` / `gethostbyaddr` | inchangé |
| OUI vendor | lookup local (fichier ou dictionnaire) | inchangé |
| HTTP banner | URLSession + InsecureDelegate | + inspection SSL (SecTrust) |

### 3.6 Surveillance réseau (NetworkMonitor)

- `NWPathMonitor` détecte les changements de connexion
- Bannière animée dans la sidebar avec message et bouton "Rescanner"
- Types détectés : connexion WiFi → Ethernet, perte réseau, changement réseau

### 3.7 Localisation

- Langues : Français (défaut) + Anglais
- Enum `L10n` type-safe dans `Utils/L10n.swift`
- Source actuelle : `fr.lproj/Localizable.strings` + `en.lproj/Localizable.strings`

---

## 4. Améliorations planifiées

### 🔴 Priorité haute

#### A1 — NWBrowser : remplacer le subprocess `dns-sd`

**Contexte** : `DeviceEnricher.resolveMDNS()` lance `/usr/bin/dns-sd` et le tue après 1.5s. Fragile, bloquant, dépendant d'un outil CLI.

**Cible** : Utiliser `NWBrowser` (Network framework, déjà importé) pour découvrir les services Bonjour de façon native et asynchrone.

**Ce que ça apporte** :
- Découverte des services *avant* ou *pendant* le port scan → identification du type d'appareil plus précise
- Pas de subprocess, pas de timeout arbitraire
- Types de services à scanner : `_http._tcp.`, `_ssh._tcp.`, `_smb._tcp.`, `_afpovertcp._tcp.`, `_raop._tcp.`, `_airplay._tcp.`, `_ipp._tcp.`, `_printer._tcp.`, `_companion-link._tcp.`
- Résultat dans `NetworkDevice.mdnsName` + nouveau champ `bonjourServices: [String]` (services découverts)

**Info.plist** à ajouter :
```xml
<key>NSBonjourServices</key>
<array>
  <string>_http._tcp</string>
  <string>_ssh._tcp</string>
  <!-- etc. -->
</array>
<key>NSLocalNetworkUsageDescription</key>
<string>NetGuard scanne votre réseau local pour détecter les appareils.</string>
```

---

#### A2 — SecCertificate/SecTrust : inspection SSL

**Contexte** : `grabHTTP()` accepte tout certificat SSL via `InsecureDelegate` (aucune validation).

**Cible** : Capturer le certificat SSL pendant le GET HTTPS et l'analyser.

**Workflow technique** (cible macOS 26, on utilise les APIs modernes uniquement) :

```
URLSessionDelegate.urlSession(_:didReceive challenge:completionHandler:)
  ↓
let trust = challenge.protectionSpace.serverTrust       // SecTrust
  ↓
var err: CFError?
let isTrusted = SecTrustEvaluateWithError(trust, &err)  // macOS 10.14+
  ↓
let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]  // macOS 12+
let leaf  = chain?.first
  ↓
// Extraction d'infos
SecCertificateCopySubjectSummary(leaf)        → CFString (sujet/CN)
SecCertificateCopyNotValidBeforeDate(leaf)    → CFDate (macOS 13+)
SecCertificateCopyNotValidAfterDate(leaf)     → CFDate (macOS 13+)
SecCertificateCopyData(leaf) + parser le DER pour l'issuer
```

> ⚠️ **Ne pas utiliser** `SecTrustGetCertificateAtIndex(_:_:)` — déprécié en faveur de `SecTrustCopyCertificateChain(_:)` (macOS 12+).
> Toutes les APIs ci-dessus sont disponibles dès macOS 13, donc OK sur cible macOS 26.

**Informations à extraire** :
- Sujet / CN (`SecCertificateCopySubjectSummary`)
- Issuer (parser DER ou utiliser `SecCertificateCopyKey` + helpers)
- Dates de validité (`SecCertificateCopyNotValidBeforeDate` / `…AfterDate`)
- Auto-signé : sujet == issuer
- Validé ou non (`SecTrustEvaluateWithError` → Bool + CFError)
- Cause d'échec lisible : `CFErrorCopyDescription(err)`

**Nouvelles propriétés sur `NetworkDevice`** :
```swift
var sslCertificate: CertificateInfo?   // nouveau

struct CertificateInfo: Codable {
    var subject: String
    var issuer: String
    var validFrom: Date
    var validTo: Date
    var isSelfSigned: Bool
    var isExpired: Bool          // dérivé : validTo < Date()
    var isTrusted: Bool
    var trustErrorDescription: String?   // si !isTrusted, raison lisible
}
```

**Capture du certificat dans `DeviceEnricher.grabHTTP()`** :
- Remplacer/étendre `InsecureDelegate` par un `CertificateCapturingDelegate` qui :
  1. Garde la connexion fonctionnelle (toujours accepter le challenge pour collecter le cert)
  2. Stocke la `SecTrust` reçue dans un `[host: SecTrust]` interne au délégué
- Après le `dataTask.resume()`, lire le `SecTrust` pour le host, le valider, peupler `CertificateInfo`

**Nouvelles alertes dans `VulnerabilityChecker`** :
- Certificat expiré → `.critical` (« Le certificat de 192.168.1.X a expiré le … »)
- Certificat auto-signé sur un service web → `.medium`
- Certificat invalide (autre raison `trustErrorDescription`) → `.high`

**Important — thread safety** :
- Les fonctions `Sec*` C ne sont pas isolées par un acteur. L'analyse du certificat doit se faire dans l'actor `DeviceEnricher` ou via une fonction `nonisolated` pour éviter les blocages MainActor.

---

#### A3 — SFCertificatePanel : bouton "Voir le certificat"

**Contexte** : Aucune façon de consulter le certificat SSL d'un appareil.

**Cible** : Dans `DeviceDetailView` (section Réseau), ajouter un bouton "Voir le certificat" visible si `sslCertificate != nil`.

**Comportement** : Ouvre la sheet/panel macOS natif `SFCertificatePanel` — aucun code UI custom nécessaire.

```swift
// Appel via NSViewRepresentable ou depuis un NSWindowController
SFCertificatePanel.shared().runModal(for: trust, showGroup: true)
```

---

### 🟡 Priorité moyenne

#### A4 — Diagnostiquer le réseau

**Contexte** : Quand le scan retourne 0 appareil ou échoue, l'utilisateur ne sait pas pourquoi.

**Cible** : Afficher un bouton "Diagnostiquer le réseau" dans la sidebar quand `devices.isEmpty && !scanStatus.isScanning`.

**Comportement** : Ouvre l'assistant réseau macOS via `NSWorkspace` :
```swift
NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.network")!)
```
(URL scheme exacte à confirmer lors de l'implémentation — tester plusieurs options)

---

#### A5 — Persistance complète (Keychain + SwiftData)

**Contexte** : Tout est perdu au redémarrage de l'app. Impossible de détecter un nouvel appareil.

**Cible** : Sauvegarder l'intégralité de chaque `NetworkDevice` entre les sessions.

**Architecture** :
- `SwiftData` (macOS 14+, disponible sur macOS 26) pour le stockage des appareils connus et de l'historique
- `Keychain` pour les données sensibles (clés, tokens futurs)
- `@Model` SwiftData sur `NetworkDevice` (ou modèle miroir `PersistedDevice`)

**Comportement** :
- À la fin de chaque scan : comparer les appareils trouvés avec les appareils connus
- Nouvel appareil détecté → alerte `.intrusion` (catégorie existante) + notification macOS
- Mise à jour des champs `firstSeen` / `lastSeen` cohérente
- Option "Oublier cet appareil" dans `DeviceDetailView`

---

#### A6 — Historique des scans

**Contexte** : Aucun moyen de comparer les scans dans le temps. Nouveau feature demandé.

**Cible** : Conserver un historique des scans précédents, accessible dans un onglet dédié de la sidebar.

**Modèle** :
```swift
@Model
class ScanSnapshot {
    var id: UUID
    var date: Date
    var duration: TimeInterval
    var deviceCount: Int
    var alertCount: Int
    var newDeviceCount: Int          // appareils pas vus avant
    var devices: [PersistedDevice]   // snapshot complet
    var alerts: [NetworkAlert]
    var networkName: String          // SSID ou interface
}
```

**UI — onglet "Historique" dans la sidebar** :
- Sélecteur d'onglet en haut de la sidebar : **Réseau** | **Historique**
- Liste des scans passés (date, durée, nb appareils, nb alertes, nb nouveaux)
- Clic sur un scan → charge le snapshot dans la NetworkMapView et DeviceDetailView (lecture seule)
- Indicateur visuel "nouveau" sur les appareils apparus depuis le scan précédent
- Limite de rétention : configurable (défaut : 30 derniers scans)

---

#### A7 — Scan planifié

**Contexte** : L'utilisateur doit manuellement lancer un scan. Nouveau feature demandé.

**Cible** : Permettre de planifier des scans automatiques en arrière-plan.

**Configuration** (dans un panneau Préférences ou directement dans la sidebar) :
- Fréquence : toutes les 15 min / 30 min / 1 h / 4 h / 24 h / désactivé
- Scan rapide ou scan complet
- Actif seulement quand l'app est en foreground, ou aussi en background ?

**Comportement quand un changement est détecté** :
- **Notification macOS** (`UserNotifications`) :
  - "Nouvel appareil détecté — 192.168.1.X (inconnu)"
  - "Port vulnérable détecté sur 192.168.1.Y (port 23 Telnet)"
- **Alerte in-app** : badge sur l'icône Dock + entrée non lue dans la sidebar

**Contraintes** :
- Pas de background refresh hors App Store → scan planifié actif tant que l'app tourne
- `NSBackgroundActivityScheduler` pour les scans en arrière-plan quand l'app est ouverte

---

#### A8 — Accessibility (VoiceOver)

**Contexte** : Aucun label d'accessibilité sur les éléments interactifs actuels.

**Cible** : Support VoiceOver complet sur macOS.

**À implémenter** :
- `.accessibilityLabel` sur tous les boutons icônes (scan, fermer, voir certificat...)
- `.accessibilityElement(children: .combine)` sur les nœuds de `NetworkMapView`
- `.accessibilityLabel` + `.accessibilityValue` sur les `MetricCard`
- `AccessibilityNotification.Announcement("Scan terminé — X appareils, Y alertes").post()` dans AppState après scan
- Labels sur les lignes de `DeviceDetailView`

---

### 🟢 Qualité / maintenance

#### A9 — Migration String Catalogs (.xcstrings)

**Contexte** : Localisation actuelle via `fr.lproj/Localizable.strings` + `en.lproj/Localizable.strings`.

**Cible** : Migrer vers `Localizable.xcstrings` (standard Xcode 15+).

**Méthode** : Edit → Convert to String Catalog dans Xcode (quasi automatique).  
Avantage : Xcode affiche les clés manquantes/non traduites directement dans l'éditeur.

---

#### A10 — Swift Testing

**Contexte** : Aucun test unitaire dans le projet.

**Cible** : Ajouter des tests avec le framework `Testing` (Swift 6, macOS 15+).

**Fichiers cibles** :
```swift
// Tests/VulnerabilityCheckerTests.swift
@Test("Telnet détecté comme critique")
func testTelnetIsCritical() async { ... }

@Test("WEP génère une alerte critique")
func testWEPAlertIsCritical() async { ... }

// Tests/NetworkScannerTests.swift
@Test("Parsing subnet CIDR")
func testSubnetParsing() { ... }
```

---

#### A11 — FoundationModels : recommandations LLM on-device

**Contexte** : Les recommandations de `VulnerabilityChecker` sont statiques (textes hardcodés).

**Cible** : Remplacer les textes statiques par des explications contextuelles générées par le LLM on-device d'Apple Intelligence.

**Conditions** : macOS 26 + Apple Intelligence activé sur l'appareil.

**Comportement** :
- Si `FoundationModels` disponible → explication détaillée et contextualisée (device + port + OS)
- Sinon → fallback sur le texte statique actuel

**Exemple** :
```
Port 3306 (MySQL) ouvert sur 192.168.1.45 (Linux, vendor: QNAP)
→ LLM : "Ce NAS QNAP expose MySQL directement sur le réseau local.
          Un accès non authentifié permettrait de lire ou modifier
          toutes les données. Configurez bind-address=127.0.0.1
          dans /etc/mysql/mysql.conf.d/mysqld.cnf."
```

**Guard** :
```swift
guard FoundationModels.isAvailable else {
    return staticRecommendation(for: alert)
}
```

---

## 5. Modèle de données — évolutions

### NetworkDevice (ajouts)
```swift
var bonjourServices: [String]        // ex: ["_ssh._tcp.", "_http._tcp."]
var sslCertificate: CertificateInfo? // inspection SSL (A2)
```

### Nouveau : CertificateInfo
```swift
struct CertificateInfo: Codable {
    var subject: String
    var issuer: String
    var validFrom: Date
    var validTo: Date
    var isSelfSigned: Bool
    var isExpired: Bool                  // dérivé : validTo < Date()
    var isTrusted: Bool
    var trustErrorDescription: String?   // raison lisible si !isTrusted
}
```

**APIs utilisées** (toutes disponibles macOS 13+, on cible 26) :
- `SecTrustEvaluateWithError(_:_:)` — validation (Bool + CFError)
- `SecTrustCopyCertificateChain(_:)` — chaîne complète (remplace l'ancien `SecTrustGetCertificateAtIndex`)
- `SecCertificateCopySubjectSummary(_:)` — CN/sujet
- `SecCertificateCopyNotValidBeforeDate(_:)` / `…AfterDate(_:)` — dates de validité directes (pas de parsing DER)

### Nouveau : ScanSnapshot (SwiftData)
```swift
@Model class ScanSnapshot {
    var id: UUID
    var date: Date
    var duration: TimeInterval
    var networkName: String
    var deviceCount: Int
    var alertCount: Int
    var newDeviceCount: Int
    var devicesData: Data   // JSON encodé de [NetworkDevice]
    var alertsData: Data    // JSON encodé de [NetworkAlert]
}
```

### AppState (ajouts)
```swift
@Published var scheduledScanEnabled: Bool = false
@Published var scheduledScanInterval: TimeInterval = 3600
@Published var scanHistory: [ScanSnapshot] = []
@Published var selectedSnapshot: ScanSnapshot? = nil  // nil = scan actuel
```

---

## 5b. Identification des appareils

### A12 — Fingerprinting avancé (identification automatique)

**Contexte** : L'identification actuelle est basique — TTL → OS family, OUI → vendor. Beaucoup d'appareils restent `unknown`.

**Cible** : Croiser toutes les sources disponibles pour identifier précisément le type et le modèle d'appareil.

**Sources à croiser** (par ordre de fiabilité) :

| Source | Exemple | Type déduit |
|---|---|---|
| Service Bonjour `_airplay._tcp.` + `_raop._tcp.` | — | Apple TV / HomePod |
| Service Bonjour `_companion-link._tcp.` | — | iPhone / iPad |
| Service Bonjour `_ipp._tcp.` ou `_printer._tcp.` | — | Imprimante |
| Service Bonjour `_homekit._tcp.` | — | Accessoire domotique |
| Service Bonjour `_googlecast._tcp.` | — | Chromecast / Google device |
| Service Bonjour `_smb._tcp.` + vendor NAS | — | NAS |
| HTTP Server banner | "Synology DiskStation" | NAS Synology |
| HTTP Server banner | "FRITZ!Box" | Routeur AVM |
| HTTP Server banner | "Cisco" / "Meraki" | Routeur/switch Cisco |
| HTTP title | "DiskStation Manager" | NAS Synology |
| OUI vendor | "Apple Inc." | Appareil Apple |
| OUI vendor | "Synology" | NAS Synology |
| TTL 64 + vendor Apple | — | macOS ou iOS |
| Port 22 ouvert + vendor Apple | — | Mac (SSH activé) |
| Port 9100 (RAW printing) | — | Imprimante |

**Architecture** : Nouvelle méthode `DeviceEnricher.inferType(device:)` appelée après enrichissement complet. Remplace / complète la logique actuelle de `guessOS()`.

```swift
// Règles de priorité (ordre décroissant)
// 1. Services Bonjour → type fort
// 2. HTTP banner/title → vendor précis
// 3. OUI + ports → combinaison
// 4. TTL seul → fallback OS
```

**Résultat attendu** : réduire significativement les appareils de type `.unknown` sur un réseau domestique typique.

---

### A13 — Notes utilisateur

**Contexte** : Aucun moyen d'annoter un appareil inconnu ("Mon NAS", "Box de la salle", "Tablette de ma fille").

**Cible** : Champ texte libre sur chaque appareil, persisté entre les sessions.

**Nouveau champ sur `NetworkDevice`** :
```swift
var userNote: String   // "" par défaut, éditable dans DeviceDetailView
```

**UI dans `DeviceDetailView`** :
- Section "Note" (ou intégrée dans la section Identité)
- Si note vide : placeholder "Ajouter une note…" cliquable
- Si note non vide : texte affiché + bouton modifier (icône crayon)
- Édition inline dans la vue (pas de sheet séparée)
- Sauvegarde automatique via SwiftData (dépend de A5)

---

## 6. Hors périmètre

| Feature | Raison |
|---|---|
| EndpointSecurity | Entitlement Apple restreint (usage interne Apple/EDR) |
| HealthKit | Sans rapport |
| Visual Intelligence | Sans rapport |
| MLX / Metal | Sans rapport |
| Scan réseau distant (WAN) | Hors réseau local — hors scope sécurité |
| Blocage d'appareils | Nécessite accès routeur (API propriétaire) |
| App Store distribution | Usage personnel + open source |

---

## 7. Ordre d'implémentation recommandé

| # | Feature | Dépendances | Complexité |
|---|---|---|---|
| 1 | A9 — String Catalogs | — | Faible (migration Xcode auto) |
| 2 | A8 — Accessibility | — | Faible |
| 3 | A1 — NWBrowser | — | Moyenne |
| 4 | A12 — Fingerprinting avancé | A1 (services Bonjour disponibles) | Moyenne |
| 5 | A2 — SecCertificate/SecTrust | A1 (grabHTTP amélioré) | Moyenne |
| 6 | A3 — SFCertificatePanel | A2 (SecTrust disponible) | Faible |
| 7 | A5 — Persistance SwiftData | — | Moyenne |
| 8 | A13 — Notes utilisateur | A5 (persistance SwiftData) | Faible |
| 9 | A6 — Historique scans | A5 (persistance) | Moyenne |
| 10 | A7 — Scan planifié | A5 (persistance), UserNotifications | Moyenne |
| 11 | A4 — Diagnostique réseau | — | Faible |
| 12 | A10 — Swift Testing | Features stables | Moyenne |
| 13 | A11 — FoundationModels | Features stables | Moyenne |

---

## 8. Contraintes techniques

- **Pas de sandbox** : accès `/sbin/ping`, `/usr/bin/nmblookup`, ports réseau libres
- **No App Store** : pas de restrictions d'entitlements
- **Apple Silicon uniquement** : pas de support Intel (Universal Binary inutile)
- **macOS 26+** : toutes les APIs modernes disponibles (SwiftData, FoundationModels, Swift 6.x)
- **Swift 6 strict concurrency** : `actor` pour les services, `@MainActor` pour UI, `Sendable` partout
- **Open source** : code propre, pas de secrets hardcodés, README en FR + EN

---

*Fin du cahier des charges — v1.0*
