import SwiftUI

// MARK: - SidebarView
struct SidebarView: View {
    @EnvironmentObject var state: AppState
    @State private var showingAlerts = false
    @State private var scanType: ScanTypeSheet? = nil
    @State private var selectedTab: SidebarTab = .network

    enum ScanTypeSheet: Identifiable {
        case full, quick
        var id: Int { hashValue }
    }

    enum SidebarTab {
        case network, history
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            Divider().overlay(Color.white.opacity(0.08))

            // Sélecteur Réseau / Historique
            tabPicker

            if selectedTab == .network {
                // Bannière changement réseau (NWPathMonitor)
                if let event = state.networkMonitor.changeEvent {
                    NetworkChangeBanner(event: event) {
                        state.networkMonitor.dismissEvent()
                    } onRescan: {
                        state.networkMonitor.dismissEvent()
                        Task { await state.refreshNetworkInfo() }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                ScrollView {
                    VStack(spacing: 12) {
                        metricsGrid
                        networkInfoSection
                        alertsSection
                    }
                    .padding(14)
                }

                Divider().overlay(Color.white.opacity(0.08))
                scanButtons
            } else {
                HistoryView()
            }
        }
        .glassPanelBackground()
        .frame(minWidth: 340, idealWidth: 380, maxWidth: 440)
        .animation(.easeInOut(duration: 0.3), value: state.networkMonitor.changeEvent?.id)
    }

    // MARK: - Tab Picker
    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            Text(L10n.History.tabNetwork).tag(SidebarTab.network)
            Text(L10n.History.tabHistory).tag(SidebarTab.history)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.App.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 8, height: 8)
                    Text(state.lastScanLabel)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var statusDotColor: Color {
        switch state.scanStatus {
        case .scanning:  return .yellow
        case .completed: return state.totalAlerts > 0 ? .orange : .green
        case .failed:    return .red
        case .idle:      return .gray
        }
    }

    // MARK: - Metrics Grid
    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            MetricCard(
                title: L10n.Sidebar.metricDevices,
                value: "\(state.devices.count)",
                color: .white,
                isActive: state.deviceFilter == .known,
                action: { state.toggleFilter(.known) }
            )
            MetricCard(title: L10n.Sidebar.metricPorts, value: "\(state.openPortCount)",
                       color: state.openPortCount > 0 ? .orange : .green)
            MetricCard(title: L10n.Sidebar.metricEncrypt, value: wifiEncryptionShort,
                       color: wifiEncryptionColor)
            MetricCard(
                title: L10n.Sidebar.metricUnknown,
                value: "\(state.unknownCount)",
                color: state.unknownCount > 0 ? .orange : .green,
                isActive: state.deviceFilter == .unknown,
                action: { state.toggleFilter(.unknown) }
            )
        }
    }

    private var wifiEncryptionShort: String {
        let s = state.wifiEncryption
        if s.contains("WPA3") { return "WPA3" }
        if s.contains("WPA2") { return "WPA2" }
        if s.contains("WPA")  { return "WPA" }
        if s.contains("WEP")  { return "WEP" }
        if s.contains("Ouvert") || s.contains("Open") { return "Ouvert" }
        return s == "—" ? "—" : s
    }

    private var wifiEncryptionColor: Color {
        let s = wifiEncryptionShort
        if s.contains("WPA3") || s.contains("WPA2") { return .green }
        if s.contains("WPA")  { return .yellow }
        if s.contains("WEP") || s.contains("Ouvert") { return .red }
        return .gray
    }

    // MARK: - Network Info
    private var networkInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: L10n.Sidebar.sectionNetwork)
            ForEach(state.networkInfos.prefix(2), id: \.interfaceName) { info in
                NetworkInfoRow(info: info)
            }
            if state.networkInfos.isEmpty {
                InfoRow(label: "Interface", value: "—")
            }
        }
        .padding(10)
        .glassCard(cornerRadius: 8)
    }

    // MARK: - Alerts
    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(title: L10n.Sidebar.sectionAlerts)
                Spacer()
                if state.totalAlerts > 0 {
                    Button(L10n.Sidebar.markAllRead) { state.markAllAlertsRead() }
                        .font(.system(size: 13))
                        .foregroundColor(.blue)
                        .buttonStyle(.plain)
                }
            }

            if state.alerts.isEmpty {
                Text(state.scanStatus.isScanning ? L10n.Sidebar.scanning : L10n.Sidebar.noAlerts)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(state.alerts.prefix(5)) { alert in
                    AlertRow(alert: alert)
                        .onTapGesture { state.markAlertRead(alert) }
                }
                if state.alerts.count > 5 {
                    Button(L10n.Sidebar.seeAll(state.alerts.count)) {
                        showingAlerts = true
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.blue)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
                }
            }
        }
        .padding(10)
        .glassCard(cornerRadius: 8)
        .sheet(isPresented: $showingAlerts) { AllAlertsSheet() }
    }

    // MARK: - Scan Buttons
    private var scanButtons: some View {
        VStack(spacing: 8) {
            // Scan progress bar
            if case .scanning(let p, let msg) = state.scanStatus {
                VStack(spacing: 4) {
                    ProgressView(value: p)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                    Text(msg)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }

            HStack(spacing: 8) {
                Button {
                    Task { await state.startFullScan() }
                } label: {
                    Label(L10n.Sidebar.scanFull, systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ScanButtonStyle(color: .blue))
                .disabled(state.scanStatus.isScanning)

                Button {
                    Task { await state.startQuickScan() }
                } label: {
                    Label(L10n.Sidebar.scanQuick, systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ScanButtonStyle(color: Color(red: 0.2, green: 0.5, blue: 0.8)))
                .disabled(state.scanStatus.isScanning)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
            .padding(.top, state.scanStatus.isScanning ? 6 : 10)
        }
    }

}

// MARK: - Sub-components

struct MetricCard: View {
    let title: String
    let value: String
    let color: Color
    /// Bordure bleue et fond plus clair quand `true`. Indique un filtre actif.
    var isActive: Bool = false
    /// Si fourni, la carte devient un bouton qui invoque cette closure au tap.
    /// Un petit chevron est affiché en haut à droite pour signaler l'interactivité.
    var action: (() -> Void)? = nil

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(isActive ? 0.85 : 0.45))
                    .lineLimit(1)
                Spacer()
                if action != nil {
                    Image(systemName: isActive ? "xmark.circle.fill"
                                               : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 11))
                        .foregroundColor(isActive ? .blue : .white.opacity(0.3))
                }
            }
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive
                      ? Color.blue.opacity(0.15)
                      : Color(red: 0.12, green: 0.13, blue: 0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.blue.opacity(0.55) : Color.clear,
                        lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    var body: some View {
        if let action {
            Button(action: action) { cardContent }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title), \(value)")
                .accessibilityHint(isActive
                    ? "Filtre actif. Touchez pour désactiver."
                    : "Touchez pour filtrer la carte sur cette catégorie.")
                .accessibilityAddTraits(.isButton)
        } else {
            cardContent
        }
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white.opacity(0.35))
            .tracking(1.5)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.45))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
        }
    }
}

