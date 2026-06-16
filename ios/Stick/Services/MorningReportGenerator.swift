// ios/Stick/Services/MorningReportGenerator.swift
import Foundation

// MARK: - LLM 响应解析

struct LLMReportResponse: Codable {
    let summary: String
    let score: Int
    let shortAdvice: [String]
    let longAdvice: [String]
    let detail: String
}

func parseLLMResponse(_ text: String) -> LLMReportResponse? {
    guard let start = text.firstIndex(of: "{"),
          let end = text.lastIndex(of: "}"),
          start < end else { return nil }
    let jsonStr = String(text[start...end])
    return try? JSONDecoder().decode(LLMReportResponse.self, from: jsonStr.data(using: .utf8)!)
}

// MARK: - 生成器

@MainActor
final class MorningReportGenerator {
    static let shared = MorningReportGenerator()

    private let systemPrompt = """
你是一位专业的 iOS 健康数据分析师。根据用户昨日的 HealthKit 数据，生成一份晨间健康报告。

数据来源：步数、步行速度、双脚支撑百分比、睡眠分析、耳机音量暴露（夜间清醒判断）、久坐时长、饮食记录。

输出格式（严格按以下 JSON 结构返回，不要输出任何其他内容）：

{
  "summary": "综合评估段落（50-80字）",
  "score": 综合健康得分（0-100整数）,
  "shortAdvice": ["短期建议1", "短期建议2", "短期建议3"],
  "longAdvice": ["长期建议1", "长期建议2", "长期建议3"],
  "detail": "详细分析段落（150-200字），涵盖睡眠结构、久坐风险、运动充足性、步态与疲惫度、饮食记录"
}

注意事项：
- score 必须与 summary 文字内容一致
- shortAdvice 3-4 条，具体可执行
- longAdvice 3-4 条，面向健康管理长期目标
- detail 段落要引用具体数据（如具体时间、分钟数）
"""

