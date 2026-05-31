import Foundation
import SwiftData

// MARK: - ScanSnapshot
/// Résumé persisté d'un scan (métriques uniquement — pas de copie des appareils).
/// Limite : 30 entrées, nettoyage géré par AppState.saveSnapshot().
@Model
final class ScanSnapshot {
    var id: UUID
    var date: Date
    var durationSeconds: Double
    var deviceCount: Int
    var alertCount: Int
    var newDeviceCount: Int

    init(
        date: Date,
        durationSeconds: Double,
        deviceCount: Int,
        alertCount: Int,
        newDeviceCount: Int
    ) {
        self.id              = UUID()
        self.date            = date
        self.durationSeconds = durationSeconds
        self.deviceCount     = deviceCount
        self.alertCount      = alertCount
        self.newDeviceCount  = newDeviceCount
    }
}
