import WidgetKit
import SwiftUI

// MARK: - Widget Bundle (六个 widget 共存)
// 实际渲染在 StickWidgetView.swift / StickMediumWidgetView.swift / ... / 各 widget view
// widget target 和主 app 共享这些 view 文件。
//
// ⚠️ 不再使用 `Link(destination: stick://...)`：iOS 对自定义 URL scheme 每次都弹
// 「在 'Stick' 中打开?」系统弹窗，体验割裂。所有 widget 改为不可点（点 widget 只进
// widget 库，不进 app）。如需重新打开 app，从主屏点 Stick 图标即可。

@main
struct StickWidgetBundle: WidgetBundle {
    var body: some Widget {
        StickRiskAlertWidget()              // 2x2  · 久坐血小板沉积风险告警
    }
}

// MARK: - 2x2 小 widget

struct StickWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StickWidget", provider: StickProvider()) { entry in
            StickWidgetView(entry: entry)
        }
        .configurationDisplayName("Stick")
        .description("2x2 · 状态 + 心率")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 4x2 中 widget

struct StickMediumWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StickMediumWidget", provider: StickProvider()) { entry in
            StickMediumWidgetView(entry: entry)
        }
        .configurationDisplayName("Stick")
        .description("4x2 · 心情 + 告警")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - 2x2 风险告警 widget（久坐血小板沉积）

struct StickRiskAlertWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StickRiskAlertWidget", provider: RiskAlertProvider()) { entry in
            StickRiskAlertWidgetView(entry: entry)
        }
        .configurationDisplayName("Stick 风险")
        .description("久坐血小板沉积风险 · 提示动动")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 2x2 运动后冰水告警 widget（5 步因果链）

struct StickPostWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StickPostWorkoutWidget", provider: PostWorkoutProvider()) { entry in
            StickPostWorkoutWidgetView(entry: entry)
        }
        .configurationDisplayName("Stick 运动后")
        .description("刚运动完 · 别灌冰水 · 5 步因果链")
        .supportedFamilies([.systemSmall])
    }
}
