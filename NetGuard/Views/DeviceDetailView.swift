import SwiftUI

// MARK: - DeviceDetailView
struct DeviceDetailView: View {
    @ObservedObject var device: NetworkDevice
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                deviceHeader
                actionsSection
                if hasAnyQuickAccess { quickAccessSection }
                identitySection
                networkSection
                if device.sslCertificate != nil { certificateSection }
                if !device.openPorts.isEmpty { portsSection }
                let devAlerts = state.alerts.filter { $0.deviceIP == device.ip }
                if !devAlerts.isEmpty { alertsSection(devAlerts) }
                notesSection
            }
            .padding(16)
        }
        .background(Color(red: 0.08, green: 0.09, blue: 0.11))
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 400)
    }

    // MARK: - Accès rapide (navigateur + lanceurs de protocoles)
    private var openPortNumbers: Set<Int> {
        Set(device.openPorts.map(\.port))
    }
    private var hasAnyQuickAccess: Bool {
        let webPorts: Set<Int> = [80, 8080, 8888, 443, 8443]
        let protoPorts: Set<Int> = [22, 445, 548, 5900, 21]
        return !openPortNumbers.isDisjoint(with: webPorts.union(protoPorts))
    }

    @ViewBuilder
    private var quickAccessSection: some View {
        DetailSection(title: L10n.QuickAccess.sectionTitle) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 78), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                // Navigateur — HTTPS prioritaire si dispo, sinon HTTP
                if let webPort = firstOpenPort(among: [443, 8443, 80, 8080, 8888]) {
                    let scheme = (webPort == 443 || webPort == 8443) ? "https" : "http"
                    QuickAccessButton(icon: "globe",
                                      label: L10n.QuickAccess.browser,
                                      hint: L10n.QuickAccess.browserHint,
                                      url: "\(scheme)://\(device.ip):\(webPort)/")
                }
                if openPortNumbers.contains(22) {
                    QuickAccessButton(icon: "terminal",
                                      label: L10n.QuickAccess.ssh,
                                      hint: L10n.QuickAccess.sshHint,
                                      url: "ssh://\(device.ip)")
                    QuickAccessButton(icon: "doc.text",
                                      label: L10n.QuickAccess.sftp,
                                      hint: L10n.QuickAccess.sftpHint,
                                      url: "sftp://\(device.ip)")
                }
                if openPortNumbers.contains(445) {
                    QuickAccessButton(icon: "folder.fill.badge.person.crop",
                                      label: L10n.QuickAccess.smb,
                                      hint: L10n.QuickAccess.smbHint,
                                      url: "smb://\(device.ip)")
                }
                if openPortNumbers.contains(548) {
                    QuickAccessButton(icon: "externaldrive.connected.to.line.below.fill",
                                      label: L10n.QuickAccess.afp,
                                      hint: L10n.QuickAccess.afpHint,
                                      url: "afp://\(device.ip)")
                }
                if openPortNumbers.contains(5900) {
                    QuickAccessButton(icon: "rectangle.on.rectangle",
                                      label: L10n.QuickAccess.vnc,
                                      hint: L10n.QuickAccess.vncHint,
                                      url: "vnc://\(device.ip)")
                }
                if openPortNumbers.contains(21) {
                    QuickAccessButton(icon: "arrow.up.arrow.down.circle",
                                      label: L10n.QuickAccess.ftp,
                                      hint: L10n.QuickAccess.ftpHint,
                                      url: "ftp://\(device.ip)")
                }
            }
        }
    }

    private func firstOpenPort(among priority: [Int]) -> Int? {
        priority.first(where: openPortNumbers.contains)
    }

    // MARK: - Certificate section (A2)
    @ViewBuilder
    private var certificateSection: some View {
        if let cert = device.sslCertificate {
            DetailSection(title: L10n.Certificate.sectionTitle) {
                // Badges en haut (état)
                HStack(spacing: 6) {
                    if cert.isExpired {
                        CertBadge(label: L10n.Certificate.badgeExpired,
                                  color: Color(red: 0.9, green: 0.2, blue: 0.2))
                    } else if cert.isNearExpiry {
                        CertBadge(label: L10n.Certificate.badgeNearExpiry,
                                  color: Color(red: 1.0, green: 0.6, blue: 0.0))
                    }
                    if cert.isSelfSigned {
                        CertBadge(label: L10n.Certificate.badgeSelfSigned,
                                  color: Color(red: 1.0, green: 0.6, blue: 0.0))
                    }
                    if cert.isTrusted {
                        CertBadge(label: L10n.Certificate.badgeTrusted,
                                  color: Color(red: 0.2, green: 0.75, blue: 0.4))
                    } else if !cert.isSelfSigned && !cert.isExpired {
                        CertBadge(label: L10n.Certificate.badgeUntrusted,
                                  color: Color(red: 0.9, green: 0.4, blue: 0.1))
                    }
                    Spacer()
                }
                .padding(.bottom, 4)

                DetailRow(icon: "person.text.rectangle",
                          label: L10n.Certificate.labelSubject,
                          value: cert.subject)
                DetailRow(icon: "building.columns",
                          label: L10n.Certificate.labelIssuer,
                          value: cert.issuer)
                DetailRow(icon: "calendar.badge.clock",
                          label: L10n.Certificate.labelValidFrom,
                          value: cert.validFrom.formatted(date: .abbreviated, time: .omitted))
                DetailRow(icon: "calendar.badge.exclamationmark",
                          label: L10n.Certificate.labelValidTo,
                          value: cert.validTo.formatted(date: .abbreviated, time: .omitted),
                          valueColor: cert.isExpired ? .red :
                                      cert.isNearExpiry ? .orange : .white)
                if !cert.isExpired {
                    DetailRow(icon: "clock",
                              label: L10n.Certificate.daysLeft(cert.daysUntilExpiry),
                              value: "")
                }
                if let err = cert.trustErrorDescription, !cert.isTrusted {
                    DetailRow(icon: "exclamationmark.triangle",
                              label: "Erreur",
                              value: err,
                              valueColor: .orange)
                }
            }
        }
    }

    // MARK: - Bindings annotations utilisateur
    private var aliasBinding: Binding<String> {
        Binding(
            get: { device.userAlias },
            set: { newValue in
                device.userAlias = newValue
                state.persistAnnotation(for: device)
            }
        )
    }
    private var noteBinding: Binding<String> {
        Binding(
            get: { device.userNote },
            set: { newValue in
                device.userNote = newValue
                state.persistAnnotation(for: device)
            }
        )
    }

    // MARK: - Actions section
    private var actionsSection: some View {
        let running = state.runningDeviceAction[device.id]
        let anyRunning = running != nil
        return DetailSection(title: L10n.DetailActions.sectionTitle) {
            HStack(spacing: 8) {
                ActionButton(
                    icon: "network",
                    label: L10n.DetailActions.scanPorts,
                    hint: L10n.DetailActions.scanPortsHint,
                    isRunning: running == .ports,
                    isDisabled: anyRunning
                ) {
                    Task { await state.scanPortsFor(device) }
                }
                ActionButton(
                    icon: "magnifyingglass",
                    label: L10n.DetailActions.enrich,
                    hint: L10n.DetailActions.enrichHint,
                    isRunning: running == .enrich,
                    isDisabled: anyRunning
                ) {
                    Task { await state.enrichDeviceManually(device) }
                }
                ActionButton(
                    icon: "shield",
                    label: L10n.DetailActions.checkVuln,
                    hint: L10n.DetailActions.checkVulnHint,
                    isRunning: running == .vulnerabilities,
                    isDisabled: anyRunning
                ) {
                    Task { await state.checkVulnerabilitiesFor(device) }
                }
            }
        }
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
                    Text(device.status.localizedName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(device.status.color)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(device.status.color.opacity(0.12))
                .cornerRadius(20)

                // Nom personnalisé (édition inline)
                TextField(L10n.UserAnnotation.aliasPlaceholder, text: aliasBinding)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)
                    .padding(.top, 2)
                    .accessibilityLabel(L10n.UserAnnotation.aliasPlaceholder)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(detailCard)
        .cornerRadius(12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(device.displayName), \(device.ip), \(device.status.localizedName)")
    }

    // MARK: - Identity section
    private var identitySection: some View {
        DetailSection(title: L10n.Detail.sectionIdentity) {
            if !device.vendor.isEmpty {
                DetailRow(icon: "building.2", label: L10n.Detail.labelVendor,  value: device.vendor)
            }
            DetailRow(icon: device.osGuess.icon, label: L10n.Detail.labelOS,
                      value: device.osGuess.localizedName)
            if device.ttl > 0 {
                DetailRow(icon: "clock.arrow.circlepath", label: L10n.Detail.labelTTL,
                          value: "\(device.ttl) sauts")
            }
            if !device.mac.isEmpty {
                DetailRow(icon: "checkmark.seal", label: L10n.Detail.labelMAC,
                          value: device.mac, monospaced: true)
            }
            if !device.mdnsName.isEmpty {
                DetailRow(icon: "bonjour", label: L10n.Detail.labelBonjour,
                          value: device.mdnsName)
            }
            if !device.bonjourServices.isEmpty {
                DetailRow(
                    icon: "dot.radiowaves.left.and.right",
                    label: L10n.Detail.labelBonjourServices,
                    value: device.bonjourServices
                        .map { $0
                            .replacingOccurrences(of: "._tcp", with: "")
                            .replacingOccurrences(of: "_", with: "")
                        }
                        .joined(separator: " · ")
                )
            }
            if !device.netbiosName.isEmpty {
                DetailRow(icon: "network.badge.shield.half.filled", label: L10n.Detail.labelNetBIOS,
                          value: device.netbiosName)
            }
            if !device.hostname.isEmpty && device.hostname != device.mdnsName {
                DetailRow(icon: "globe", label: L10n.Detail.labelDNS,
                          value: device.hostname)
            }
            DetailRow(icon: device.type.icon, label: L10n.Detail.labelType,
                      value: device.type.localizedName)
            if device.isCurrentDevice {
                DetailRow(icon: "arrow.up.circle.fill", label: L10n.Detail.labelRole,
                          value: "Ce Mac (appareil courant)", accent: true)
            }
        }
    }

    // MARK: - Network section
    private var networkSection: some View {
        DetailSection(title: L10n.Detail.sectionNetwork) {
            if device.responseTime > 0 {
                DetailRow(icon: "speedometer", label: L10n.Detail.labelLatency,
                          value: String(format: "%.1f ms", device.responseTime),
                          valueColor: latencyColor)
            }
            if !device.httpBanner.isEmpty {
                DetailRow(icon: "server.rack", label: L10n.Detail.labelHTTPServer,
                          value: device.httpBanner)
            }
            if !device.httpTitle.isEmpty {
                DetailRow(icon: "globe", label: L10n.Detail.labelWebPage,
                          value: device.httpTitle)
            }
            DetailRow(icon: "calendar", label: L10n.Detail.labelFirstSeen,
                      value: device.firstSeen.formatted(date: .abbreviated, time: .shortened))
            DetailRow(icon: "clock", label: L10n.Detail.labelLastSeen,
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

    // MARK: - Notes section (annotations utilisateur)
    private var notesSection: some View {
        DetailSection(title: L10n.UserAnnotation.notesSection) {
            ZStack(alignment: .topLeading) {
                if device.userNote.isEmpty {
                    Text(L10n.UserAnnotation.notesPlaceholder)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.25))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: noteBinding)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(minHeight: 80)
            }
            .accessibilityLabel(L10n.UserAnnotation.notesSection)
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
                .accessibilityHidden(true)

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
        .accessibilityElement(children: .combine)
    }
}

// MARK: - QuickAccessButton (panneau détail — section ACCÈS RAPIDE)
/// Bouton compact qui ouvre une URL via `NSWorkspace.shared.open(_:)`.
/// Les protocoles `ssh://`, `smb://`, `afp://`, `vnc://`, `sftp://`, `ftp://`,
/// `http(s)://` sont gérés par les apps système (Terminal, Finder,
/// Screen Sharing, navigateur par défaut).
struct QuickAccessButton: View {
    let icon: String
    let label: String
    let hint: String
    let url: String

    var body: some View {
        Button {
            if let u = URL(string: url) {
                NSWorkspace.shared.open(u)
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(height: 18)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .foregroundColor(.white.opacity(0.85))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(hint)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }
}

// MARK: - CertBadge (panneau détail — section CERTIFICAT SSL)
/// Petit chip coloré (« Approuvé », « Auto-signé », « Expiré », etc.).
struct CertBadge: View {
    let label: String
    let color: Color
    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .cornerRadius(10)
    }
}

// MARK: - ActionButton (panneau détail)
/// Bouton compact icône + label avec état loading. Utilisé dans la section
/// ACTIONS pour les analyses à la demande (ports, enrichir, vulnérabilités).
struct ActionButton: View {
    let icon: String
    let label: String
    let hint: String
    let isRunning: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    if isRunning {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .frame(height: 18)

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDisabled ? Color.white.opacity(0.04) : Color.blue.opacity(0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(isDisabled ? 0.05 : 0.14), lineWidth: 0.5)
            )
            .foregroundColor(isDisabled ? .white.opacity(0.3) : .white.opacity(0.9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(hint)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }
}
