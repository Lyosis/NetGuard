import SwiftUI

// MARK: - HistoryView
struct HistoryView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if state.snapshots.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(state.snapshots) { snapshot in
                        SnapshotRow(snapshot: snapshot)
                    }
                }
                .padding(14)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.white.opacity(0.2))
            Text(L10n.History.empty)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - SnapshotRow
struct SnapshotRow: View {
    @EnvironmentObject var state: AppState
    let snapshot: ScanSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // En-tête : date + durée
            HStack {
                Text(snapshot.date, style: .date)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Text(snapshot.date, style: .time)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
                Text(L10n.History.duration(snapshot.durationSeconds))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.35))
            }

            // Métriques
            HStack(spacing: 12) {
                snapshotBadge(
                    icon: "network",
                    value: "\(snapshot.deviceCount)",
                    label: L10n.History.devices,
                    color: .white
                )
                snapshotBadge(
                    icon: "exclamationmark.triangle",
                    value: "\(snapshot.alertCount)",
                    label: L10n.History.alerts,
                    color: snapshot.alertCount > 0 ? .orange : .green
                )
                if snapshot.newDeviceCount > 0 {
                    snapshotBadge(
                        icon: "plus.circle",
                        value: "\(snapshot.newDeviceCount)",
                        label: L10n.History.newDevices,
                        color: .yellow
                    )
                }
            }
        }
        .padding(10)
        .glassCard(cornerRadius: 8)
        .contextMenu {
            Button(role: .destructive) {
                state.deleteSnapshot(snapshot)
            } label: {
                Label(L10n.History.delete, systemImage: "trash")
            }
        }
    }

    private func snapshotBadge(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color.opacity(0.8))
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
        }
    }
}
