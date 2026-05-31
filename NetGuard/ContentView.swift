import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HSplitView {
            // Colonne 1 — Stats / réseau / alertes
            SidebarView()

            // Colonne 2 — Carte topologique
            NetworkMapView()
                .frame(minWidth: 460)

            // Colonne 3 — Détail appareil (visible si sélectionné)
            if let device = state.selectedDevice {
                DeviceDetailView(device: device)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                DeviceDetailPlaceholder()
            }
        }
        .frame(minWidth: 1300, idealWidth: 1550, minHeight: 780)
        .background(Color(red: 0.06, green: 0.07, blue: 0.09))
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: state.selectedDevice?.id)
    }
}

// MARK: - Placeholder when no device selected
struct DeviceDetailPlaceholder: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "cursorarrow.click")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.1))
            Text(L10n.Detail.placeholder)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.2))
            Text(L10n.Detail.placeholderSub)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.12))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.09, blue: 0.11))
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 400)
    }
}

#Preview {
    let container = try! ModelContainer(for: PersistedDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    ContentView()
        .environmentObject(AppState(modelContext: container.mainContext))
        .modelContainer(container)
}
