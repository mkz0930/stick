import ActivityKit
import WidgetKit
import SwiftUI

/// Live Activity 属性
struct SedentaryTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var elapsedSeconds: Int  // 已持续的秒数
        var startTime: Date     // 开始久坐的时间
    }

    var currentState: String  // sit / walk / sleep
}

/// Live Activity Widget
struct SedentaryTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SedentaryTimerAttributes.self) { context in
            // 锁屏显示
            HStack {
                VStack(alignment: .leading) {
                    Text("久坐").font(.caption).foregroundColor(.secondary)
                    Text(formatTime(context.state.elapsedSeconds))
                        .font(.system(size: 32, weight: .semibold, design: .monospaced))
                        .foregroundColor(.orange)
                }
                Spacer()
                Image(systemName: "figure.sitting")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
            }
            .padding()

        } dynamicIsland: { context in
            // 灵动岛显示（精简版）
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("久坐").foregroundColor(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(formatTime(context.state.elapsedSeconds))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.orange)
                }
            } compactLeading: {
                Image(systemName: "figure.sitting").foregroundColor(.orange)
            } compactTrailing: {
                Text(formatTime(context.state.elapsedSeconds))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.orange)
            } minimal: {
                Image(systemName: "figure.sitting").foregroundColor(.orange)
            }
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}