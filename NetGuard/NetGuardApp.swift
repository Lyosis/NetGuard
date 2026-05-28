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
