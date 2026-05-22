import SwiftUI

// MARK: - DeviceDetailView
struct DeviceDetailView: View {
    @ObservedObject var device: NetworkDevice
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                deviceHeader
                identitySection
                networkSection
                if !device.openPorts.isEmpty { portsSection }
                let devAlerts = state.alerts.filter { $0.deviceIP == device.ip }
                if !devAlerts.isEmpty { alertsSection(devAlerts) }
            }
            .padding(16)
        }
        .background(Color(red: 0.08, green: 0.09, blue: 0.11))
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 400)
    }

    // MARK: - Header
    private var deviceHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(device.type.color.opacity(0.15))
                    .frame(width: 70, height: 70)
                Circle()
                    .stroke(device.status.color.opacity(0.6), lineWidth: 2)
                    .frame(width: 70, height: 70)
                Image(systemName: device.type.icon)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(device.type.color)
            }
            VStack(spacing: 4) {
                Text(device.displayName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text(device.ip)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))

                // Status badge
                HStack(spacing: 5) {
                    Circle().fill(device.status.color).frame(width: 7, height: 7)
                    Text(device.status.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(device.status.color)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(device.status.color.opacity(0.12))
                .cornerRadius(20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(detailCard)
        .cornerRadius(12)
    }

    // MARK: - Identity section
    private var identitySection: some View {
        DetailSection(title: "IDENTITÉ") {
            if !device.vendor.isEmpty {
                DetailRow(icon: "building.2", label: "Fabricant",  value: device.vendor)
            }
            DetailRow(icon: device.osGuess.icon, label: "Système",
                      value: device.osGuess.rawValue)
            if device.ttl > 0 {
                DetailRow(icon: "clock.arrow.circlepath", label: "TTL",
                          value: "\(device.ttl) sauts")
            }
            if !device.mac.isEmpty {
                DetailRow(icon: "checkmark.seal", label: "Adresse MAC",
                          value: device.mac, monospaced: true)
            }
            if !device.mdnsName.isEmpty {
                DetailRow(icon: "bonjour", label: "Bonjour",
                          value: device.mdnsName)
            }
            if !device.netbiosName.isEmpty {
                DetailRow(icon: "network.badge.shield.half.filled", label: "NetBIOS",
                          value: device.netbiosName)
            }
            if !device.hostname.isEmpty && device.hostname != device.mdnsName {
                DetailRow(icon: "globe", label: "DNS",
                          value: device.hostname)
            }
            DetailRow(icon: device.type.icon, label: "Type",
                      value: device.type.rawValue)
            if device.isCurrentDevice {
                DetailRow(icon: "arrow.up.circle.fill", label: "Rôle",
                          value: "Ce Mac (appareil courant)", accent: true)
            }
        }
    }

    // MARK: - Network section
    private var networkSection: some View {
        DetailSection(title: "RÉSEAU") {
            if device.responseTime > 0 {
                DetailRow(icon: "speedometer", label: "Latence",
                          value: String(format: "%.1f ms", device.responseTime),
                          valueColor: latencyColor)
            }
            if !device.httpBanner.isEmpty {
                DetailRow(icon: "server.rack", label: "Serveur HTTP",
                          value: device.httpBanner)
            }
            if !device.httpTitle.isEmpty {
                DetailRow(icon: "globe", label: "Page web",
                          value: device.httpTitle)
            }
            DetailRow(icon: "calendar", label: "Vu pour la 1ère fois",
                      value: device.firstSeen.formatted(date: .abbreviated, time: .shortened))
            DetailRow(icon: "clock", label: "Dernière activité",
                      value: device.lastSeen.formatted(date: .abbreviated, time: .shortened))
        }
    }

    // MARK: - Open ports section
    private var portsSection: some View {
        DetailSection(title: "PORTS OUVERTS (\(device.openPorts.count))") {
            ForEach(device.openPorts) { port in
                HStack(spacing: 10) {
                    // Port number badge
                    Text("\(port.port)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(port.isVulnerable ? .red : .white.opacity(0.7))
                        .frame(width: 44, alignment: .trailing)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(port.isVulnerable
                                      ? Color.red.opacity(0.15)
                                      : Color.white.opacity(0.07))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(port.service)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        if !port.notes.isEmpty {
                            Text(port.notes)
                                .font(.system(size: 11))
                                .foregroundColor(port.isVulnerable
                                                 ? Color.orange.opacity(0.8)
                                                 : Color.white.opacity(0.35))
                                .lineLimit(2)
                        }
                    }

                    Spacer()

                    if port.isVulnerable {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 12))
                            .foregroundColor(.green.opacity(0.6))
                    }
                }
                .padding(.vertical, 4)

                if port.id != device.openPorts.last?.id {
                    Divider().opacity(0.1)
                }
            }
        }
    }

    // MARK: - Alerts section
    private func alertsSection(_ alerts: [NetworkAlert]) -> some View {
        DetailSection(title: "ALERTES (\(alerts.count))") {
            ForEach(alerts) { alert in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: alert.severity.icon)
                        .font(.system(size: 13))
                        .foregroundColor(alert.severity.color)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(alert.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        if !alert.recommendation.isEmpty {
                            Text("→ \(alert.recommendation)")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.4))
                                .lineLimit(3)
                        }
                    }
                }
                .padding(.vertical, 3)

                if alert.id != alerts.last?.id {
                    Divider().opacity(0.1)
                }
            }
        }
    }

    // MARK: - Helpers
    private var latencyColor: Color {
        switch device.responseTime {
        case 0..<5:   return .green
        case 5..<20:  return Color(red: 0.6, green: 0.9, blue: 0.3)
        case 20..<50: return .yellow
        default:      return .orange
        }
    }

    private var detailCard: some ShapeStyle {
        Color(red: 0.11, green: 0.12, blue: 0.15)
    }
}

// MARK: - Reusable section container
struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
                .tracking(1.5)

            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(12)
            .background(Color(red: 0.11, green: 0.12, blue: 0.15))
            .cornerRadius(10)
        }
    }
}

// MARK: - Reusable detail row
struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    var monospaced: Bool = false
    var accent: Bool = false
    var valueColor: Color = .white

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(accent ? .blue : .white.opacity(0.3))
                .frame(width: 18)

            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.45))

            Spacer()

            Text(value)
                .font(monospaced
                      ? .system(size: 12, weight: .medium, design: .monospaced)
                      : .system(size: 13, weight: .medium))
                .foregroundColor(accent ? .blue : valueColor.opacity(valueColor == .white ? 0.85 : 1))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}
