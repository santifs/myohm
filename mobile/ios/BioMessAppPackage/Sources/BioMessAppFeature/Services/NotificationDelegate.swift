import Foundation
import UserNotifications
import OSLog

/// Handles notification responses and actions
public final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private let logger = Logger(subsystem: "com.biomess.health", category: "NotificationDelegate")

    /// Called when user taps on notification or action button
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier

        logger.info("Received notification response: \(actionIdentifier)")

        switch actionIdentifier {
        case "MEASURE_NOW":
            // User tapped "Measure Now" button
            logger.info("User requested measurement from notification")
            handleMeasureNow(userInfo: userInfo)

        case "SKIP_MEASUREMENT":
            // User tapped "Skip" button
            logger.info("User skipped measurement")
            // Don't need to do anything, measurement will be skipped automatically

        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification itself
            logger.info("User tapped notification body")
            handleMeasureNow(userInfo: userInfo)

        default:
            logger.info("Unknown action: \(actionIdentifier)")
        }

        completionHandler()
    }

    /// Called when notification arrives while app is in foreground
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        logger.info("Notification arrived while app in foreground")
        completionHandler([.banner, .sound])
    }

    private func handleMeasureNow(userInfo: [AnyHashable: Any]) {
        // Post notification that will be handled by AutoMeasurementService
        NotificationCenter.default.post(
            name: .performMeasurementFromNotification,
            object: nil,
            userInfo: userInfo
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let performMeasurementFromNotification = Notification.Name("performMeasurementFromNotification")
}
