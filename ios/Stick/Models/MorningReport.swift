import Foundation

struct MorningReport: Codable, Identifiable, Hashable {
    let id: UUID
    let date: String              // "yyyy-MM-dd"
    let generatedAt: Date

    // 基础数据
    let sleepMinutes: Int
    let sleepQuality: String
    let sleepMidnightWake: Int?
    let walkMinutes: Int
    let steps: Int
    let avgSpeed: Double?
    let doubleSupport: Double?
    let sedentaryMinutes: Int
    let longestSedentaryMin: Int
    let longestSedentaryRange: String?
    let wakeUpMinute: Int

    // 步态评分（原 gaitScore）
    let gaitScore: Int

    // 新增：疲惫指数（0-100，越高越疲劳）
    let fatigueIndex: Int
    // 新增：双脚支撑 Z-Score（相对14天基线的标准差）
    let doubleSupportZScore: Double?
    // 新增：双脚支撑是否异常（Z-Score > 1.5 或绝对值 > 32%）
    let isDoubleSupportAnomaly: Bool

    // LLM 生成
    let llmSummary: String
    let llmScore: Int
    let llmShortAdvice: [String]
    let llmLongAdvice: [String]
    let llmDetail: String

    // 通知状态
    let notified: Bool
}
