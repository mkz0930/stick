import Foundation

struct MorningReport: Codable, Identifiable {
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
    let gaitScore: Int

    // LLM 生成
    let llmSummary: String
    let llmScore: Int
    let llmShortAdvice: [String]
    let llmLongAdvice: [String]
    let llmDetail: String

    // 通知状态
    let notified: Bool
}
