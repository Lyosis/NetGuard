import Foundation
import Network
import SwiftUI

// MARK: - NetworkChangeEvent
struct NetworkChangeEvent: Identifiable {
    let id = UUID()
    let kind: Kind
    let message: String
    let date: Date = Date()

    enum Kind {
        case connected
        case disconnected
        case interfaceChanged(from: String, to: String)
    }

    /// Couleur de la bannière selon le type d'événement
    var color: Color {
        switch kind {
        case .connected:           return Color(red: 0.2, green: 0.75, blue: 0.4)
        case .disconnected:        return Color(red: 0.85, green: 0.25, blue: 0.25)
        case .interfaceChanged:    return Color(red: 0.2, green: 0.5, blue: 0.9)
        }
    }

    var icon: String {
        switch kind {
        case .connected:           return "wifi"
        case .disconnected:        return "wifi.slash"
        case .interfaceChanged:    return "arrow.triangle.2.circlepath"
        }
    }
}

// MARK: - ConnectionType
enum ConnectionType: Equatable {
    case wifi
    case ethernet
    case other
    case none
    case unknown

    var displayName: String {
        switch self {
        case .wifi:     return L10n.Monitor.wifi
        case .ethernet: return L10n.Monitor.ethernet
        case .other:    return "Autre"
        case .none:     return L10n.Monitor.noNetwork
        case .unknown:  return "—"
        }
    }

    var icon: String {
        switch self {
        case .wifi:     return "wifi"
        case .ethernet: return "cable.connector"
        case .other:    return "network"
        case .none:     return "wifi.slash"
        case .unknown:  return "questionmark"
        }
    }
}

// MARK: - NetworkMonitor
@MainActor
final class NetworkMonitor: ObservableObject {

    @Published private(set) var isConnected: Bool = true
    @Published private(set) var connectionType: ConnectionType = .unknown
    @Published var changeEvent: NetworkChangeEvent? = nil

    private let monitor = NWPathMonitor()
    private let queue   = DispatchQueue(label: "com.netguard.path-monitor", qos: .utility)

    // MARK: - Start / Stop
    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let connected = path.status == .satisfied
            let type      = Self.parseType(path)

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handlePathUpdate(connected: connected, type: type)
            }
        }
        monitor.start(queue: queue)
    }

    nonisolated func stop() {
        monitor.cancel()
    }

    func dismissEvent() {
        changeEvent = nil
    }

    // MARK: - Path update handler
    private func handlePathUpdate(connected: Bool, type: ConnectionType) {
        let wasConnected = isConnected
        let wasType      = connectionType

        isConnected    = connected
        connectionType = type

        // Ignorer la première mise à jour (valeurs initiales)
        guard wasType != .unknown else { return }

        if !wasConnected && connected {
            changeEvent = NetworkChangeEvent(
                kind: .connected,
                message: "\(L10n.Monitor.connected) (\(type.displayName))"
            )
        } else if wasConnected && !connected {
            changeEvent = NetworkChangeEvent(
                kind: .disconnected,
                message: L10n.Monitor.disconnected
            )
        } else if connected && type != wasType {
            changeEvent = NetworkChangeEvent(
                kind: .interfaceChanged(from: wasType.displayName, to: type.displayName),
                message: "\(L10n.Monitor.interfaceChanged) : \(wasType.displayName) → \(type.displayName)"
            )
        }
    }

    // MARK: - Path parsing
    private nonisolated static func parseType(_ path: NWPath) -> ConnectionType {
        guard path.status == .satisfied else { return .none }
        if path.usesInterfaceType(.wifi)          { return .wifi }
        if path.usesInterfaceType(.wiredEthernet) { return .ethernet }
        return .other
    }
}