struct NetworkInfoRow: View {
    let info: NetworkInfo
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: info.interfaceType == "WiFi" ? "wifi" : "cable.connector")
                    .font(.system(size: 13))
                    .foregroundColor(.blue)
                Text("\(info.interfaceName) (\(info.interfaceType))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            InfoRow(label: L10n.Sidebar.labelLocalIP,  value: info.localIP)
            InfoRow(label: L10n.Sidebar.labelGateway,  value: info.gateway)
            InfoRow(label: L10n.Sidebar.labelDNS,      value: info.dns.first ?? "—")
            InfoRow(label: L10n.Sidebar.labelSubnet,   value: info.subnetCIDR.isEmpty ? info.subnet : info.subnetCIDR)
            if let wifi = info.wifiInfo {
                InfoRow(label: L10n.Sidebar.labelSSID,     value: wifi.ssid)
                InfoRow(label: L10n.Sidebar.labelSecurity, value: wifi.security)
            }
        }
    }
}

struct AlertRow: View {
    let alert: NetworkAlert

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: alert.severity.icon)
                .font(.system(size: 15))
                .foregroundColor(alert.severity.color)
                .frame(width: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(alert.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(alert.isRead ? .white.opacity(0.4) : .white.opacity(0.9))
                    .lineLimit(2)
                Text(alert.description)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.35))
                    .lineLimit(2)
            }
            Spacer()
            if !alert.isRead {
                Circle()
                    .fill(alert.severity.color)
                    .frame(width: 6, height: 6)
                    .padding(.top, 4)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(alert.severity.color.opacity(alert.isRead ? 0.03 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(alert.severity.color.opacity(alert.isRead ? 0.05 : 0.2), lineWidth: 0.5)
        )
    }
}

// MARK: - Scan Button Style
struct ScanButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(configuration.isPressed ? 0.6 : 0.85))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - All Alerts Sheet
struct AllAlertsSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.Sidebar.allAlerts)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(L10n.Sidebar.close) { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(state.alerts) { alert in
                        AlertRow(alert: alert)
                            .onTapGesture { state.markAlertRead(alert) }
                    }
                }
                .padding()
            }
        }
        .glassPanelBackground()
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - NetworkChangeBanner
struct NetworkChangeBanner: View {
    let event: NetworkChangeEvent
    let onDismiss: () -> Void
    let onRescan: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: event.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text(L10n.Monitor.tapToRescan)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(event.color.opacity(0.85))
        .contentShape(Rectangle())
        .onTapGesture { onRescan() }
    }
}
