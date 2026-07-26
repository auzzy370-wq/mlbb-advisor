import Foundation
import UserNotifications

/// Fires local notification banners for high/critical priority coach alerts.
/// Banners appear over Mobile Legends while the user is playing.
actor NotificationService {

    private var deliveredIDs: Set<String> = []

    // MARK: - Permission

    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: - Deliver Alerts

    func deliver(_ alerts: [CoachAlert]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else { return }

        let newAlerts = alerts.filter {
            $0.priority >= .high && !deliveredIDs.contains($0.id) && $0.isActive
        }

        for alert in newAlerts.prefix(2) {
            deliveredIDs.insert(alert.id)

            let content = UNMutableNotificationContent()
            content.title = "Haya AI"
            content.body = alert.message
            content.sound = .default
            content.interruptionLevel = alert.priority == .critical ? .timeSensitive : .active
            content.userInfo = ["alertType": alert.type.rawValue]

            let request = UNNotificationRequest(
                identifier: alert.id,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            )
            try? await center.add(request)
        }

        if deliveredIDs.count > 500 { deliveredIDs.removeAll() }
    }

    // MARK: - Cleanup

    func cancelAll() async {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        deliveredIDs.removeAll()
    }
}
