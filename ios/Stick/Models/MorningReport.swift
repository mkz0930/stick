import Foundation

struct HeartRateZoneData: Codable, Hashable {
    let zone1Percent: Double
    let zone2Percent: Double
    let zone3Percent: Double
    let zone4Percent: Double
    let zone5Percent: Double
    let predominantZone: Int
    let timeInHighIntensity: Double  // zone4+5 combined
}

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

    // 心率数据
    let avgHeartRate: Int?       // 昨日平均心率
    let maxHeartRate: Int?       // 昨日最高心率
    let heartRateZoneAnalysis: HeartRateZoneData? // 心率区间分布
    let recoveryScore: Int       // 恢复指数 0-100

    // 饮食数据
    let breakfastCalories: Int?
    let lunchCalories: Int?
    let dinnerCalories: Int?
    let totalCalories: Int?
    let mealCount: Int           // 已记录的餐次数量 (0-3)

    // LLM 生成
    let llmSummary: String
    let llmScore: Int
    let llmShortAdvice: [String]
    let llmLongAdvice: [String]
    let llmDetail: String

    // 通知状态
    let notified: Bool

    init(
        id: UUID,
        date: String,
        generatedAt: Date,
        sleepMinutes: Int,
        sleepQuality: String,
        sleepMidnightWake: Int?,
        walkMinutes: Int,
        steps: Int,
        avgSpeed: Double?,
        doubleSupport: Double?,
        sedentaryMinutes: Int,
        longestSedentaryMin: Int,
        longestSedentaryRange: String?,
        wakeUpMinute: Int,
        gaitScore: Int,
        fatigueIndex: Int,
        doubleSupportZScore: Double?,
        isDoubleSupportAnomaly: Bool,
        avgHeartRate: Int?,
        maxHeartRate: Int?,
        heartRateZoneAnalysis: HeartRateZoneData?,
        recoveryScore: Int,
        breakfastCalories: Int?,
        lunchCalories: Int?,
        dinnerCalories: Int?,
        totalCalories: Int?,
        mealCount: Int,
        llmSummary: String,
        llmScore: Int,
        llmShortAdvice: [String],
        llmLongAdvice: [String],
        llmDetail: String,
        notified: Bool
    ) {
        self.id = id
        self.date = date
        self.generatedAt = generatedAt
        self.sleepMinutes = sleepMinutes
        self.sleepQuality = sleepQuality
        self.sleepMidnightWake = sleepMidnightWake
        self.walkMinutes = walkMinutes
        self.steps = steps
        self.avgSpeed = avgSpeed
        self.doubleSupport = doubleSupport
        self.sedentaryMinutes = sedentaryMinutes
        self.longestSedentaryMin = longestSedentaryMin
        self.longestSedentaryRange = longestSedentaryRange
        self.wakeUpMinute = wakeUpMinute
        self.gaitScore = gaitScore
        self.fatigueIndex = fatigueIndex
        self.doubleSupportZScore = doubleSupportZScore
        self.isDoubleSupportAnomaly = isDoubleSupportAnomaly
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.heartRateZoneAnalysis = heartRateZoneAnalysis
        self.recoveryScore = recoveryScore
        self.breakfastCalories = breakfastCalories
        self.lunchCalories = lunchCalories
        self.dinnerCalories = dinnerCalories
        self.totalCalories = totalCalories
        self.mealCount = mealCount
        self.llmSummary = llmSummary
        self.llmScore = llmScore
        self.llmShortAdvice = llmShortAdvice
        self.llmLongAdvice = llmLongAdvice
        self.llmDetail = llmDetail
        self.notified = notified
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(String.self, forKey: .date)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        sleepMinutes = try container.decode(Int.self, forKey: .sleepMinutes)
        sleepQuality = try container.decode(String.self, forKey: .sleepQuality)
        sleepMidnightWake = try container.decodeIfPresent(Int.self, forKey: .sleepMidnightWake)
        walkMinutes = try container.decode(Int.self, forKey: .walkMinutes)
        steps = try container.decode(Int.self, forKey: .steps)
        avgSpeed = try container.decodeIfPresent(Double.self, forKey: .avgSpeed)
        doubleSupport = try container.decodeIfPresent(Double.self, forKey: .doubleSupport)
        sedentaryMinutes = try container.decode(Int.self, forKey: .sedentaryMinutes)
        longestSedentaryMin = try container.decode(Int.self, forKey: .longestSedentaryMin)
        longestSedentaryRange = try container.decodeIfPresent(String.self, forKey: .longestSedentaryRange)
        wakeUpMinute = try container.decode(Int.self, forKey: .wakeUpMinute)
        gaitScore = try container.decode(Int.self, forKey: .gaitScore)
        fatigueIndex = try container.decode(Int.self, forKey: .fatigueIndex)
        doubleSupportZScore = try container.decodeIfPresent(Double.self, forKey: .doubleSupportZScore)
        isDoubleSupportAnomaly = try container.decode(Bool.self, forKey: .isDoubleSupportAnomaly)
        avgHeartRate = try container.decodeIfPresent(Int.self, forKey: .avgHeartRate)
        maxHeartRate = try container.decodeIfPresent(Int.self, forKey: .maxHeartRate)
        heartRateZoneAnalysis = try container.decodeIfPresent(HeartRateZoneData.self, forKey: .heartRateZoneAnalysis)
        recoveryScore = try container.decode(Int.self, forKey: .recoveryScore)
        breakfastCalories = try container.decodeIfPresent(Int.self, forKey: .breakfastCalories)
        lunchCalories = try container.decodeIfPresent(Int.self, forKey: .lunchCalories)
        dinnerCalories = try container.decodeIfPresent(Int.self, forKey: .dinnerCalories)
        totalCalories = try container.decodeIfPresent(Int.self, forKey: .totalCalories)
        mealCount = try container.decodeIfPresent(Int.self, forKey: .mealCount) ?? 0
        llmSummary = try container.decode(String.self, forKey: .llmSummary)
        llmScore = try container.decode(Int.self, forKey: .llmScore)
        llmShortAdvice = try container.decode([String].self, forKey: .llmShortAdvice)
        llmLongAdvice = try container.decode([String].self, forKey: .llmLongAdvice)
        llmDetail = try container.decode(String.self, forKey: .llmDetail)
        notified = try container.decode(Bool.self, forKey: .notified)
    }
}
