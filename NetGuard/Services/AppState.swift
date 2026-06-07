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
        Task { await refreshNetworkInfo() }
        Task.detached(priority: .utility) {
            await OUIDatabase.shared.preload()
        }
    }

    deinit {
        networkMonitor.stop()
    }

    // MARK: - Persistance SwiftData

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
            modelContext.insert(PersistedDevice.make(from: device))
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
        self.devices      = persisted.map { $0.toNetworkDevice() }
        self.lastScanDate = persisted.first?.lastSeen
    }

    /// Upsert des appareils dans SwiftData après un scan. Fetch unique → pas de N+1.
    private func upsertToStore(_ scanned: [NetworkDevice]) {
        let allPersisted = (try? modelContext.fetch(FetchDescriptor<PersistedDevice>())) ?? []
        let byKey = Dictionary(uniqueKeysWithValues: allPersisted.map { ($0.persistenceKey, $0) })

        for device in scanned {
            if let existing = byKey[device.persistenceKey] {
                existing.update(from: device)
            } else {
                modelContext.insert(PersistedDevice.make(from: device))
            }
        }
        try? modelContext.save()
    }

    /// Applique les annotations (alias, note, override) depuis SwiftData aux devices fraîchement scannés.
    /// Fetch unique — O(n) total.
    private func applyPersistedAnnotations(to list: [NetworkDevice]) {
        let allPersisted = (try? modelContext.fetch(FetchDescriptor<PersistedDevice>())) ?? []
        let byKey = Dictionary(uniqueKeysWithValues: allPersisted.map { ($0.persistenceKey, $0) })
        for device in list {
            guard let persisted = byKey[device.persistenceKey] else { continue }
            device.userAlias        = persisted.userAlias
            device.userNote         = persisted.userNote
            device.userOverrideType = persisted.userOverrideTypeRaw.flatMap { DeviceType(rawValue: $0) }
        }
    }

    /// Détecte les appareils inconnus de SwiftData et génère des alertes `.intrusion`.
    /// N'est actif que si SwiftData contient déjà des données (pas au tout premier scan).
    /// Retourne le nombre de nouveaux appareils détectés (pour ScanSnapshot).
    @discardableResult
    private func detectAndAlertNewDevices(_ discovered: [NetworkDevice]) -> Int {
        let allPersisted = (try? modelContext.fetch(FetchDescriptor<PersistedDevice>())) ?? []
        guard !allPersisted.isEmpty else { return 0 }
        let knownKeys = Set(allPersisted.map(\.persistenceKey))

        var newDevices: [NetworkDevice] = []
        for device in discovered where !knownKeys.contains(device.persistenceKey) {
            newDevices.append(device)
            alerts.append(NetworkAlert(
                severity:       .high,
                category:       .intrusion,
                title:          "Nouvel appareil détecté",
                description:    "\(device.displayName) (\(device.ip)) apparaît pour la première fois sur ce réseau.",
                deviceIP:       device.ip,
                recommendation: "Vérifiez que cet appareil est autorisé sur votre réseau."
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
        let key = device.persistenceKey
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
        scanStatus = .scanning(progress: 0.01, message: "Récupération des informations réseau…")
        await refreshNetworkInfo()

        guard primaryNetwork.localIP != "—" else {
            scanStatus = .failed(error: "Aucune interface réseau active")
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

        applyPersistedAnnotations(to: discoveredDevices)
        await MainActor.run { self.devices = discoveredDevices }

        // Step 3 : Port scan
        await portScanner.scanMultipleHosts(devices: discoveredDevices) { [weak self] progress, msg in
            await self?.setScanStatus(.scanning(progress: 0.40 + progress * 0.25, message: msg))
        }

        await MainActor.run { self.devices = discoveredDevices }

        // Step 3b : Bonjour discovery
        scanStatus = .scanning(progress: 0.65, message: "Découverte des services Bonjour…")
        await enricher.discoverBonjourServices()
        scanStatus = .scanning(progress: 0.70, message: "Services Bonjour découverts")

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
        let newCount = detectAndAlertNewDevices(discoveredDevices)
        upsertToStore(discoveredDevices)

        let scanDate = Date()
        let duration = scanDate.timeIntervalSince(start)

        saveSnapshot(
            date: scanDate,
            duration: duration,
            deviceCount: discoveredDevices.count,
            alertCount: newAlerts.count + newCount,
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
        scanStatus = .scanning(progress: 0.01, message: "Scan rapide…")
        await refreshNetworkInfo()

        guard primaryNetwork.localIP != "—" else {
            scanStatus = .failed(error: "Aucune interface réseau active"); return
        }

        let discovered = await networkScanner.discoverHosts(
            subnet: primaryNetwork.subnetCIDR,
            localIP: primaryNetwork.localIP,
            gateway: primaryNetwork.gateway
        ) { [weak self] p, msg in
            await self?.setScanStatus(.scanning(progress: p * 0.95, message: msg))
        }

        applyPersistedAnnotations(to: discovered)
        for device in discovered { device.scanState = .active }

        let newCount = detectAndAlertNewDevices(discovered)
        upsertToStore(discovered)

        let scanDate = Date()
        let duration = scanDate.timeIntervalSince(start)

        saveSnapshot(
            date: scanDate,
            duration: duration,
            deviceCount: discovered.count,
            alertCount: newCount,
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
        let key = device.persistenceKey
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

    /// Remplace l'état courant par un réseau fictif pour les screenshots / démos.
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
