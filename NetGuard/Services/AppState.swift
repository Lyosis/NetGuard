import Foundation
import SwiftUI
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

    /// Sous-ensemble de `devices` à afficher selon le filtre courant.
    /// `.all` → tout, `.known` → tout sauf `.unknown`, `.unknown` → uniquement `.unknown`.
    var filteredDevices: [NetworkDevice] {
        switch deviceFilter {
        case .all:     return devices
        case .known:   return devices.filter { $0.effectiveType != .unknown }
        case .unknown: return devices.filter { $0.effectiveType == .unknown }
        }
    }

    /// Bascule entre le filtre demandé et `.all` (re-clic = désactivation).
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
    init() {
        networkMonitor.start()
        loadCachedScan()
        Task { await refreshNetworkInfo() }
        // Précharge la base OUI IEEE (~3 MB) en background pour ne pas
        // ralentir le premier scan complet.
        Task.detached(priority: .utility) {
            await OUIDatabase.shared.preload()
        }
    }

    // MARK: - Cache du dernier scan (stop-gap avant SwiftData A5)
    private func loadCachedScan() {
        guard let snap = ScanCache.shared.load() else { return }
        self.devices      = snap.devices
        self.alerts       = snap.alerts
        self.lastScanDate = snap.date
        // Réapplique les annotations utilisateur (MAC déjà connue dans le cache)
        applyUserAnnotations(to: snap.devices)
    }

    private func saveCachedScan() {
        let label = "\(primaryNetwork.interfaceName) — \(primaryNetwork.subnetCIDR)"
        ScanCache.shared.save(devices: devices, alerts: alerts, networkLabel: label)
    }

    deinit {
        networkMonitor.stop()
    }

    // MARK: - Scan status helper
    /// Met à jour `scanStatus` sur le MainActor depuis les handlers de progression `@Sendable`.
    /// Évite la closure imbriquée `MainActor.run { self?... }` qui capture `self` dans du code concurrent (interdit en Swift 6).
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
        alerts = []
        devices = []

        // Step 1: Network info
        scanStatus = .scanning(progress: 0.01, message: "Récupération des informations réseau…")
        await refreshNetworkInfo()

        guard primaryNetwork.localIP != "—" else {
            scanStatus = .failed(error: "Aucune interface réseau active")
            return
        }

        let subnet  = primaryNetwork.subnetCIDR
        let localIP = primaryNetwork.localIP
        let gateway = primaryNetwork.gateway

        // Step 2: Host discovery
        let discoveredDevices = await networkScanner.discoverHosts(
            subnet: subnet,
            localIP: localIP,
            gateway: gateway
        ) { [weak self] progress, msg in
            await self?.setScanStatus(.scanning(progress: 0.05 + progress * 0.35, message: msg))
        }

        applyUserAnnotations(to: discoveredDevices)
        await MainActor.run { self.devices = discoveredDevices }

        // Step 3: Port scan
        await portScanner.scanMultipleHosts(devices: discoveredDevices) { [weak self] progress, msg in
            await self?.setScanStatus(.scanning(progress: 0.40 + progress * 0.25, message: msg))
        }

        await MainActor.run { self.devices = discoveredDevices }

        // Step 3b: Bonjour discovery (NWBrowser — tous les services en ~3s, en parallèle)
        scanStatus = .scanning(progress: 0.65, message: "Découverte des services Bonjour…")
        await enricher.discoverBonjourServices()
        scanStatus = .scanning(progress: 0.70, message: "Services Bonjour découverts")

        // Step 4: Enrich devices (OS, Bonjour, NetBIOS, HTTP banners, latency)
        await enricher.enrichAll(devices: discoveredDevices) { [weak self] progress, msg in
            await self?.setScanStatus(.scanning(progress: 0.70 + progress * 0.10, message: msg))
        }

        await MainActor.run { self.devices = discoveredDevices }

        // Step 5: Vulnerability check
        let wifiInfo = networkInfos.first(where: { $0.interfaceType == "WiFi" })?.wifiInfo
        let newAlerts = await vulnChecker.checkAll(
            devices: discoveredDevices,
            wifiInfo: wifiInfo
        ) { [weak self] progress, msg in
            await self?.setScanStatus(.scanning(progress: 0.80 + progress * 0.18, message: msg))
        }

        // Step 6: Update device statuses
        for device in discoveredDevices {
            let deviceAlerts = newAlerts.filter { $0.deviceIP == device.ip }
            if deviceAlerts.contains(where: { $0.severity >= .high }) {
                device.status = .alert
            } else if device.type != .unknown {
                device.status = .safe
            }
        }

        await MainActor.run {
            self.alerts     = newAlerts
            self.devices    = discoveredDevices
            self.lastScanDate = Date()
            let duration    = Date().timeIntervalSince(start)
            self.scanStatus = .completed(duration: duration)
        }

        // Cache disque (stop-gap avant SwiftData A5)
        saveCachedScan()

        // Annonce VoiceOver de fin de scan
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

        applyUserAnnotations(to: discovered)
        let duration = Date().timeIntervalSince(start)
        await MainActor.run {
            self.devices    = discovered
            self.lastScanDate = Date()
            self.scanStatus   = .completed(duration: duration)
        }

        // Cache disque (stop-gap avant SwiftData A5)
        saveCachedScan()

        // Annonce VoiceOver de fin de scan rapide
        AccessibilityNotification.Announcement(
            L10n.A11y.scanQuickDone(devices: discovered.count)
        ).post()
    }

    // MARK: - Mark alert as read
    func markAlertRead(_ alert: NetworkAlert) {
        if let idx = alerts.firstIndex(where: { $0.id == alert.id }) {
            alerts[idx].isRead = true
            saveCachedScan()
        }
    }

    func markAllAlertsRead() {
        for i in alerts.indices { alerts[i].isRead = true }
        saveCachedScan()
    }

    // MARK: - Annotations utilisateur (nom + notes, persistées par MAC)

    /// Charge l'alias + note pour chaque device depuis `UserAnnotationsStore`.
    /// Appelée après chaque scan une fois les MAC connues.
    private func applyUserAnnotations(to list: [NetworkDevice]) {
        let store = UserAnnotationsStore.shared
        for device in list {
            let a = store.annotation(for: device.mac)
            device.userAlias = a.alias
            device.userNote  = a.note
            device.userOverrideType = a.overrideType
        }
    }

    /// Sauvegarde l'annotation courante d'un device (appelée à chaque édition
    /// du champ alias, des notes, ou du type forcé dans `DeviceDetailView`).
    func persistAnnotation(for device: NetworkDevice) {
        UserAnnotationsStore.shared.save(
            mac:          device.mac,
            alias:        device.userAlias,
            note:         device.userNote,
            overrideType: device.userOverrideType
        )
    }

    /// Force ou efface le type d'un appareil. `nil` revient à l'auto-détection.
    /// Met à jour `runningDeviceAction[device.id]`, persiste l'annotation, et
    /// resauvegarde le cache pour que la valeur survive au quit.
    func setOverrideType(for device: NetworkDevice, to type: DeviceType?) {
        device.userOverrideType = type
        persistAnnotation(for: device)
        saveCachedScan()
    }

    // MARK: - Actions à la demande sur un appareil (panneau détail)

    /// Scanne les ports d'un seul appareil. Met à jour `device.openPorts`.
    func scanPortsFor(_ device: NetworkDevice) async {
        guard runningDeviceAction[device.id] == nil else { return }
        runningDeviceAction[device.id] = .ports
        defer { runningDeviceAction[device.id] = nil }

        let ports = await portScanner.scanPorts(
            host: device.ip,
            ports: CommonPort.all.map(\.number),
            timeout: 1.0
        ) { _, _ in }   // pas de progression UI pour cette action ponctuelle

        device.openPorts = ports
        device.lastSeen  = Date()
        saveCachedScan()
    }

    /// Enrichit un seul appareil : ping/TTL, NetBIOS, HTTP, OS guess, Bonjour.
    /// Lance d'abord la découverte Bonjour globale (3 s) pour que la table soit
    /// à jour avant l'enrichissement.
    func enrichDeviceManually(_ device: NetworkDevice) async {
        guard runningDeviceAction[device.id] == nil else { return }
        runningDeviceAction[device.id] = .enrich
        defer { runningDeviceAction[device.id] = nil }

        await enricher.discoverBonjourServices()
        await enricher.enrichDevice(device)
        saveCachedScan()
    }

    /// Vérifie les vulnérabilités d'un seul appareil. Remplace ses alertes
    /// dans `self.alerts` et met à jour son statut (safe / alert).
    func checkVulnerabilitiesFor(_ device: NetworkDevice) async {
        guard runningDeviceAction[device.id] == nil else { return }
        runningDeviceAction[device.id] = .vulnerabilities
        defer { runningDeviceAction[device.id] = nil }

        let newAlerts = await vulnChecker.checkDevice(device)

        // Remplacer les alertes existantes de ce device par les nouvelles
        alerts.removeAll { $0.deviceIP == device.ip }
        alerts.append(contentsOf: newAlerts)
        alerts.sort { $0.severity > $1.severity }

        // Mettre à jour le statut visuel
        if newAlerts.contains(where: { $0.severity >= .high }) {
            device.status = .alert
        } else if device.type != .unknown {
            device.status = .safe
        }

        saveCachedScan()
    }
}

// MARK: - DeviceAction
/// Action ponctuelle en cours sur un appareil (affichage du spinner du bouton).
enum DeviceAction {
    case ports
    case enrich
    case vulnerabilities
}

// MARK: - DeviceFilter
/// Filtre de la carte réseau, contrôlé depuis les MetricCards de la sidebar.
enum DeviceFilter {
    case all
    case known      // tous sauf .unknown
    case unknown
}
