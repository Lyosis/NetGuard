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
    var unknownCount: Int    { devices.filter { $0.type == .unknown }.count }
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
        Task { await refreshNetworkInfo() }
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

        let duration = Date().timeIntervalSince(start)
        await MainActor.run {
            self.devices    = discovered
            self.lastScanDate = Date()
            self.scanStatus   = .completed(duration: duration)
        }

        // Annonce VoiceOver de fin de scan rapide
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
}
