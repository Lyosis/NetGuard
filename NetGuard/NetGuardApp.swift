import SwiftUI

@main
struct NetGuardApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Scan") {
                Button("Scan complet") {
                    Task { await appState.startFullScan() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(appState.scanStatus.isScanning)

                Button("Scan rapide") {
                    Task { await appState.startQuickScan() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(appState.scanStatus.isScanning)

                Divider()

                Button("Marquer toutes les alertes comme lues") {
                    appState.markAllAlertsRead()
                }
                .keyboardShortcut("k", modifiers: [.command])
            }
        }
    }
}
