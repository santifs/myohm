import Foundation
@preconcurrency import UserNotifications
import OSLog

/// Manages local notifications for automatic measurements
/// Sends notifications to iPhone and Apple Watch for pre-measurement alerts
@Observable
@MainActor
public final class LocalNotificationManager: Sendable {

    // MARK: - Properties

    public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private let notificationCenter = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "com.biomess.health", category: "Notifications")
    public let delegate = NotificationDelegate()

    // MARK: - Notification Types

    public enum NotificationType {
        case measurementAlert(secondsUntil: Int)
        case measurementStarting
        case measurementComplete
        case measurementFailed
        case sessionComplete

        var identifier: String {
            switch self {
            case .measurementAlert: return "measurement_alert"
            case .measurementStarting: return "measurement_starting"
            case .measurementComplete: return "measurement_complete"
            case .measurementFailed: return "measurement_failed"
            case .sessionComplete: return "session_complete"
            }
        }
    }

    // MARK: - Initialization

    public init() {
        Task {
            await checkAuthorizationStatus()
        }
        notificationCenter.delegate = delegate
    }

    // MARK: - Authorization

    /// Request notification permissions
    public func requestAuthorization() async throws {
        logger.info("Requesting notification authorization...")

        let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])

        await checkAuthorizationStatus()

        if granted {
            logger.info("Notification authorization granted")
        } else {
            logger.warning("Notification authorization denied")
        }
    }

    /// Check current authorization status
    public func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        logger.info("Notification authorization status: \(String(describing: self.authorizationStatus))")
    }

    // MARK: - Notification Scheduling

    /// Schedule a pre-measurement alert notification
    /// - Parameters:
    ///   - secondsBeforeMeasurement: How many seconds before measurement to alert
    ///   - sessionName: Name of the auto-measurement session
    ///   - measurementNumber: Which measurement this is in the session
    public func schedulePreMeasurementAlert(
        secondsBeforeMeasurement: Int = 5,
        sessionName: String,
        measurementNumber: Int
    ) async throws {
        guard authorizationStatus == .authorized else {
            logger.warning("Cannot schedule notification - not authorized")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "📊 Measurement Coming Up"
        content.body = "Measurement #\(measurementNumber) for '\(sessionName)' will start in \(secondsBeforeMeasurement) seconds. Please remain still."
        content.sound = .default
        content.categoryIdentifier = "MEASUREMENT_ALERT"

        // Add action buttons for Apple Watch
        content.userInfo = [
            "sessionName": sessionName,
            "measurementNumber": measurementNumber
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(secondsBeforeMeasurement), repeats: false)
        let identifier = "\(NotificationType.measurementAlert(secondsUntil: secondsBeforeMeasurement).identifier)_\(measurementNumber)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        try await notificationCenter.add(request)
        logger.info("Scheduled pre-measurement alert for measurement #\(measurementNumber)")
    }

    /// Schedule immediate measurement starting notification
    public func sendMeasurementStarting(sessionName: String, measurementNumber: Int) async throws {
        guard authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "📡 Measuring Now"
        content.body = "Measurement #\(measurementNumber) for '\(sessionName)' is now in progress. Stay still for 10 seconds."
        content.sound = .default
        content.categoryIdentifier = "MEASUREMENT_STARTING"

        let identifier = "\(NotificationType.measurementStarting.identifier)_\(measurementNumber)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        try await notificationCenter.add(request)
        logger.info("Sent measurement starting notification #\(measurementNumber)")
    }

    /// Send measurement complete notification
    public func sendMeasurementComplete(sessionName: String, measurementNumber: Int, success: Bool) async throws {
        guard authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()

        if success {
            content.title = "✅ Measurement Complete"
            content.body = "Measurement #\(measurementNumber) for '\(sessionName)' completed successfully."
            content.sound = .default
        } else {
            content.title = "⚠️ Measurement Failed"
            content.body = "Measurement #\(measurementNumber) for '\(sessionName)' failed. Will retry at next interval."
            content.sound = .default
        }

        content.categoryIdentifier = success ? "MEASUREMENT_COMPLETE" : "MEASUREMENT_FAILED"

        let type: NotificationType = success ? .measurementComplete : .measurementFailed
        let identifier = "\(type.identifier)_\(measurementNumber)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        try await notificationCenter.add(request)
        logger.info("Sent measurement complete notification #\(measurementNumber) - success: \(success)")
    }

    /// Send session complete notification
    public func sendSessionComplete(sessionName: String, totalMeasurements: Int, successRate: Double) async throws {
        guard authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "🏁 Session Complete"
        content.body = "'\(sessionName)' finished with \(totalMeasurements) measurements (\(String(format: "%.0f%%", successRate)) success rate)."
        content.sound = .default
        content.categoryIdentifier = "SESSION_COMPLETE"

        let identifier = NotificationType.sessionComplete.identifier
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        try await notificationCenter.add(request)
        logger.info("Sent session complete notification for '\(sessionName)'")
    }

    /// Send a generic notification with custom title and body
    public func sendNotification(title: String, body: String) async throws {
        guard authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let identifier = "generic_\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        try await notificationCenter.add(request)
        logger.info("Sent generic notification: \(title)")
    }

    // MARK: - Notification Management

    /// Cancel all pending notifications
    public func cancelAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        logger.info("Cancelled all pending notifications")
    }

    /// Cancel specific notification
    public func cancelNotification(withIdentifier identifier: String) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        logger.info("Cancelled notification: \(identifier)")
    }

    /// Get count of pending notifications
    public func getPendingNotificationCount() async -> Int {
        let pending = await notificationCenter.pendingNotificationRequests()
        return pending.count
    }

    // MARK: - Notification Actions

    /// Register notification categories and actions
    public func registerNotificationCategories() {
        // Pre-measurement alert actions
        let measureNowAction = UNNotificationAction(
            identifier: "MEASURE_NOW",
            title: "Measure Now",
            options: [.foreground] // Opens app to perform measurement
        )

        let skipAction = UNNotificationAction(
            identifier: "SKIP_MEASUREMENT",
            title: "Skip",
            options: []
        )

        let measurementAlertCategory = UNNotificationCategory(
            identifier: "MEASUREMENT_ALERT",
            actions: [measureNowAction, skipAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Session complete category
        let sessionCompleteCategory = UNNotificationCategory(
            identifier: "SESSION_COMPLETE",
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([
            measurementAlertCategory,
            sessionCompleteCategory
        ])

        logger.info("Registered notification categories")
    }
}
