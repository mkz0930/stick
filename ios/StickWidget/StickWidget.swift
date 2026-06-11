import WidgetKit
import SwiftUI

// MARK: - Widget + Bundle
// 实际渲染在 StickWidgetView.swift（与主 app 共享）。这里只放 @main 配置。

@main
struct StickWidgetBundle: WidgetBundle {
    var body: some Widget {
        StickWidget()
    }
}

struct StickWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StickWidget", provider: StickProvider()) { entry in
            StickWidgetView(entry: entry)
        }
        .configurationDisplayName("Stick")
        .description("实时姿态 · 心率 · 心情")
        .supportedFamilies([.systemSmall])
    }
}
