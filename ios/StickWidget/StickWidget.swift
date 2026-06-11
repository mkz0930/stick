import WidgetKit
import SwiftUI

// MARK: - Widget Bundle (两个 widget 共存)
// 实际渲染在 StickWidgetView.swift / StickMediumWidgetView.swift
// widget target 和主 app 共享这两份 view 文件。

@main
struct StickWidgetBundle: WidgetBundle {
    var body: some Widget {
        StickWidget()         // 2x2  · 状态 + 火柴人 + 心率
        StickMediumWidget()   // 4x2  · 心情趋势 + 状态告警
    }
}

// MARK: - 2x2 小 widget

struct StickWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StickWidget", provider: StickProvider()) { entry in
            StickWidgetView(entry: entry)
        }
        .configurationDisplayName("Stick · 状态")
        .description("实时姿态 · 心率 · 心情")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 4x2 中 widget

struct StickMediumWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StickMediumWidget", provider: StickProvider()) { entry in
            StickMediumWidgetView(entry: entry)
        }
        .configurationDisplayName("Stick · 心情 + 告警")
        .description("心情趋势 + 状态告警（久坐提醒 / 浅睡提示）")
        .supportedFamilies([.systemMedium])
    }
}
