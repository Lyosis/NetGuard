import Foundation
import SwiftUI
import Combine

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
        guard let d = lastScanDate else { return "Jamais scanné" }
        let interval = Date().timeIntervalSince(d)
        if interval < 60  { return "Dernier scan il y a \(Int(interval)) s" }
        if interval < 3600 { return "Dernier scan il y a \(Int(interval/60)) min" }
        return "Dernier scan il y a \(Int(interval/3600)) h"
    }

    // MARK: - Init
    init() {
        Task { await refreshNetworkInfo() }
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
            await MainActor.run {
                self?.scanStatus = .scanning(progress: 0.05 + progress * 0.35, message: msg)
            }
        }

        await MainActor.run { self.devices = discoveredDevices }

        // Step 3: Port scan
        await portScanner.scanMultipleHosts(devices: discoveredDevices) { [weak self] progress, msg in
            await MainActor.run {
                self?.scanStatus = .scanning(progress: 0.40 + progress * 0.30, message: msg)
            }
        }

        await MainActor.run { self.devices = discoveredDevices }

        // Step 4: Enrich devices (OS, mDNS, HTTP banners, latency)
        await enricher.enrichAll(devices: discoveredDevices) { [weak self] progress, msg in
            await MainActor.run {
                self?.scanStatus = .scanning(progress: 0.70 + progress * 0.10, message: msg)
            }
        }

        await MainActor.run { self.devices = discoveredDevices }

        // Step 5: Vulnerability check
        let wifiInfo = networkInfos.first(where: { $0.interfaceType == "WiFi" })?.wifiInfo
        let newAlerts = await vulnChecker.checkAll(
            devices: discoveredDevices,
            wifiInfo: wifiInfo
        ) { [weak self] progress, msg in
            await MainActor.run {
                self?.scanStatus = .scanning(progress: 0.80 + progress * 0.18, message: msg)
            }
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
            await MainActor.run {
                self?.scanStatus = .scanning(progress: p * 0.95, message: msg)
            }
        }

        let duration = Date().timeIntervalSince(start)
        await MainActor.run {
            self.devices    = discovered
            self.lastScanDate = Date()
            self.scanStatus   = .completed(duration: duration)
        }
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
