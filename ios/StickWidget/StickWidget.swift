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