    func generate(for date: Date) async throws -> MorningReport {
        let hk = HealthKitService.shared
        let scorer = BodyStateScorer.shared

        // 1. 收集昨日数据
        let snapshots = await hk.queryYesterdaySnapshots()
        let sleepMinutes = await hk.queryYesterdaySleepMinutes()
        let walkMinutes = await hk.queryYesterdayWalkMinutes()
        let sedentaryMinutes = await hk.queryYesterdaySedentaryMinutes()
        let steps = await hk.queryYesterdaySteps()
        let wakeUpMinute = await hk.queryYesterdayWakeUpMinute()

        // 2. 夜间清醒检测
        let nightWakes = await hk.detectNightWakePeriods()
        let nightWakeCount = nightWakes.count
        let sleepQuality: String
        switch nightWakeCount {
        case 0: sleepQuality = "连续"
        case 1: sleepQuality = "轻度中断"
        case 2: sleepQuality = "中断"
        default: sleepQuality = "碎片化"
        }

        // 3. 步态评分
        let gaitScore = scorer.computeGaitScore(
            speed: await hk.todayWalkingSpeed(),
            doubleSupport: await hk.todayWalkingDoubleSupport(),
            nightWakeCount: nightWakeCount
        )

        // 4. 心率数据分析（暂无 Apple Watch，数据均为 0/空）
        // let avgHR = await hk.yesterdayAverageHeartRate()
        // let maxHR = await hk.yesterdayMaxHeartRate()
        // let hrv = await hk.yesterdayHRV()
        // let restingHR = await hk.yesterdayRestingHeartRate()
        // let hrZoneAnalysis = await hk.analyzeYesterdayHeartRateZones()

        // 5. 恢复指数（依赖心率数据，暂无 Apple Watch）
        // let recoveryScore = scorer.computeRecoveryScore(
        //     hrv: hrv,
        //     restingHR: restingHR
        // )

        // 6. 饮食数据
        let foodStore = FoodLogStore.shared
        let breakfastEntries = foodStore.entries(for: date).filter { $0.meal == .breakfast }
        let lunchEntries = foodStore.entries(for: date).filter { $0.meal == .lunch }
        let dinnerEntries = foodStore.entries(for: date).filter { $0.meal == .dinner }

        let breakfastCalories = breakfastEntries.compactMap { $0.calories }.reduce(0, +)
        let lunchCalories = lunchEntries.compactMap { $0.calories }.reduce(0, +)
        let dinnerCalories = dinnerEntries.compactMap { $0.calories }.reduce(0, +)
        let totalCalories = breakfastCalories + lunchCalories + dinnerCalories

        var mealCount = 0
        if !breakfastEntries.isEmpty { mealCount += 1 }
        if !lunchEntries.isEmpty { mealCount += 1 }
        if !dinnerEntries.isEmpty { mealCount += 1 }

        // 7. 组装用户 prompt
        let userPrompt = """
昨日数据：
- 睡眠: \(sleepMinutes)分钟，夜间清醒 \(nightWakes.reduce(0) { $1.count })分钟，质量: \(sleepQuality)
- 起床时间: \(minuteToTimeString(wakeUpMinute))
- 步行: \(walkMinutes)分钟，步数 \(steps)步
- 久坐: \(sedentaryMinutes)分钟
- 步态评分: \(gaitScore)/100
- 饮食: 总\(totalCalories)大卡，早\(breakfastCalories)大卡 / 午\(lunchCalories)大卡 / 晚\(dinnerCalories)大卡，已记录\(mealCount)餐

请生成健康报告。
"""

        // 8. 调用 LLM
        let response = try await LLMService.sendMessage(userPrompt, context: systemPrompt)
        let llmData = parseLLMResponse(response)

        // 9. 构建报告（心率数据暂无可用来源，传 nil/0）
        // let hrZoneData: HeartRateZoneData? = hrZoneAnalysis.map {
        //     HeartRateZoneData(
        //         zone1Percent: $0.zone1Percent,
        //         zone2Percent: $0.zone2Percent,
        //         zone3Percent: $0.zone3Percent,
        //         zone4Percent: $0.zone4Percent,
        //         zone5Percent: $0.zone5Percent,
        //         predominantZone: $0.predominantZone,
        //         timeInHighIntensity: $0.timeInHighIntensity
        //     )
        // }

        return MorningReport(
            id: UUID(),
            date: Self.dateFormatter.string(from: date),
            generatedAt: Date(),
            sleepMinutes: sleepMinutes,
            sleepQuality: sleepQuality,
            sleepMidnightWake: nightWakes.first?.count,
            walkMinutes: walkMinutes,
            steps: steps,
            avgSpeed: await hk.todayWalkingSpeed(),
            doubleSupport: await hk.todayWalkingDoubleSupport(),
            sedentaryMinutes: sedentaryMinutes,
            longestSedentaryMin: await hk.todaySedentaryMinutes(),
            longestSedentaryRange: nil,
            wakeUpMinute: wakeUpMinute,
            gaitScore: gaitScore,
            fatigueIndex: 0,
            doubleSupportZScore: nil,
            isDoubleSupportAnomaly: false,
            avgHeartRate: nil,
            maxHeartRate: nil,
            heartRateZoneAnalysis: nil,
            recoveryScore: 0,
            breakfastCalories: breakfastEntries.isEmpty ? nil : breakfastCalories,
            lunchCalories: lunchEntries.isEmpty ? nil : lunchCalories,
            dinnerCalories: dinnerEntries.isEmpty ? nil : dinnerCalories,
            totalCalories: mealCount > 0 ? totalCalories : nil,
            mealCount: mealCount,
            llmSummary: llmData?.summary ?? "数据生成中...",
            llmScore: llmData?.score ?? 0,
            llmShortAdvice: llmData?.shortAdvice ?? [],
            llmLongAdvice: llmData?.longAdvice ?? [],
            llmDetail: llmData?.detail ?? "",
            notified: false
        )
    }

    private static var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    private func minuteToTimeString(_ minute: Int) -> String {
        let h = minute / 60
        let m = minute % 60
        return String(format: "%02d:%02d", h, m)
    }
}