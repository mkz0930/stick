// ios/Stick/Services/NotificationService.swift
import UserNotifications

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch { return false }
    }

    func scheduleMorningReport(_ report: MorningReport) async {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "📊 昨日健康报告已生成"
        content.body = "查看今日身体状态分析 →"
        content.sound = .default
        content.categoryIdentifier = "MORNING_REPORT"
        content.userInfo = ["reportDate": report.date]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "morning-report-\(report.date)",
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }
}