import WidgetKit
import SwiftUI

// MARK: - Widget Bundle (两个 widget 共存)
// 实际渲染在 StickWidgetView.swift / StickMediumWidgetView.swift
// widget target 和主 app 共享这两份 view 文件。

@main
struct StickWidgetBundle: WidgetBundle {
    var body: some Widget {
        StickWidget()                       // 2x2  · 状态 + 火柴人 + 心率
        StickMediumWidget()                 // 4x2  · 心情趋势 + 状态告警
        StickRiskAlertWidget()              // 2x2  · 久坐血小板沉积风险告警
        StickPostWorkoutWidget()            // 2x2  · 运动后冰水 5 步因果链告警
        StickSedentaryLegDMWidget()         // 2x2  · 久坐钩子 · 腿给你发了一条私信
        StickSedentaryWaistShowWidget()     // 2x2  · 久坐钩子 · 今晚腰会演哪一出
    }
}

// MARK: - 2x2 小 widget

struct StickWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StickWidget", provider: StickProvider()) { entry in
            Link(destination: URL(string: "stick://science/walking")!) {
                StickWidgetView(entry: entry)
            }
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
            Link(destination: URL(string: "stick://science/sedentarymood")!) {
                StickMediumWidgetView(entry: entry)
            }
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
            Link(destination: URL(string: "stick://science/sedentary")!) {
                StickRiskAlertWidgetView(entry: entry)
            }
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
            Link(destination: URL(string: "stick://science/icewater")!) {
                StickPostWorkoutWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("Stick 运动后")
        .description("刚运动完 · 别灌冰水 · 5 步因果链")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 2x2 久坐点击钩子 · 腿给你发了一条私信

struct StickSedentaryLegDMWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StickSedentaryLegDMWidget", provider: LegDMProvider()) { entry in
            Link(destination: URL(string: "stick://science/sedentaryhook")!) {
                StickSedentaryLegDMWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("Stick 腿私信")
        .description("久坐钩子 · 腿给你发了一条私信")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 2x2 久坐点击钩子 · 今晚腰会演哪一出

struct StickSedentaryWaistShowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StickSedentaryWaistShowWidget", provider: WaistShowProvider()) { entry in
            Link(destination: URL(string: "stick://science/sedentaryhook")!) {
                StickSedentaryWaistShowWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("Stick 腰演出")
        .description("久坐钩子 · 今晚腰会演哪一出")
        .supportedFamilies([.systemSmall])
    }
}
