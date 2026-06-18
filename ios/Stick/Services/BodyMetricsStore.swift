//
//  BodyMetricsStore.swift
//  用户手动输入/对话提取的身体数据
//  身高、体重、体脂率、血压、血糖等
//  持久化到 UserDefaults
//

import Foundation

@MainActor
@Observable
final class BodyMetricsStore {
    static let shared = BodyMetricsStore()

    // MARK: - 身体数据

    var heightCm: Double?       // 身高 cm
    var weightKg: Double?       // 体重 kg
    var bodyFatPct: Double?    // 体脂率 %
    var systolicBP: Int?         // 收缩压 mmHg
    var diastolicBP: Int?       // 舒张压 mmHg
    var fastingBloodSugar: Double? // 空腹血糖 mmol/L
    var sleepHours: Double?      // 睡眠时长 小时
    var mood: String?            // 心情关键词
    var waterCups: Int?         // 饮水量 杯
    var exerciseMinutes: Int?    // 运动时长 分钟
    var stressLevel: String?     // 压力等级 高/中/低
    var symptom: String?        // 身体症状关键词
    var bloodOxygen: Int?       // 血氧百分比 90-100

    // MARK: - 计算属性

    var bmi: Double? {
        guard let h = heightCm, let w = weightKg, h > 0 else { return nil }
        return w / ((h / 100) * (h / 100))
    }

    var bmiLevel: String {
        guard let bmi = bmi else { return "暂无" }
        if bmi < 18.5  { return "偏瘦" }
        if bmi < 24    { return "正常" }
        if bmi < 28    { return "偏胖" }
        return "肥胖"
    }

    // MARK: - UserDefaults Keys

    private let kHeight   = "body.height"
    private let kWeight   = "body.weight"
    private let kFat      = "body.fat"
    private let kSystolic = "body.systolic"
    private let kDiastolic = "body.diastolic"
    private let kSugar    = "body.sugar"
    private let kSleep    = "body.sleep"
    private let kMood     = "body.mood"
    private let kWater    = "body.water"
    private let kExercise  = "body.exercise"
    private let kStress   = "body.stress"
    private let kSymptom  = "body.symptom"
    private let kBloodOxygen = "body.bloodOxygen"

    init() {
        heightCm           = UserDefaults.standard.object(forKey: kHeight) as? Double
        weightKg           = UserDefaults.standard.object(forKey: kWeight) as? Double
        bodyFatPct         = UserDefaults.standard.object(forKey: kFat) as? Double
        systolicBP         = UserDefaults.standard.object(forKey: kSystolic) as? Int
        diastolicBP        = UserDefaults.standard.object(forKey: kDiastolic) as? Int
        fastingBloodSugar  = UserDefaults.standard.object(forKey: kSugar) as? Double
        sleepHours         = UserDefaults.standard.object(forKey: kSleep) as? Double
        mood               = UserDefaults.standard.string(forKey: kMood)
        waterCups         = UserDefaults.standard.object(forKey: kWater) as? Int
        exerciseMinutes    = UserDefaults.standard.object(forKey: kExercise) as? Int
        stressLevel        = UserDefaults.standard.string(forKey: kStress)
        symptom           = UserDefaults.standard.string(forKey: kSymptom)
        bloodOxygen       = UserDefaults.standard.object(forKey: kBloodOxygen) as? Int
    }

