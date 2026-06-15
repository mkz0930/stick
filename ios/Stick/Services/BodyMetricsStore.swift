//
//  BodyMetricsStore.swift
//  用户手动输入/对话提取的身体数据
//  身高、体重、体脂率、血压、血糖等
//  持久化到 UserDefaults
//

import Foundation

@MainActor
final class BodyMetricsStore: ObservableObject {
    static let shared = BodyMetricsStore()

    // MARK: - 身体数据

    @Published var heightCm: Double?       // 身高 cm
    @Published var weightKg: Double?       // 体重 kg
    @Published var bodyFatPct: Double?    // 体脂率 %
    @Published var systolicBP: Int?         // 收缩压 mmHg
    @Published var diastolicBP: Int?       // 舒张压 mmHg
    @Published var fastingBloodSugar: Double? // 空腹血糖 mmol/L

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

    private let kHeight  = "body.height"
    private let kWeight  = "body.weight"
    private let kFat     = "body.fat"
    private let kSystolic  = "body.systolic"
    private let kDiastolic = "body.diastolic"
    private let kSugar   = "body.sugar"

    init() {
        heightCm        = UserDefaults.standard.object(forKey: kHeight) as? Double
        weightKg        = UserDefaults.standard.object(forKey: kWeight) as? Double
        bodyFatPct      = UserDefaults.standard.object(forKey: kFat) as? Double
        if let sys = UserDefaults.standard.object(forKey: kSystolic) as? Int {
            systolicBP = sys
        }
        if let dia = UserDefaults.standard.object(forKey: kDiastolic) as? Int {
            diastolicBP = dia
        }
        fastingBloodSugar = UserDefaults.standard.object(forKey: kSugar) as? Double
    }

    private func save() {
        if let h = heightCm        { UserDefaults.standard.set(h, forKey: kHeight) } else { UserDefaults.standard.removeObject(forKey: kHeight) }
        if let w = weightKg        { UserDefaults.standard.set(w, forKey: kWeight) } else { UserDefaults.standard.removeObject(forKey: kWeight) }
        if let f = bodyFatPct      { UserDefaults.standard.set(f, forKey: kFat) } else { UserDefaults.standard.removeObject(forKey: kFat) }
        if let sys = systolicBP    { UserDefaults.standard.set(sys, forKey: kSystolic) } else { UserDefaults.standard.removeObject(forKey: kSystolic) }
        if let dia = diastolicBP   { UserDefaults.standard.set(dia, forKey: kDiastolic) } else { UserDefaults.standard.removeObject(forKey: kDiastolic) }
        if let s = fastingBloodSugar { UserDefaults.standard.set(s, forKey: kSugar) } else { UserDefaults.standard.removeObject(forKey: kSugar) }
    }

    // MARK: - 正则提取

    /// 从用户文本中提取身体数据
    func extract(from text: String) {
        // 身高: 身高178 / 身高 178cm / 身高1米78
        if let m = text.range(of: "身高\\s*(\\d+\\.?\\d*)", options: .regularExpression) {
            let num = text[m].components(separatedBy: CharacterSet.decimalDigits.inverted.union(CharacterSet(charactersIn: "."))).joined()
            if let v = Double(num), v > 50, v < 300 {
                heightCm = v
            }
        }
        // 身高: 1米78 / 1m78
        if heightCm == nil {
            if let m = text.range(of: "(\\d+)米(\\d+)", options: .regularExpression) {
                let s = String(text[m])
                let parts = s.components(separatedBy: CharacterSet(charactersIn: "米"))
                if parts.count == 2,
                   let m1 = Double(parts[0]), let m2 = Double(parts[1]) {
                    heightCm = m1 * 100 + m2
                }
            }
        }

        // 体重: 体重70kg / 体重 70 / 体重70公斤
        if let m = text.range(of: "体重\\s*(\\d+\\.?\\d*)\\s*(kg|公斤|千克)?", options: .regularExpression) {
            let num = text[m].components(separatedBy: CharacterSet.decimalDigits.inverted.union(CharacterSet(charactersIn: "."))).joined()
            if let v = Double(num), v > 20, v < 500 {
                weightKg = v
            }
        }

        // 体脂率: 体脂率18% / 体脂 18%
        if let m = text.range(of: "(体脂[率]?\\s*|体脂率)\\s*(\\d+\\.?\\d*)\\s*%?", options: .regularExpression) {
            let num = text[m].components(separatedBy: CharacterSet.decimalDigits.inverted.union(CharacterSet(charactersIn: "."))).joined()
            if let v = Double(num), v > 1, v < 70 {
                bodyFatPct = v
            }
        }

        // 血压: 血压130/80 / 血压 130-80 / 血压130
        let bpPattern = "血压\\s*(\\d{2,3})[\\/\\-\\s]+(\\d{2,3})"
        if let m = text.range(of: bpPattern, options: .regularExpression) {
            let s = String(text[m])
            let nums = s.components(separatedBy: CharacterSet.decimalDigits.inverted.union(CharacterSet(charactersIn: "/")))
                .filter { $0.count >= 2 }
            if nums.count >= 2, let sys = Int(nums[0]), let dia = Int(nums[1]), sys > 60, sys < 250, dia > 40, dia < 150 {
                systolicBP = sys
                diastolicBP = dia
            }
        }

        // 血糖: 血糖5.6 / 空腹血糖5.6 / 血糖5.6mmol
        if let m = text.range(of: "(空腹)?血糖\\s*(\\d+\\.?\\d*)\\s*(mmol)?", options: .regularExpression) {
            let num = text[m].components(separatedBy: CharacterSet.decimalDigits.inverted.union(CharacterSet(charactersIn: "."))).joined()
            if let v = Double(num), v > 1, v < 35 {
                fastingBloodSugar = v
            }
        }

        save()
    }
}
