import SwiftUI
import SwiftData

@main
struct NetGuardApp: App {
    private let container: ModelContainer
    @StateObject private var appState: AppState

    init() {
        let c: ModelContainer
        do {
            c = try ModelContainer(for: PersistedDevice.self, ScanSnapshot.self)
        } catch {
            // Fallback mémoire si le schéma SwiftData est corrompu — données non persistées
            // mais l'app reste fonctionnelle.
            print("[NetGuard] ModelContainer init failed: \(error) — falling back to in-memory store")
            c = try! ModelContainer(
                for: PersistedDevice.self, ScanSnapshot.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
        self.container = c
        self._appState = StateObject(wrappedValue: AppState(modelContext: c.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .modelContainer(container)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu(L10n.Menu.scan) {
                Button(L10n.Menu.scanFull) {
                    Task { await appState.startFullScan() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(appState.scanStatus.isScanning)

                Button(L10n.Menu.scanQuick) {
                    Task { await appState.startQuickScan() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(appState.scanStatus.isScanning)

                Divider()

                Button(L10n.Menu.markAllRead) {
                    appState.markAllAlertsRead()
                }
                .keyboardShortcut("k", modifiers: [.command])
            }
        }
    }
}