    private func save() {
        if let h = heightCm           { UserDefaults.standard.set(h, forKey: kHeight) } else { UserDefaults.standard.removeObject(forKey: kHeight) }
        if let w = weightKg            { UserDefaults.standard.set(w, forKey: kWeight) } else { UserDefaults.standard.removeObject(forKey: kWeight) }
        if let f = bodyFatPct          { UserDefaults.standard.set(f, forKey: kFat) } else { UserDefaults.standard.removeObject(forKey: kFat) }
        if let sys = systolicBP        { UserDefaults.standard.set(sys, forKey: kSystolic) } else { UserDefaults.standard.removeObject(forKey: kSystolic) }
        if let dia = diastolicBP      { UserDefaults.standard.set(dia, forKey: kDiastolic) } else { UserDefaults.standard.removeObject(forKey: kDiastolic) }
        if let s = fastingBloodSugar  { UserDefaults.standard.set(s, forKey: kSugar) } else { UserDefaults.standard.removeObject(forKey: kSugar) }
        if let s = sleepHours         { UserDefaults.standard.set(s, forKey: kSleep) } else { UserDefaults.standard.removeObject(forKey: kSleep) }
        if let m = mood               { UserDefaults.standard.set(m, forKey: kMood) } else { UserDefaults.standard.removeObject(forKey: kMood) }
        if let c = waterCups         { UserDefaults.standard.set(c, forKey: kWater) } else { UserDefaults.standard.removeObject(forKey: kWater) }
        if let e = exerciseMinutes    { UserDefaults.standard.set(e, forKey: kExercise) } else { UserDefaults.standard.removeObject(forKey: kExercise) }
        if let s = stressLevel        { UserDefaults.standard.set(s, forKey: kStress) } else { UserDefaults.standard.removeObject(forKey: kStress) }
        if let s = symptom            { UserDefaults.standard.set(s, forKey: kSymptom) } else { UserDefaults.standard.removeObject(forKey: kSymptom) }
        if let bo = bloodOxygen       { UserDefaults.standard.set(bo, forKey: kBloodOxygen) } else { UserDefaults.standard.removeObject(forKey: kBloodOxygen) }
    }

    // MARK: - 正则提取

