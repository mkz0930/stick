//
//  DataRecordView.swift
//  数据记录 — 按设计稿重写
//

import SwiftUI
import Combine

@MainActor
final class DataRecordViewModel: ObservableObject {
    @Published var today: [HealthSnapshot] = []
    @Published var insights: [HealthInsight] = []
    @Published private(set) var userProfile: String = ""

    private var cancellables = Set<AnyCancellable>()

    init() {
        userProfile = UserProfileStore.shared.profile
        refresh()
        HealthStore.shared.$today
            .receive(on: RunLoop.main)
            .sink { [weak self] snaps in
                guard let self else { return }
                self.today = snaps
                self.insights = HealthAnalyzer.shared.analyze(snapshots: snaps)
            }
            .store(in: &cancellables)
    }

    func refresh() {
        userProfile = UserProfileStore.shared.profile
        HealthStore.shared.refreshToday()
        let snaps = HealthStore.shared.today
        today = snaps
        insights = HealthAnalyzer.shared.analyze(snapshots: snaps)
    }

    var avgHeartRate: Int? {
        let hrs = today.compactMap { $0.heartRate }
        guard !hrs.isEmpty else { return nil }
        return Int((hrs.reduce(0, +) / Double(hrs.count)).rounded())
    }

    var totalSteps: Int {
        today.last?.stepCount ?? 0
    }

    var totalEnergy: Int {
        Int(today.compactMap { $0.activeEnergy }.reduce(0, +).rounded())
    }

    var sitMinutes: Int {
        today.filter { $0.bodyState == "sit" }.count
    }

    var sleepMinutes: Int {
        let sleeps = today.filter { $0.bodyState == "sleep" }
        guard let first = sleeps.first?.timestamp, let last = sleeps.last?.timestamp else { return 0 }
        return Int(last.timeIntervalSince(first) / 60)
    }
}

struct DataRecordView: View {
    var onClose: () -> Void

    @StateObject private var vm = DataRecordViewModel()
    /// LLM 生成的今日洞察（一句）
    @State private var insight: String = ""
    @State private var isLoadingInsight: Bool = false

    /// 血压显示值：收缩压/舒张压 或 --
    private var bpValue: String {
        guard let sys = BodyMetricsStore.shared.systolicBP,
              let dia = BodyMetricsStore.shared.diastolicBP else { return "--" }
        return "\(sys)/\(dia)"
    }

    /// 血糖显示值：或 --
    private var sugarValue: String {
        guard let v = BodyMetricsStore.shared.fastingBloodSugar else { return "--" }
        return String(format: "%.1f", v)
    }

    /// 今日饮食记录条目
    private var dietEntries: [FoodEntry] {
        FoodLogStore.shared.todayEntries
    }

