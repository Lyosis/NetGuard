import Foundation
import SwiftUI
import SwiftData
import Combine
import Accessibility

// MARK: - AppState (ViewModel central)
@MainActor
class AppState: ObservableObject {

    // MARK: - Published state
    @Published var devices: [NetworkDevice]       = []
    @Published var alerts: [NetworkAlert]         = []
    @Published var networkInfos: [NetworkInfo]    = []
    @Published var primaryNetwork: NetworkInfo    = .empty
    @Published var scanStatus: ScanStatus         = .idle
    @Published var selectedDevice: NetworkDevice? = nil
    @Published var lastScanDate: Date?            = nil
    /// Action en cours sur un appareil (clé = device.id). Permet de griser le
    /// bouton concerné et d'afficher un spinner dans le panneau détail.
    @Published var runningDeviceAction: [UUID: DeviceAction] = [:]
    /// Filtre actif sur la carte (cliquable depuis les MetricCards de la sidebar).
    @Published var deviceFilter: DeviceFilter = .all
    @Published var snapshots: [ScanSnapshot]  = []
    @Published var auditResults: [UUID: SecurityAuditor.AuditResult] = [:]
    /// Dernier scan sans aucune MAC lisible (cf. `NetworkScanner.lastARPResolvedCount`).
    /// Tant qu'il est vrai, aucun appareil sans MAC n'est écrit en base, et les
    /// annotations de ces appareils sont désactivées : elles ne pourraient pas être enregistrées.
    @Published private(set) var isARPDegraded = false

    /// Sous-ensemble de `devices` à afficher selon le filtre courant.
    var filteredDevices: [NetworkDevice] {
        switch deviceFilter {
        case .all:     return devices
        case .known:   return devices.filter { $0.effectiveType != .unknown }
        case .unknown: return devices.filter { $0.effectiveType == .unknown }
        }
    }

    func toggleFilter(_ target: DeviceFilter) {
        deviceFilter = (deviceFilter == target) ? .all : target
    }

    // MARK: - Services
    private let networkInfoService   = NetworkInfoService.shared
    private let networkScanner       = NetworkScanner()
    private let portScanner          = PortScanner()
    private let vulnChecker          = VulnerabilityChecker()
    private let enricher             = DeviceEnricher.shared
    let networkMonitor               = NetworkMonitor()

    // MARK: - Persistance
    private let modelContext: ModelContext
    private let notificationService = NotificationService()

    // MARK: - Computed
    var totalAlerts: Int     { alerts.filter { !$0.isRead }.count }
    var openPortCount: Int   { devices.flatMap(\.openPorts).count }
    var unknownCount: Int    { devices.filter { $0.effectiveType == .unknown }.count }
    var alertDevices: Int    { devices.filter { $0.status == .alert }.count }

    var wifiEncryption: String {
        networkInfos.first(where: { $0.interfaceType == "WiFi" })?
            .wifiInfo?.security ?? "—"
    }

    var lastScanLabel: String {
        guard let d = lastScanDate else { return L10n.App.lastScanNever }
        let interval = Date().timeIntervalSince(d)
        if interval < 60   { return L10n.App.lastScanSeconds(Int(interval)) }
        if interval < 3600 { return L10n.App.lastScanMinutes(Int(interval / 60)) }
        return L10n.App.lastScanHours(Int(interval / 3600))
    }

