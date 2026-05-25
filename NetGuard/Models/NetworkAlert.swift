import Foundation
import SwiftUI

// MARK: - Alert Severity
enum AlertSeverity: String, Codable, Comparable {
    case critical = "critical"
    case high     = "high"
    case medium   = "medium"
    case low      = "low"
    case info     = "info"

    var localizedName: String {
        switch self {
        case .critical: return L10n.Severity.critical
        case .high:     return L10n.Severity.high
        case .medium:   return L10n.Severity.medium
        case .low:      return L10n.Severity.low
        case .info:     return L10n.Severity.info
        }
    }

    static func < (lhs: AlertSeverity, rhs: AlertSeverity) -> Bool {
        let order: [AlertSeverity] = [.info, .low, .medium, .high, .critical]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }

    var color: Color {
        switch self {
        case .critical: return Color(red: 0.9, green: 0.1, blue: 0.1)
        case .high:     return Color(red: 0.9, green: 0.4, blue: 0.1)
        case .medium:   return Color(red: 1.0, green: 0.6, blue: 0.0)
        case .low:      return Color(red: 0.3, green: 0.7, blue: 1.0)
        case .info:     return Color.gray
        }
    }

    var icon: String {
        switch self {
        case .critical: return "exclamationmark.triangle.fill"
        case .high:     return "exclamationmark.circle.fill"
        case .medium:   return "exclamationmark.circle"
        case .low:      return "info.circle.fill"
        case .info:     return "info.circle"
        }
    }
}

// MARK: - Alert Category
enum AlertCategory: String, Codable {
    case openPort        = "Port ouvert"
    case weakEncryption  = "Chiffrement faible"
    case unknownDevice   = "Appareil inconnu"
    case vulnerability   = "Vulnérabilité"
    case configuration   = "Configuration"
    case intrusion       = "Intrusion potentielle"
}

// MARK: - Network Alert
struct NetworkAlert: Identifiable, Codable {
    let id: UUID
    let severity: AlertSeverity
    let category: AlertCategory
    let title: String
    let description: String
    let deviceIP: String
    let recommendation: String
    let timestamp: Date
    var isRead: Bool

    init(
        severity: AlertSeverity,
        category: AlertCategory,
        title: String,
        description: String,
        deviceIP: String,
        recommendation: String = "",
        isRead: Bool = false
    ) {
        self.id = UUID()
        self.severity = severity
        self.category = category
        self.title = title
        self.description = description
        self.deviceIP = deviceIP
        self.recommendation = recommendation
        self.timestamp = Date()
        self.isRead = false
    }

    var timeAgo: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 { return "À l'instant" }
        if interval < 3600 { return "Il y a \(Int(interval/60)) min" }
        if interval < 86400 { return "Il y a \(Int(interval/3600)) h" }
        return "Il y a \(Int(interval/86400)) j"
    }
}