    private func mealLabel(_ meal: MealType) -> String {
        switch meal {
        case .breakfast: return "早餐"
        case .lunch: return "午餐"
        case .dinner: return "晚餐"
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                ScrollView {
                    VStack(spacing: 12) {
                        todayInsight
                        dashboardSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            vm.refresh()
            // 每次打开都调 LLM 生成一句洞察
            Task { await generateInsight() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Text("数据记录")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.navy)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.navy)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.card).overlay(Circle().stroke(Theme.border, lineWidth: 1)))
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - 今日洞察

    private var todayInsight: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("今日洞察")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.navy)
                Spacer()
                Text(todayDateString())
                    .font(.system(size: 13))
                    .foregroundColor(Theme.slate)
            }
            if !vm.userProfile.isEmpty {
                Text(vm.userProfile)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.navy)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.navy.opacity(0.06)))
            }
            // LLM 生成的洞察: loading / 文本
            if isLoadingInsight {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("正在生成洞察…")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.slate)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if !insight.isEmpty {
                Text(insight)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.slate)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("今日数据不足，洞察稍后生成")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.mist)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1)))
    }

    /// 每次打开 DataRecordView 时调 LLM，基于今日健康数据+用户画像生成一句 20 字以内的洞察
    private func generateInsight() async {
        isLoadingInsight = true
        defer { isLoadingInsight = false }
        let context = buildInsightContext()
        let message = "你是用户的健康小助手。基于今日健康数据，输出一句话中文总结，不超过 20 个字。专注最值得提醒的一点，直接给句子，不要标题、不要 emoji、不要说教。"
        do {
            let raw = try await LLMService.sendMessage(message, context: context)
            let cleaned = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\"", with: "")
            // 简单截断: 60 字符 ≈ 30 中文字 + 标点
            insight = cleaned.count > 40 ? String(cleaned.prefix(40)) : cleaned
        } catch {
            insight = ""
            print("[DataRecordView] generateInsight failed: \(error)")
        }
    }

    /// 把 vm.today 折算成 7 行摘要给 LLM
    private func buildInsightContext() -> String {
        let snaps = vm.today
        var sit = 0, walk = 0, sleep = 0, stand = 0
        var steps = snaps.last?.stepCount ?? 0
        var hrSum = 0.0, hrCount = 0
        var energy = 0.0
        for s in snaps {
            switch s.bodyState {
            case "sit":   sit += 1
            case "walk":  walk += 1
            case "sleep": sleep += 1
            case "stand": stand += 1
            default:      break
            }
            if let hr = s.heartRate   { hrSum += hr; hrCount += 1 }
            if let e  = s.activeEnergy { energy += e }
        }
        let avgHR = hrCount > 0 ? Int(hrSum / Double(hrCount)) : 0
        let profile = UserProfileStore.shared.profile
        var ctx = """
        今日健康数据：
        - 步数: \(steps) 步
        - 久坐: \(sit) 分钟
        - 行走: \(walk) 分钟
        - 睡眠: \(sleep) 分钟
        - 站立: \(stand) 分钟
        - 平均心率: \(avgHR) bpm
        - 活动能量: \(Int(energy)) 千卡
        """
        if !profile.isEmpty {
            ctx += "\n\n用户画像：\(profile)"
        }
        return ctx
    }

    private func todayDateString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEE MM/dd"
        return f.string(from: Date())
    }

    // MARK: - 健康仪表盘

    private var dashboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("健康仪表盘")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.navy)
                Spacer()
                HStack(spacing: 4) {
                    Text("更新于 22:29")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.slate)
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.slate)
                }
            }

            VStack(spacing: 10) {
                // 第一行: 睡眠 + 步数
                HStack(spacing: 10) {
                    DashboardCard(
                        icon: "moon.zzz.fill",
                        iconColor: Theme.dashSleep,
                        title: "睡眠",
                        sub: "暂无数据",
                        value: "--"
                    )
                    DashboardCard(
                        icon: "figure.walk",
                        iconColor: Theme.dashSteps,
                        title: "步数",
                        sub: "06-13 22:29",
                        value: "\(vm.totalSteps)",
                        valueUnit: "/10000"
                    )
                }

                // 第二行: 运动记录 + 饮食记录
                HStack(spacing: 10) {
                    DashboardCard(
                        icon: "figure.run",
                        iconColor: Theme.dashSteps,
                        title: "运动记录",
                        sub: "暂无数据",
                        value: "--",
                        valueUnit: "分钟"
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        // 顶行：图标 + 标题
                        HStack(spacing: 6) {
                            Image(systemName: "fork.knife")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.dashDiet)
                            Text("饮食记录")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Theme.navy)
                        }
                        Text("今日累计")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.mist)
                        Spacer(minLength: 0)
                        // 进度条
                        DietProgressBar(current: FoodLogStore.shared.todayTotalCalories, goal: 1800)
                        // 各餐明细
                        if !dietEntries.isEmpty {
                            ForEach(MealType.allCases, id: \.self) { meal in
                                let entries = dietEntries.filter { $0.meal == meal }
                                if !entries.isEmpty {
                                    let mealCal = entries.compactMap { $0.calories }.reduce(0, +)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(mealLabel(meal))  \(mealCal > 0 ? "\(mealCal) kcal" : "-- kcal")")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(Theme.navy)
                                        ForEach(entries) { entry in
                                            Text("· \(entry.foodName)")
                                                .font(.system(size: 11))
                                                .foregroundColor(Theme.slate)
                                        }
                                    }
                                }
                            }
                        } else {
                            Text("暂无数据")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.mist)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1)))
                }

                // 久坐记录 (单卡)
                DashboardCard(
                    icon: "figure.seated.side",
                    iconColor: Color(red: 0.92, green: 0.55, blue: 0.20),
                    title: "久坐记录",
                    sub: "今日累计",
                    value: "\(vm.sitMinutes)",
                    valueUnit: "分钟"
                )

                // 心情记录 (单卡)
                DashboardCard(
                    icon: "face.smiling",
                    iconColor: Color(red: 0.55, green: 0.75, blue: 0.50),
                    title: "心情记录",
                    sub: "来自对话分析",
                    value: BodyMetricsStore.shared.mood ?? "--",
                    valueUnit: ""
                )

                // 身材管理 (通栏)
                BodyCard(
                    icon: "figure.arms.open",
                    iconColor: Theme.dashBody,
                    title: "身材管理",
                    sub: "暂无数据",
                    heightCm: BodyMetricsStore.shared.heightCm,
                    weightKg: BodyMetricsStore.shared.weightKg,
                    bodyFatPct: BodyMetricsStore.shared.bodyFatPct
                )

                // 第三 + 第四行: 2x2 健康生命体征 (血压/血糖 + 血氧/心率)
                VStack(spacing: 10) {
                    // 顶行: 血压 + 血糖
                    HStack(spacing: 10) {
                        DashboardCard(
                            icon: "drop.fill",
                            iconColor: Theme.dashBlood,
                            title: "血压",
                            sub: "来自对话分析",
                            value: bpValue,
                            valueUnit: "mmHg"
                        )
                        DashboardCard(
                            icon: "drop.fill",
                            iconColor: Theme.dashBlood,
                            title: "血糖",
                            sub: "空腹",
                            value: sugarValue,
                            valueUnit: "mmol/L"
                        )
                    }
                    // 底行: 血氧 + 心率
                    HStack(spacing: 10) {
                        DashboardCard(
                            icon: "lungs.fill",
                            iconColor: Theme.dashBlood,
                            title: "血氧",
                            sub: "暂无数据",
                            value: "--",
                            valueUnit: "%"
                        )
                        DashboardCard(
                            icon: "heart.fill",
                            iconColor: Color(red: 0.86, green: 0.21, blue: 0.27),
                            title: "心率",
                            sub: "暂无数据",
                            value: "--",
                            valueUnit: "bpm"
                        )
                    }
                }
            }
        }
    }
}

