import SwiftUI
import WidgetKit

// MARK: - Widget 预览入口（Xcode #Preview Canvas）
//
// 在 Xcode 里打开此文件，⌥⌘↩ 即可看到 widget 渲染效果。
// 提供 2x2 / 4x2 / 风险告警 widget 的 3 种 size 预览。

@available(iOS 17.0, *)
struct StickWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // 坐姿（最常见）
            StickWidgetView(entry: StickEntry(
                date: .now,
                state: SharedStickState(
                    stateRaw: "坐",
                    englishName: "SITTING",
                    actionPhrase: "深度专注",
                    heartRate: 78,
                    mood: "良好",
                    durationMinutes: 47,
                    subLine: "OFFICE · DEEP WORK",
                    updatedAt: .now
                )
            ))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .previewDisplayName("2x2 · 坐")

            // 走姿
            StickWidgetView(entry: StickEntry(
                date: .now,
                state: SharedStickState(
                    stateRaw: "走",
                    englishName: "WALKING",
                    actionPhrase: "能量输出",
                    heartRate: 118,
                    mood: "良好",
                    durationMinutes: 12,
                    subLine: "OUTDOOR · COMMUTE",
                    updatedAt: .now
                )
            ))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .previewDisplayName("2x2 · 走")

            // 睡姿
            StickWidgetView(entry: StickEntry(
                date: .now,
                state: SharedStickState(
                    stateRaw: "睡",
                    englishName: "SLEEPING",
                    actionPhrase: "深度修复",
                    heartRate: 56,
                    mood: "深睡",
                    durationMinutes: 167,
                    subLine: "BEDROOM · DEEP SLEEP",
                    updatedAt: .now
                )
            ))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .previewDisplayName("2x2 · 睡")
        }
    }
}

@available(iOS 17.0, *)
struct StickMediumWidget_Previews: PreviewProvider {
    static var previews: some View {
        StickMediumWidgetView(entry: StickEntry(
            date: .now,
            state: SharedStickState(
                stateRaw: "坐",
                englishName: "SITTING",
                actionPhrase: "深度专注",
                heartRate: 78,
                mood: "良好",
                durationMinutes: 47,
                subLine: "OFFICE · DEEP WORK",
                updatedAt: .now
            )
        ))
        .previewContext(WidgetPreviewContext(family: .systemMedium))
        .previewDisplayName("4x2 · 坐")
    }
}

@available(iOS 17.0, *)
struct StickRiskAlertWidget_Previews: PreviewProvider {
    static var previews: some View {
        StickRiskAlertWidgetView(entry: StickEntry(
            date: .now,
            state: SharedStickState(
                stateRaw: "坐",
                englishName: "SITTING",
                actionPhrase: "深度专注",
                heartRate: 78,
                mood: "良好",
                durationMinutes: 47,
                subLine: "OFFICE · DEEP WORK",
                updatedAt: .now
            )
        ))
        .previewContext(WidgetPreviewContext(family: .systemSmall))
        .previewDisplayName("风险告警 · 坐")
    }
}
