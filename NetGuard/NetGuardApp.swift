import SwiftUI
import SwiftData

@main
struct NetGuardApp: App {
    private let container: ModelContainer
    @StateObject private var appState: AppState

    init() {
        // Store dédié + reprise unique de l'ancien emplacement (cf. NetGuardStore).
        // Schéma versionné : les bases 1.0–1.1.3 sont reconnues comme V1 et migrées en V2.
        let store = NetGuardStore.open()
        self.container = store.container
        self._appState = StateObject(wrappedValue: AppState(
            modelContext: store.container.mainContext,
            isStorePersistent: store.failure == nil
        ))
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

            #if DEBUG
            // MARK: Menu Debug (screenshots / démo — build DEBUG uniquement)
            CommandMenu("Debug") {
                Button("Charger le réseau démo") {
                    appState.loadDemoData()
                }

                Button("Réinitialiser") {
                    appState.devices = []
                    appState.alerts  = []
                    appState.auditResults = [:]
                    appState.scanStatus = .idle
                }
            }
            #endif
        }
    }
}