// MARK: - DashboardCard

private struct DashboardCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let sub: String
    let value: String
    var valueUnit: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.navy)
            }
            Text(sub)
                .font(.system(size: 11))
                .foregroundColor(Theme.mist)
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.navy)
                if !valueUnit.isEmpty {
                    Text(valueUnit)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.slate)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1)))
    }
}

// MARK: - DietProgressBar

private struct DietProgressBar: View {
    let current: Int
    let goal: Int  // 固定 1800

    private var progress: Double { min(Double(current) / Double(goal), 1.0) }
    private var isOver: Bool { current > goal }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.border)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isOver ? Color.red : Theme.dashDiet)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 6)
            Text("\(current) / \(goal) kcal")
                .font(.system(size: 11))
                .foregroundColor(isOver ? .red : Theme.slate)
        }
    }
}

// MARK: - BodyCard (通栏三栏)

private struct BodyCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let sub: String
    let heightCm: Double?
    let weightKg: Double?
    let bodyFatPct: Double?

    private var bmi: Double? {
        guard let h = heightCm, let w = weightKg, h > 0 else { return nil }
        return w / ((h / 100) * (h / 100))
    }

    private func fmt(_ value: Double?, _ unit: String) -> String {
        guard let v = value else { return "--" }
        return String(format: "%.1f", v) + unit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.navy)
            }
            Text(sub)
                .font(.system(size: 11))
                .foregroundColor(Theme.mist)

            HStack(alignment: .top, spacing: 0) {
                bodyColumn(fmt(heightCm, ""), "身高/cm")
                Spacer()
                bodyColumn(fmt(weightKg, ""), "体重/KG")
                Spacer()
                bodyColumn(bmi.map { String(format: "%.1f", $0) } ?? "--", "BMI")
                Spacer()
                bodyColumn(fmt(bodyFatPct, ""), "体脂率/%")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1)))
    }

    private func bodyColumn(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(Theme.navy)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Theme.slate)
        }
    }
}

#Preview {
    DataRecordView(onClose: {})
}