    // MARK: - Init
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        networkMonitor.start()
        migrateFromStopGapIfNeeded()
        loadPersistedDevices()
        loadSnapshots()
        Task { await notificationService.requestAuthorization() }
        Task {
            await refreshNetworkInfo()
            // Identifie le réseau et déclenche la migration d'identité sans attendre
            // un premier scan — sinon les appareils déjà connus resteraient orphelins.
            await refreshNetworkID()
        }
        Task.detached(priority: .utility) {
            await OUIDatabase.shared.preload()
        }
    }

    deinit {
        networkMonitor.stop()
    }

    // MARK: - Identité du réseau courant

    private static let networkIDKey       = "netguard.current_network_id"
    private static let identityMigratedKey = "netguard.identity_migrated.v2"

    /// Réseau sur lequel on se trouve. Mémorisé entre deux lancements : au démarrage
    /// on doit pouvoir afficher le cache avant que le premier scan ait identifié la
    /// passerelle.
    private(set) var currentNetworkID: String =
        UserDefaults.standard.string(forKey: AppState.networkIDKey) ?? ""

    /// Recalcule l'identité du réseau, la mémorise, et déclenche la migration
    /// d'identité si elle n'a pas encore pu tourner (elle a besoin du réseau).
    ///
    /// Quand la passerelle figure dans `devices` — le cas après chaque scan — la MAC
    /// est déjà connue et rien n'est lu sur le disque. Sinon le repli interroge `arp`,
    /// donc un `Process` synchrone : il est écarté du `MainActor` pour ne pas figer
    /// l'interface.
    private func refreshNetworkID(from devices: [NetworkDevice] = []) async {
        let gateway = primaryNetwork.gateway
        let cidr    = primaryNetwork.subnetCIDR

        let id: String
        if let mac = devices.first(where: { $0.ip == gateway })?.normalizedMAC, !mac.isEmpty {
            id = "gw:\(mac)"
        } else {
            id = await Task.detached(priority: .utility) {
                NetworkIdentity.identifier(gatewayIP: gateway, subnetCIDR: cidr)
            }.value
        }

        guard !id.isEmpty, id != "net:" else { return }
        // MAC de la passerelle illisible (table ARP vide) : ce n'est pas un changement de
        // réseau. Garder le dernier réseau identifié par sa passerelle plutôt que d'en
        // inventer un — sinon les appareils connus disparaissent de l'affichage. Le scan
        // lui-même est alors dégradé : il n'écrit rien et ne lève aucune intrusion.
        if id.hasPrefix("net:"), currentNetworkID.hasPrefix("gw:") { return }
        currentNetworkID = id
        UserDefaults.standard.set(id, forKey: Self.networkIDKey)
        // La migration rattache chaque fiche à un réseau, une fois pour toutes : elle
        // attend une identité fiable, celle de la passerelle.
        if id.hasPrefix("gw:") { migrateDeviceIdentityIfNeeded() }
    }

    // MARK: - Persistance SwiftData

    /// Migration unique vers les clés portées par réseau.
    ///
    /// La formule de `persistenceKey` a changé : sans cette passe, tous les appareils
    /// déjà connus obtiendraient une clé différente et seraient signalés comme autant
    /// d'intrusions au premier lancement suivant la mise à jour.
    ///
    /// Ne peut tourner qu'une fois le réseau identifié — d'où l'appel depuis
    /// `refreshNetworkID()` plutôt que depuis `init`.
    private func migrateDeviceIdentityIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.identityMigratedKey) else { return }
        guard !currentNetworkID.isEmpty else { return }   // réessai au prochain scan

        let all = (try? modelContext.fetch(FetchDescriptor<PersistedDevice>())) ?? []
        guard !all.isEmpty else {
            UserDefaults.standard.set(true, forKey: Self.identityMigratedKey)
            return
        }

        // Les entrées antérieures n'ont pas de réseau : faute d'information contraire,
        // elles proviennent de celui sur lequel on se trouve.
        var claimed: Set<String> = []
        var merged = 0
        for device in all.sorted(by: { $0.lastSeen > $1.lastSeen }) {
            let newKey = "\(currentNetworkID)|\(device.toNetworkDevice().deviceIdentity)"
            // Deux entrées peuvent converger vers la même clé — typiquement deux MAC
            // randomisées d'un même appareil, désormais rapprochées par leur nom mDNS.
            // `persistenceKey` étant unique, garder la plus récente et supprimer l'autre
            // plutôt que de faire échouer l'enregistrement.
            if claimed.contains(newKey) {
                modelContext.delete(device)
                merged += 1
                continue
            }
            claimed.insert(newKey)
            device.persistenceKey = newKey
            device.networkID      = currentNetworkID
        }

        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: Self.identityMigratedKey)
        print("[NetGuard] Migration identité : \(all.count) appareils rattachés à \(currentNetworkID)"
              + (merged > 0 ? ", \(merged) fusionnés" : ""))
    }

    /// Migration unique depuis les stop-gaps (ScanCache JSON + UserAnnotations UserDefaults).
    /// Ne s'exécute que si SwiftData est vide — idempotente.
    private func migrateFromStopGapIfNeeded() {
        let count = (try? modelContext.fetchCount(FetchDescriptor<PersistedDevice>())) ?? 0
        guard count == 0 else { return }

        guard let snap = ScanCache.shared.load() else { return }

        // Lire les annotations depuis UserDefaults (ancienne clé UserAnnotationsStore)
        struct LegacyAnnotation: Codable { var alias: String; var note: String; var overrideType: DeviceType? }
        let annotationsKey = "netguard.user_annotations.v1"
        let legacyAnnotations: [String: LegacyAnnotation]
        if let data = UserDefaults.standard.data(forKey: annotationsKey),
           let decoded = try? JSONDecoder().decode([String: LegacyAnnotation].self, from: data) {
            legacyAnnotations = decoded
        } else {
            legacyAnnotations = [:]
        }

        for device in snap.devices {
            let macKey = device.mac
                .lowercased()
                .replacingOccurrences(of: ":", with: "")
                .replacingOccurrences(of: "-", with: "")
            if let annotation = legacyAnnotations[macKey] {
                device.userAlias        = annotation.alias
                device.userNote         = annotation.note
                device.userOverrideType = annotation.overrideType
            }
            // Réseau pas encore identifié à ce stade : `migrateDeviceIdentityIfNeeded()`
            // rattachera ces entrées dès le premier scan.
            modelContext.insert(PersistedDevice.make(from: device, networkID: currentNetworkID))
        }

        try? modelContext.save()
        ScanCache.shared.clear()
        UserDefaults.standard.removeObject(forKey: annotationsKey)
        print("[NetGuard] Migration stop-gap → SwiftData : \(snap.devices.count) appareils migrés.")
    }

    /// Charge les appareils persistés au démarrage — affichage immédiat carte pré-remplie (grisée).
    private func loadPersistedDevices() {
        let descriptor = FetchDescriptor<PersistedDevice>(
            sortBy: [SortDescriptor(\.lastSeen, order: .reverse)]
        )
        guard let persisted = try? modelContext.fetch(descriptor), !persisted.isEmpty else { return }
        // N'afficher que le réseau courant. Les entrées sans réseau sont celles qui
        // n'ont pas encore été migrées : les garder visibles évite un écran vide au
        // premier lancement suivant la mise à jour.
        let scoped = persisted.filter { $0.networkID.isEmpty || $0.networkID == currentNetworkID }
        guard !scoped.isEmpty else { return }
        self.devices      = scoped.map { $0.toNetworkDevice() }
        self.lastScanDate = scoped.first?.lastSeen
    }

    /// Upsert des appareils dans SwiftData après un scan. Fetch unique → pas de N+1.
    ///
    /// Point de passage unique de toutes les écritures (scans et actions sur un appareil) :
    /// c'est ici, et non dans chaque appelant, qu'un appareil sans MAC est refusé quand la
    /// lecture ARP est dégradée — sinon il serait enregistré sous une clé `ip:`.
    private func upsertToStore(_ scanned: [NetworkDevice]) {
        let writable = isARPDegraded ? scanned.filter { !$0.mac.isEmpty } : scanned
        guard !writable.isEmpty else { return }
        let allPersisted = (try? modelContext.fetch(FetchDescriptor<PersistedDevice>())) ?? []
        let byKey = Dictionary(uniqueKeysWithValues: allPersisted.map { ($0.persistenceKey, $0) })

        for device in writable {
            let key = device.persistenceKey(networkID: currentNetworkID)
            if let existing = byKey[key] {
                existing.update(from: device)
                existing.networkID = currentNetworkID
            } else {
                modelContext.insert(PersistedDevice.make(from: device, networkID: currentNetworkID))
            }
        }
        try? modelContext.save()
    }

    /// Reprend de SwiftData ce que le scan n'a pas mesuré : annotations utilisateur et
    /// enrichissement (type, OS, noms, bannières, services, ports).
    ///
    /// Un scan rapide ne fait ni Bonjour, ni HTTP, ni empreinte d'OS : ses appareils
    /// arrivent avec ces champs vides. Sans cette reprise, `upsertToStore` les recopiait
    /// tels quels et effaçait l'enrichissement du dernier scan complet — en base comme
    /// à l'écran. Règle : une donnée ne peut être remplacée que par une donnée.
    ///
    /// Les mesures fraîches (IP, latence, TTL, `lastSeen`) ne sont jamais reprises.
    /// Fetch unique — O(n) total.
    private func applyPersistedKnowledge(to list: [NetworkDevice]) {
        let allPersisted = (try? modelContext.fetch(FetchDescriptor<PersistedDevice>())) ?? []
        let byKey = Dictionary(uniqueKeysWithValues: allPersisted.map { ($0.persistenceKey, $0) })
        for device in list {
            guard let persisted = byKey[device.persistenceKey(networkID: currentNetworkID)] else { continue }
            let known = persisted.toNetworkDevice()

            device.userAlias        = known.userAlias
            device.userNote         = known.userNote
            device.userOverrideType = known.userOverrideType

            // Type et OS établis par l'enrichissement priment sur la devinette faite à la
            // découverte à partir du seul constructeur. Seul un scan complet les révise.
            if known.type    != .unknown { device.type    = known.type }
            if known.osGuess != .unknown { device.osGuess = known.osGuess }

            if device.vendor.isEmpty          { device.vendor          = known.vendor }
            if device.hostname.isEmpty        { device.hostname        = known.hostname }
            if device.mdnsName.isEmpty        { device.mdnsName        = known.mdnsName }
            if device.netbiosName.isEmpty     { device.netbiosName     = known.netbiosName }
            if device.httpBanner.isEmpty      { device.httpBanner      = known.httpBanner }
            if device.httpTitle.isEmpty       { device.httpTitle       = known.httpTitle }
            if device.bonjourServices.isEmpty { device.bonjourServices = known.bonjourServices }
            // Un scan complet remesure les ports et remplace cette liste, vide comprise.
            if device.openPorts.isEmpty       { device.openPorts       = known.openPorts }
            if device.upnp == nil             { device.upnp            = known.upnp }
            if device.sslCertificate == nil   { device.sslCertificate  = known.sslCertificate }
        }
    }

    /// Détection des nouveaux appareils puis persistance — sauf si la lecture ARP a échoué.
    ///
    /// Sans MAC, chaque appareil prend une clé `ip:` : il serait signalé comme une
    /// intrusion et enregistré en double. Le scan est alors signalé comme dégradé et
    /// rien n'est écrit — plutôt qu'un échec silencieux. Cas réel : sous macOS 27, un
    /// build signé Apple Development (Debug lancé depuis Xcode) lit une table ARP vide,
    /// sans erreur. Les builds Developer ID distribués ne sont pas touchés.
    /// Retourne le nombre de nouveaux appareils.
    private func detectAndPersist(_ discovered: [NetworkDevice], arpResolvedCount: Int) -> Int {
        // Une seule alerte de ce type à la fois : le scan rapide ne vide pas la liste.
        alerts.removeAll { $0.category == .scanHealth }
        if let alert = Self.arpReadFailure(in: discovered, arpResolvedCount: arpResolvedCount) {
            isARPDegraded = true
            alerts.append(alert)
            return 0
        }
        isARPDegraded = false
        let newCount = detectAndAlertNewDevices(discovered)
        upsertToStore(discovered)
        return newCount
    }

    /// Des hôtes répondent, mais la table ARP n'a renvoyé aucune entrée pour le sous-réseau.
    /// La machine locale est exclue du décompte : sa propre MAC n'est jamais dans la table.
    private static func arpReadFailure(in discovered: [NetworkDevice], arpResolvedCount: Int) -> NetworkAlert? {
        let others = discovered.filter { !$0.isCurrentDevice }
        guard arpResolvedCount == 0, !others.isEmpty else { return nil }
        return NetworkAlert(
            severity:       .medium,
            category:       .scanHealth,
            title:          L10n.ARPFailure.title,
            description:    L10n.ARPFailure.description(others.count),
            deviceIP:       "",
            recommendation: L10n.ARPFailure.recommendation
        )
    }

    /// Les annotations (alias, note, type forcé) d'un appareil peuvent-elles être enregistrées ?
    /// Non pour un appareil sans MAC pendant une lecture ARP dégradée : il n'est pas en base.
    func canPersistAnnotations(for device: NetworkDevice) -> Bool {
        !(isARPDegraded && device.mac.isEmpty)
    }

    /// Détecte les appareils inconnus de SwiftData et génère des alertes `.intrusion`.
    /// N'est actif que si SwiftData contient déjà des données (pas au tout premier scan).
    /// Retourne le nombre de nouveaux appareils détectés (pour ScanSnapshot).
    @discardableResult
    private func detectAndAlertNewDevices(_ discovered: [NetworkDevice]) -> Int {
        let allPersisted = (try? modelContext.fetch(FetchDescriptor<PersistedDevice>())) ?? []
        // Ne comparer qu'aux appareils déjà vus **sur ce réseau**. Arriver sur un réseau
        // inconnu ne doit pas signaler chacun de ses appareils comme une intrusion : un
        // réseau jamais vu se comporte comme un premier scan — on apprend, on n'alerte pas.
        let onThisNetwork = allPersisted.filter { $0.networkID == currentNetworkID }
        guard !onThisNetwork.isEmpty else { return 0 }
        let knownKeys = Set(onThisNetwork.map(\.persistenceKey))

        var newDevices: [NetworkDevice] = []
        for device in discovered
        where !knownKeys.contains(device.persistenceKey(networkID: currentNetworkID)) {
            newDevices.append(device)
            alerts.append(NetworkAlert(
                severity:       .high,
                category:       .intrusion,
                title:          L10n.Intrusion.title,
                description:    L10n.Intrusion.description(device.displayName, device.ip),
                deviceIP:       device.ip,
                recommendation: L10n.Intrusion.recommendation
            ))
        }

        if !newDevices.isEmpty {
            Task { await notificationService.notifyNewDevices(newDevices) }
        }

        return newDevices.count
    }

    // MARK: - Oublier un appareil

    /// Supprime définitivement un appareil de SwiftData et de la liste courante.
    func forgetDevice(_ device: NetworkDevice) {
        let key = device.persistenceKey(networkID: currentNetworkID)
        var descriptor = FetchDescriptor<PersistedDevice>(
            predicate: #Predicate { $0.persistenceKey == key }
        )
        descriptor.fetchLimit = 1
        if let persisted = try? modelContext.fetch(descriptor).first {
            modelContext.delete(persisted)
            try? modelContext.save()
        }
        devices.removeAll { $0.id == device.id }
        if selectedDevice?.id == device.id { selectedDevice = nil }
    }

    // MARK: - Historique des scans

    private static let snapshotLimit = 30

    /// Charge les snapshots au démarrage, triés du plus récent au plus ancien.
    private func loadSnapshots() {
        let descriptor = FetchDescriptor<ScanSnapshot>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        self.snapshots = (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Enregistre un snapshot post-scan et élimine les entrées au-delà de la limite.
    private func saveSnapshot(date: Date, duration: Double, deviceCount: Int,
                               alertCount: Int, newDeviceCount: Int) {
        let snapshot = ScanSnapshot(
            date: date,
            durationSeconds: duration,
            deviceCount: deviceCount,
            alertCount: alertCount,
            newDeviceCount: newDeviceCount
        )
        modelContext.insert(snapshot)

        // Nettoyage : ne garder que les N plus récents
        let descriptor = FetchDescriptor<ScanSnapshot>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        if let all = try? modelContext.fetch(descriptor),
           all.count > Self.snapshotLimit {
            for old in all.dropFirst(Self.snapshotLimit) {
                modelContext.delete(old)
            }
        }

        try? modelContext.save()
        loadSnapshots()
    }

    /// Supprime un snapshot depuis l'UI (context menu / swipe-to-delete).
    func deleteSnapshot(_ snapshot: ScanSnapshot) {
        modelContext.delete(snapshot)
        try? modelContext.save()
        snapshots.removeAll { $0.id == snapshot.id }
    }

    // MARK: - Scan status helper
    private func setScanStatus(_ status: ScanStatus) {
        self.scanStatus = status
    }

    // MARK: - Refresh network info only (fast)
    func refreshNetworkInfo() async {
        let infos   = networkInfoService.fetchAllInterfaces()
        networkInfos = infos
        primaryNetwork = infos.first ?? .empty
    }

    // MARK: - Full scan
    func startFullScan() async {
        guard !scanStatus.isScanning else { return }

        let start = Date()
        alerts  = []
        devices = []

        // Step 1 : Network info
        scanStatus = .scanning(progress: 0.01, message: L10n.Scan.progressNetInfo)
        await refreshNetworkInfo()

        guard primaryNetwork.localIP != "—" else {
            scanStatus = .failed(error: L10n.Scan.noInterface)
            return
        }

        let subnet  = primaryNetwork.subnetCIDR
        let localIP = primaryNetwork.localIP
        let gateway = primaryNetwork.gateway

        // Step 2 : Host discovery
        let discoveredDevices = await networkScanner.discoverHosts(
            subnet: subnet,
            localIP: localIP,
            gateway: gateway
        ) { [weak self] progress, msg in
            await self?.setScanStatus(.scanning(progress: 0.05 + progress * 0.35, message: msg))
        }
        let arpResolved = await networkScanner.lastARPResolvedCount

        // La passerelle vient d'être scannée : l'identité du réseau est à jour et
        // gratuite. Doit précéder toute lecture ou écriture des clés de persistance.
        await refreshNetworkID(from: discoveredDevices)

        applyPersistedKnowledge(to: discoveredDevices)
        await MainActor.run { self.devices = discoveredDevices }

        // Step 3 : Port scan
        await portScanner.scanMultipleHosts(devices: discoveredDevices) { [weak self] progress, msg in
            await self?.setScanStatus(.scanning(progress: 0.40 + progress * 0.25, message: msg))
        }

        await MainActor.run { self.devices = discoveredDevices }

        // Step 3b : Bonjour discovery
        scanStatus = .scanning(progress: 0.65, message: L10n.Scan.bonjourDiscovering)
        await enricher.discoverBonjourServices()
        scanStatus = .scanning(progress: 0.70, message: L10n.Scan.bonjourDone)

        // Step 4 : Enrich devices
        await enricher.enrichAll(devices: discoveredDevices) { [weak self] progress, msg in
            await self?.setScanStatus(.scanning(progress: 0.70 + progress * 0.10, message: msg))
        }

        await MainActor.run { self.devices = discoveredDevices }

        // Step 5 : Vulnerability check
        let wifiInfo = networkInfos.first(where: { $0.interfaceType == "WiFi" })?.wifiInfo
        let newAlerts = await vulnChecker.checkAll(
            devices: discoveredDevices,
            wifiInfo: wifiInfo
        ) { [weak self] progress, msg in
            await self?.setScanStatus(.scanning(progress: 0.80 + progress * 0.18, message: msg))
        }

        // Step 6 : Update device statuses
        for device in discoveredDevices {
            let deviceAlerts = newAlerts.filter { $0.deviceIP == device.ip }
            if deviceAlerts.contains(where: { $0.severity >= .high }) {
                device.status = .alert
            } else if device.type != .unknown {
                device.status = .safe
            }
            device.scanState = .active
        }

        // Step 7 : Détection nouveaux appareils + persistance
        let newCount = detectAndPersist(discoveredDevices, arpResolvedCount: arpResolved)

        let scanDate = Date()
        let duration = scanDate.timeIntervalSince(start)

        saveSnapshot(
            date: scanDate,
            duration: duration,
            deviceCount: discoveredDevices.count,
            alertCount: newAlerts.count + newCount + (isARPDegraded ? 1 : 0),
            newDeviceCount: newCount
        )

        await MainActor.run {
            self.alerts       = newAlerts + self.alerts   // intrusion alerts en tête
            self.devices      = discoveredDevices
            self.lastScanDate = scanDate
            self.scanStatus   = .completed(duration: duration)
        }

        AccessibilityNotification.Announcement(
            L10n.A11y.scanDone(devices: discoveredDevices.count, alerts: newAlerts.count)
        ).post()
    }

    // MARK: - Quick scan (hosts only, no ports)
    func startQuickScan() async {
        guard !scanStatus.isScanning else { return }
        let start = Date()
        scanStatus = .scanning(progress: 0.01, message: L10n.Scan.quickScan)
        await refreshNetworkInfo()

        guard primaryNetwork.localIP != "—" else {
            scanStatus = .failed(error: L10n.Scan.noInterface); return
        }

        let discovered = await networkScanner.discoverHosts(
            subnet: primaryNetwork.subnetCIDR,
            localIP: primaryNetwork.localIP,
            gateway: primaryNetwork.gateway
        ) { [weak self] p, msg in
            await self?.setScanStatus(.scanning(progress: p * 0.95, message: msg))
        }
        let arpResolved = await networkScanner.lastARPResolvedCount

        await refreshNetworkID(from: discovered)
        applyPersistedKnowledge(to: discovered)
        for device in discovered { device.scanState = .active }

        let newCount = detectAndPersist(discovered, arpResolvedCount: arpResolved)

        let scanDate = Date()
        let duration = scanDate.timeIntervalSince(start)

        saveSnapshot(
            date: scanDate,
            duration: duration,
            deviceCount: discovered.count,
            alertCount: newCount + (isARPDegraded ? 1 : 0),
            newDeviceCount: newCount
        )

        await MainActor.run {
            self.devices      = discovered
            self.lastScanDate = scanDate
            self.scanStatus   = .completed(duration: duration)
        }

        AccessibilityNotification.Announcement(
            L10n.A11y.scanQuickDone(devices: discovered.count)
        ).post()
    }

    // MARK: - Mark alert as read
    func markAlertRead(_ alert: NetworkAlert) {
        if let idx = alerts.firstIndex(where: { $0.id == alert.id }) {
            alerts[idx].isRead = true
        }
    }

    func markAllAlertsRead() {
        for i in alerts.indices { alerts[i].isRead = true }
    }

    // MARK: - Annotations utilisateur

    /// Persiste l'alias, la note et le type overridé d'un appareil dans SwiftData.
    func persistAnnotation(for device: NetworkDevice) {
        let key = device.persistenceKey(networkID: currentNetworkID)
        var descriptor = FetchDescriptor<PersistedDevice>(
            predicate: #Predicate { $0.persistenceKey == key }
        )
        descriptor.fetchLimit = 1
        guard let persisted = try? modelContext.fetch(descriptor).first else { return }
        persisted.userAlias         = device.userAlias
        persisted.userNote          = device.userNote
        persisted.userOverrideTypeRaw = device.userOverrideType?.rawValue
        try? modelContext.save()
    }

    /// Force ou efface le type d'un appareil. `nil` revient à l'auto-détection.
    func setOverrideType(for device: NetworkDevice, to type: DeviceType?) {
        device.userOverrideType = type
        persistAnnotation(for: device)
    }

    // MARK: - Actions à la demande sur un appareil (panneau détail)

    func scanPortsFor(_ device: NetworkDevice) async {
        guard runningDeviceAction[device.id] == nil else { return }
        runningDeviceAction[device.id] = .ports
        defer { runningDeviceAction[device.id] = nil }

        let ports = await portScanner.scanPorts(
            host: device.ip,
            ports: CommonPort.all.map(\.number),
            timeout: 1.0
        ) { _, _ in }

        device.openPorts = ports
        device.lastSeen  = Date()
        upsertToStore([device])
    }

    func enrichDeviceManually(_ device: NetworkDevice) async {
        guard runningDeviceAction[device.id] == nil else { return }
        runningDeviceAction[device.id] = .enrich
        defer { runningDeviceAction[device.id] = nil }

        await enricher.discoverBonjourServices()
        await enricher.enrichDevice(device)
        upsertToStore([device])
    }

    func runSecurityAudit(for device: NetworkDevice) async {
        guard runningDeviceAction[device.id] == nil else { return }
        runningDeviceAction[device.id] = .audit
        defer { runningDeviceAction[device.id] = nil }
        let result = await SecurityAuditor.shared.audit(device: device)
        auditResults[device.id] = result
    }

    func checkVulnerabilitiesFor(_ device: NetworkDevice) async {
        guard runningDeviceAction[device.id] == nil else { return }
        runningDeviceAction[device.id] = .vulnerabilities
        defer { runningDeviceAction[device.id] = nil }

        let newAlerts = await vulnChecker.checkDevice(device)

        alerts.removeAll { $0.deviceIP == device.ip }
        alerts.append(contentsOf: newAlerts)
        alerts.sort { $0.severity > $1.severity }

        if newAlerts.contains(where: { $0.severity >= .high }) {
            device.status = .alert
        } else if device.type != .unknown {
            device.status = .safe
        }

        upsertToStore([device])
    }

    // MARK: - Demo Mode

    #if DEBUG
    /// Remplace l'état courant par un réseau fictif pour les screenshots / démos.
    /// Disponible en build DEBUG uniquement.
    func loadDemoData() {
        // Devices
        devices = DemoData.devices
        selectedDevice = nil

        // Network info
        primaryNetwork = DemoData.networkInfo
        networkInfos = [DemoData.networkInfo]

        // Alerts
        alerts = DemoData.alerts

        // Audit results
        auditResults = [:]
        for device in devices {
            if let raw = DemoData.auditResults[device.ip] {
                let findings = raw.findings.map { f in
                    SecurityAuditor.AuditFinding(severity: f.severity, title: f.title, detail: f.detail)
                }
                auditResults[device.id] = SecurityAuditor.AuditResult(
                    score: raw.score,
                    findings: findings,
                    credentialsTested: true
                )
            }
        }

        // Scan status
        scanStatus = .completed(duration: 8.4)
        lastScanDate = Date()
    }
    #endif
}

// MARK: - DeviceAction
enum DeviceAction {
    case ports
    case enrich
    case vulnerabilities
    case audit
}

// MARK: - DeviceFilter
enum DeviceFilter {
    case all
    case known
    case unknown
}