    /// 从用户文本中提取身体数据（自然语言输入）
    func extract(from text: String) {
        let t = text

        // MARK: 身高
        if let m = t.range(of: "身高\\s*(\\d+\\.?\\d*)", options: .regularExpression) {
            let num = String(t[m]).components(separatedBy: CharacterSet.decimalDigits.inverted.union(CharacterSet(charactersIn: "."))).joined()
            if let v = Double(num), v > 50, v < 300 { heightCm = v }
        }
        if heightCm == nil, let m = t.range(of: "(\\d+)米(\\d+)", options: .regularExpression) {
            let s = String(t[m])
            let parts = s.components(separatedBy: CharacterSet(charactersIn: "米"))
            if parts.count == 2, let m1 = Double(parts[0]), let m2 = Double(parts[1]) { heightCm = m1 * 100 + m2 }
        }

        // MARK: 体重
        if let m = t.range(of: "体重\\s*(\\d+\\.?\\d*)\\s*(kg|公斤|千克)?", options: .regularExpression) {
            let num = String(t[m]).components(separatedBy: CharacterSet.decimalDigits.inverted.union(CharacterSet(charactersIn: "."))).joined()
            if let v = Double(num), v > 20, v < 500 { weightKg = v }
        }

        // MARK: 体脂率
        if let m = t.range(of: "(体脂[率]?\\s*|体脂率)\\s*(\\d+\\.?\\d*)\\s*%?", options: .regularExpression) {
            let num = String(t[m]).components(separatedBy: CharacterSet.decimalDigits.inverted.union(CharacterSet(charactersIn: "."))).joined()
            if let v = Double(num), v > 1, v < 70 { bodyFatPct = v }
        }

        // MARK: 血压
        if let m = t.range(of: "血压\\s*(\\d{2,3})[\\/\\-\\s]+(\\d{2,3})", options: .regularExpression) {
            let s = String(t[m])
            let nums = s.components(separatedBy: CharacterSet.decimalDigits.inverted.union(CharacterSet(charactersIn: "/")))
                .filter { $0.count >= 2 }
            if nums.count >= 2, let sys = Int(nums[0]), let dia = Int(nums[1]), sys > 60, sys < 250, dia > 40, dia < 150 {
                systolicBP = sys; diastolicBP = dia
            }
        }

        // MARK: 血糖
        if let m = t.range(of: "(空腹)?血糖\\s*(\\d+\\.?\\d*)\\s*(mmol)?", options: .regularExpression) {
            let num = String(t[m]).components(separatedBy: CharacterSet.decimalDigits.inverted.union(CharacterSet(charactersIn: "."))).joined()
            if let v = Double(num), v > 1, v < 35 { fastingBloodSugar = v }
        }

        // MARK: 睡眠时长
        if let m = t.range(of: "睡了?\\s*(\\d+\\.?\\d*)\\s*小时", options: .regularExpression) {
            let num = String(t[m]).components(separatedBy: CharacterSet.decimalDigits.inverted.union(CharacterSet(charactersIn: "."))).joined()
            if let v = Double(num), v > 0, v <= 24 { sleepHours = v }
        }
        if sleepHours == nil, let m = t.range(of: "睡眠\\s*(\\d+\\.?\\d*)\\s*小时", options: .regularExpression) {
            let num = String(t[m]).components(separatedBy: CharacterSet.decimalDigits.inverted.union(CharacterSet(charactersIn: "."))).joined()
            if let v = Double(num), v > 0, v <= 24 { sleepHours = v }
        }
        if sleepHours == nil, t.contains("失眠") || t.contains("睡眠不好") || t.contains("睡眠差") { sleepHours = 0 }

        // MARK: 饮水量
        if let m = t.range(of: "喝了?\\s*(\\d+)\\s*杯", options: .regularExpression) {
            let num = String(t[m]).components(separatedBy: CharacterSet.decimalDigits).joined()
            if let v = Int(num), v > 0, v <= 20 { waterCups = v }
        }
        if waterCups == nil, t.contains("喝水少") || t.contains("没怎么喝水") { waterCups = 0 }

        // MARK: 运动时长
        if let m = t.range(of: "运动\\s*(\\d+)\\s*分钟", options: .regularExpression) {
            let num = String(t[m]).components(separatedBy: CharacterSet.decimalDigits).joined()
            if let v = Int(num), v > 0, v <= 600 { exerciseMinutes = v }
        }
        if let m = t.range(of: "跑步\\s*(\\d+)\\s*分钟", options: .regularExpression) {
            let num = String(t[m]).components(separatedBy: CharacterSet.decimalDigits).joined()
            if let v = Int(num), v > 0, v <= 600 { exerciseMinutes = (exerciseMinutes ?? 0) + v }
        }
        if let m = t.range(of: "走了?\\s*(\\d+)\\s*分钟", options: .regularExpression) {
            let num = String(t[m]).components(separatedBy: CharacterSet.decimalDigits).joined()
            if let v = Int(num), v > 0, v <= 600 { exerciseMinutes = (exerciseMinutes ?? 0) + v }
        }

        // MARK: 心情
        if t.contains("心情不好") || t.contains("情绪低落") || t.contains("不开心") || t.contains("郁闷") { mood = "低落" }
        else if t.contains("开心") || t.contains("心情好") || t.contains("高兴") || t.contains("愉快") { mood = "愉悦" }
        else if t.contains("焦虑") || t.contains("烦躁") { mood = "焦虑" }
        else if t.contains("抑郁") || t.contains("沮丧") { mood = "抑郁" }
        else if t.contains("平静") || t.contains("放松") { mood = "平静" }

        // MARK: 压力
        if t.contains("压力大") || t.contains("压力很大") || t.contains("压力山大") { stressLevel = "高" }
        else if t.contains("压力小") || t.contains("压力一般") { stressLevel = "中" }
        else if t.contains("没压力") || t.contains("轻松") { stressLevel = "低" }

        // MARK: 身体症状
        let symptomKeywords = ["头痛", "头晕", "咳嗽", "感冒", "发烧", "胃疼", "胃痛", "眼睛干", "眼干", "腰疼", "腰痛", "背痛", "肩酸", "脖子酸", "胸闷", "心悸", "恶心", "腹泻", "便秘", "疲劳", "乏力", "失眠", "焦虑", "抑郁"]
        for kw in symptomKeywords {
            if t.contains(kw) { symptom = kw; break }
        }

        // MARK: 血氧
        if let m = t.range(of: "血氧\\s*(\\d{2})\\s*%?", options: .regularExpression) {
            let num = String(t[m]).components(separatedBy: CharacterSet.decimalDigits.inverted.union(CharacterSet(charactersIn: "%"))).joined()
            if let v = Int(num), v >= 90, v <= 100 { bloodOxygen = v }
        }

        save()
    }
}
