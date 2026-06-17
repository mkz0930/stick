import ActivityKit
import Foundation

/// Live Activity 属性定义。主 app 和 Widget 两个 target 共享。
/// iOS 16.1+ ActivityKit 需要两个 target 的属性定义完全一致。
struct SedentaryTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// 已持续的秒数
        var elapsedSeconds: Int
        /// 开始久坐的时间
        var startTime: Date
    }

    /// 当前状态（sit / walk / stand / sleep）
    var currentState: String
}