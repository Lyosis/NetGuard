import Foundation
import UserNotifications

// MARK: - NotificationService
/// Gère les autorisations et l'envoi des notifications macOS.
/// Seules les intrusions (nouveaux appareils) déclenchent une notification.
@MainActor
final class NotificationService {

    private let center = UNUserNotificationCenter.current()

    /// Demande la permission d'envoyer des notifications (une seule fois au démarrage).
    func requestAuthorization() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Envoie une notification groupée pour les nouveaux appareils détectés.
    /// Silencieux si la permission est refusée.
    func notifyNewDevices(_ devices: [NetworkDevice]) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.threadIdentifier = "netguard.intrusion"

        if devices.count == 1, let device = devices.first {
            content.title = "Nouvel appareil détecté"
            content.body  = "\(device.displayName) · \(device.ip)"
        } else {
            content.title = "\(devices.count) nouveaux appareils détectés"
            content.body  = devices.map(\.ip).joined(separator: ", ")
        }

        let request = UNNotificationRequest(
            identifier: "netguard.intrusion.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
