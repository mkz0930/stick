import SwiftUI

@main
struct StickApp: App {
    @State private var widgetRiskData: WidgetRiskAlertData? = nil

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    handleWidgetURL(url)
                }
                .sheet(item: $widgetRiskData) { data in
                    WidgetRiskAlertSheet(data: data)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .presentationCornerRadius(28)
                }
        }
    }

    /// 解析 widget 点击传来的 URL，弹出对应对话框。
    /// URL 格式：stick://risk-alert?duration=60&heartRate=75
    private func handleWidgetURL(_ url: URL) {
        guard url.scheme == "stick", let host = url.host else { return }

        switch host {
        case "risk-alert":
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let query = comps?.queryItems ?? []
            let duration = query.first(where: { $0.name == "duration" })
                .flatMap { Int($0.value ?? "") } ?? 30
            let heartRate = query.first(where: { $0.name == "heartRate" })
                .flatMap { Int($0.value ?? "") } ?? 75
            // 延迟一帧让 app 先渲染主界面，丝滑弹出 UI
            DispatchQueue.main.async {
                self.widgetRiskData = WidgetRiskAlertData(
                    sitDurationMinutes: duration,
                    heartRate: heartRate
                )
            }
        default:
            break
        }
    }
}
