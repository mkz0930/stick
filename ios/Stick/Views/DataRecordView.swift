//
//  DataRecordView.swift
//  数据记录 — 按设计稿重写
//

import SwiftUI

/// HealthKit 实时数据
struct HKLiveData: Equatable {
    var steps: Int = 0
    var energy: Int = 0
    var flights: Int = 0
    var distance: Double = 0
    var heartRate: Int?
    var sleepHours: Double?           // 睡眠时长 小时（来自 Health App 手动记录）
    // 新增 mobility
    var walkingSpeed: Double?          // 步速 m/s
    var walkingDoubleSupport: Double?  // 双脚支撑时间 %
    var headphoneExposure: Double?    // 耳机音量 dB
    // 今日久坐分钟数（直接从 HealthKit 每分钟步数样本统计）
    var sedentaryMinutes: Int = 0
}

@MainActor
@Observable
final class DataRecordViewModel {
    var today: [HealthSnapshot] = []
    var insights: [HealthInsight] = []
    private(set) var userProfile: String = ""
    var hkData: HKLiveData?

    private var observationTask: Task<Void, Never>?

    func loadHKData() async {
        var data = HKLiveData()
        let service = HealthKitService.shared

        if let steps = await service.todaySteps() {
            data.steps = steps
        }
        if let energy = await service.todayEnergy() {
            data.energy = Int(energy)
        }
        if let flights = await service.todayFlights() {
            data.flights = flights
        }
        if let dist = await service.todayDistance() {
            data.distance = dist / 1000
        }
        data.heartRate = await service.todayHeartRate()
        data.sleepHours = await service.todaySleepHours()
        // 新增 mobility 数据
        data.walkingSpeed = await service.todayWalkingSpeed()
        data.walkingDoubleSupport = await service.todayWalkingDoubleSupport()
        data.headphoneExposure = await service.todayHeadphoneExposure()
        // 读取今日久坐分钟数（直接从 HealthKit），减去睡眠时间（睡眠时步数为0不应算久坐）
        let sedentary = await service.todaySedentaryMinutes()
        let sleepMinutes = Int((data.sleepHours ?? 0) * 60)
        data.sedentaryMinutes = max(0, sedentary - sleepMinutes)
        hkData = data
    }

    init() {
        userProfile = UserProfileStore.shared.profile
        refresh()
        // @Observable 迁移：用 withObservationTracking 监听 HealthStore.shared.today 变化
        startObservingHealthStore()
    }

    private func startObservingHealthStore() {
        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let snaps = HealthStore.shared.today
                self.today = snaps
                self.insights = HealthAnalyzer.shared.analyze(snapshots: snaps)
                await self.waitForHealthStoreChange()
            }
        }
    }

    private func waitForHealthStoreChange() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            withObservationTracking {
                _ = HealthStore.shared.today
            } onChange: {
                cont.resume()
            }
        }
    }

    deinit {
        // observationTask 是 main actor isolated,deinit 不在 main actor,
        // 不能直接 cancel。Task 会在 self 释放后由 GC 回收 (Task 持有 weak self)。
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
        today.last?.cumulativeStepCount ?? 0
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
    /// 当前久坐 session live 时长（M:SS）
    var currentSitDuration: String? = nil
    /// 当前身体状态
    var currentBodyState: String = "sit"

    @State private var vm = DataRecordViewModel()
    /// LLM 生成的今日洞察（一句）
    @State private var insight: String = ""
    @State private var isLoadingInsight: Bool = false
    /// 数据导出
    @State private var showExportSheet: Bool = false
    @State private var exportURL: URL? = nil
    @State private var isExporting: Bool = false
    /// 7 天导出 loading
    @State private var isExporting7d: Bool = false

    // MARK: - HealthKit Computed Properties

    /// 单一数据源：vm.hkData 为 nil 时回退到空 HKLiveData，所有 UI 只读这里
    private var hk: HKLiveData { vm.hkData ?? HKLiveData() }

    private var hkSteps: String { "\(hk.steps)" }
    private var hkEnergy: String { hk.energy > 0 ? "\(hk.energy)" : "--" }
    private var hkFlights: String { hk.flights > 0 ? "\(hk.flights)" : "--" }
    private var hkDistance: String { hk.distance > 0 ? String(format: "%.1f", hk.distance) : "--" }

    // MARK: - Mobility Computed Properties

    private var hkWalkingSpeed: String {
        guard let v = hk.walkingSpeed else { return "--" }
        return String(format: "%.1f", v)
    }

    private var hkDoubleSupport: String {
        guard let v = hk.walkingDoubleSupport else { return "--" }
        return String(format: "%.1f", v)
    }

    private var hkSleepValue: String {
        guard let v = hk.sleepHours else { return "--" }
        if v <= 0 { return "--" }
        return String(format: "%.1f", v)
    }

    private var hkSedentaryValue: String {
        let m = hk.sedentaryMinutes
        if m == 0 { return "--" }
        return String(format: "%.1fh", Double(m) / 60.0)
    }

    /// 当前久坐持续时间（M:SS）
    private var hkCurrentSitValue: String {
        currentSitDuration ?? "--"
    }

    /// 久坐分析文本（仅坐姿时显示）
    private var sedentaryAnalysis: String? {
        guard currentBodyState == "sit", let duration = currentSitDuration else { return nil }
        let parts = duration.split(separator: ":")
        guard parts.count == 2, let minutes = Int(parts[0]), let seconds = Int(parts[1]) else { return nil }
        let totalSeconds = minutes * 60 + seconds
        if totalSeconds < 30 * 60 {
            return "正在久坐，建议每 30 分钟起身活动一下"
        } else if totalSeconds < 60 * 60 {
            return "久坐较久，血流有所减缓，记得站起来活动"
        } else {
            return "长期久坐风险增加，建议立刻起身走动或做拉伸"
        }
    }

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

    /// 血氧显示值：或 --
    private var bloodOxygenValue: String {
        guard let v = BodyMetricsStore.shared.bloodOxygen else { return "--" }
        return "\(v)"
    }

    /// 睡眠时长显示值：或 --
    /// 三层 fallback：
    /// 1. 用户对话里说过的（BodyMetricsStore）
    /// 2. HealthKit sleepAnalysis
    /// 3. body state 快照推断（HealthStore.shared.today 中 bodyState == "sleep" 的时间跨度）
    private var sleepValue: String {
        if let v = BodyMetricsStore.shared.sleepHours {
            if v == 0 { return "0" } // 失眠
            return String(format: "%.1f", v)
        }
        if let v = hk.sleepHours, v > 0 {
            return String(format: "%.1f", v)
        }
        // 第三层：body state 快照推断
        if vm.sleepMinutes > 0 {
            return String(format: "%.1f", Double(vm.sleepMinutes) / 60.0)
        }
        return "--"
    }

    /// 睡眠卡片副标：标明数据来源
    private var sleepSub: String {
        if BodyMetricsStore.shared.sleepHours != nil { return "来自对话分析" }
        if (hk.sleepHours ?? 0) > 0 { return "来自 HealthKit" }
        if vm.sleepMinutes > 0 { return "来自本地推断" }
        return "暂无数据"
    }

    /// 运动时长显示值（从 HealthStore 快照统计 bodyState == "walk" 的分钟数）
    private var exerciseValue: String {
        let m = HealthStore.shared.today.filter { $0.bodyState == "walk" }.count
        guard m > 0 else { return "--" }
        return "\(m)"
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

    // MARK: - HealthKit Section

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                DataRecordHeader(
                    isExporting: $isExporting,
                    isExporting7d: $isExporting7d,
                    showExportSheet: $showExportSheet,
                    exportURL: $exportURL,
                    onClose: onClose
                )
                .padding(.horizontal, 20)
                .padding(.top, 16)

                ScrollView {
                    VStack(spacing: 12) {
                        TodayInsightView(
                            insight: insight,
                            isLoadingInsight: isLoadingInsight,
                            todayDate: todayDateString()
                        )
                        DashboardSection(
                            hkSteps: hkSteps,
                            hkEnergy: hkEnergy,
                            hkFlights: hkFlights,
                            hkDistance: hkDistance,
                            hkWalkingSpeed: hkWalkingSpeed,
                            hkDoubleSupport: hkDoubleSupport,
                            hkSleepValue: hkSleepValue,
                            hkSedentaryValue: hkSedentaryValue,
                            hkCurrentSitValue: hkCurrentSitValue,
                            sleepSub: sleepSub,
                            sleepValue: sleepValue,
                            exerciseValue: exerciseValue,
                            dietEntries: dietEntries,
                            bpValue: bpValue,
                            sugarValue: sugarValue,
                            bloodOxygenValue: bloodOxygenValue,
                            mealLabel: mealLabel
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            vm.refresh()
        }
        .task {
            // vm.hkData 为 @Published：赋值后自动触发 view 重渲染，UI 通过 hk 计算属性读取
            await vm.loadHKData()
            // 每次打开都调 LLM 生成一句洞察
            await generateInsight()
        }
        .sheet(isPresented: $showExportSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Header

    // MARK: - 今日洞察

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
        // 今日步数: 取最后一条 snapshot 的 cumulativeStepCount (已是全天累计)
        let steps = snaps.last?.cumulativeStepCount ?? 0
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
}

// MARK: - Header

private struct DataRecordHeader: View {
    @Binding var isExporting: Bool
    @Binding var isExporting7d: Bool
    @Binding var showExportSheet: Bool
    @Binding var exportURL: URL?
    var onClose: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            Text("数据记录")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.navy)
            Spacer()
            // 导出今日按钮
            Button(action: {
                isExporting = true
                Task {
                    exportURL = await HealthKitService.shared.exportTodayData()
                    isExporting = false
                    if exportURL != nil {
                        showExportSheet = true
                    }
                }
            }) {
                if isExporting {
                    ProgressView().controlSize(.small).frame(width: 32, height: 32)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.navy)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Theme.card).overlay(Circle().stroke(Theme.border, lineWidth: 1)))
                }
            }
            // 导出最近 7 天按钮
            Button(action: {
                isExporting7d = true
                Task {
                    exportURL = await HealthKitService.shared.exportLast7Days()
                    isExporting7d = false
                    if exportURL != nil {
                        showExportSheet = true
                    }
                }
            }) {
                if isExporting7d {
                    ProgressView().controlSize(.small).frame(width: 44, height: 32)
                } else {
                    Text("7天")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.navy)
                        .frame(width: 44, height: 32)
                        .background(Capsule().fill(Theme.card).overlay(Capsule().stroke(Theme.border, lineWidth: 1)))
                }
            }
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
}

// MARK: - 今日洞察

private struct TodayInsightView: View {
    let insight: String
    let isLoadingInsight: Bool
    let todayDate: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("今日洞察")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.navy)
                Spacer()
                Text(todayDate)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.slate)
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
}

// MARK: - HealthKit Section

private struct HealthKitSectionView: View {
    let hkSteps: String
    let hkEnergy: String
    let hkFlights: String
    let hkDistance: String
    let hkWalkingSpeed: String
    let hkDoubleSupport: String
    let hkSleepValue: String
    let hkCurrentSitValue: String
    let hkSedentaryValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("健康数据")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.navy)
                Spacer()
                Text("来自 iPhone")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.slate)
            }

            VStack(spacing: 10) {
                // 2x2 网格
                HStack(spacing: 10) {
                    DashboardCard(
                        icon: "figure.walk",
                        iconColor: Theme.dashSteps,
                        title: "步数",
                        sub: "今日累计",
                        value: hkSteps,
                        valueUnit: "步"
                    )
                    DashboardCard(
                        icon: "flame.fill",
                        iconColor: Theme.dashDiet,
                        title: "活动能量",
                        sub: "今日累计",
                        value: hkEnergy,
                        valueUnit: "kcal"
                    )
                }
                HStack(spacing: 10) {
                    DashboardCard(
                        icon: "figure.climbing",
                        iconColor: Theme.dashBody,
                        title: "爬楼",
                        sub: "今日累计",
                        value: hkFlights,
                        valueUnit: "层"
                    )
                    DashboardCard(
                        icon: "map.fill",
                        iconColor: Theme.dashSteps,
                        title: "距离",
                        sub: "今日累计",
                        value: hkDistance,
                        valueUnit: "km"
                    )
                }
                // 新增 mobility 卡片
                HStack(spacing: 10) {
                    DashboardCard(
                        icon: "figure.walk.motion",
                        iconColor: Theme.dashSteps,
                        title: "步速",
                        sub: "今日平均",
                        value: hkWalkingSpeed,
                        valueUnit: "m/s"
                    )
                    DashboardCard(
                        icon: "waveform.path.ecg",
                        iconColor: Theme.dashBlood,
                        title: "步态分析",
                        sub: "双支撑比例",
                        value: hkDoubleSupport,
                        valueUnit: "%"
                    )
                }
                // 睡眠（来自 Health App 手动记录）
                DashboardCard(
                    icon: "moon.zzz.fill",
                    iconColor: Theme.dashSleep,
                    title: "睡眠时长",
                    sub: "来自健康 App",
                    value: hkSleepValue,
                    valueUnit: "小时"
                )
                // 久坐双卡：当前 session + 今日累计（含步行打断后的重新积累）
                HStack(spacing: 10) {
                    DashboardCard(
                        icon: "figure.seated.side",
                        iconColor: Theme.dashSedentary,
                        title: "当前久坐",
                        sub: "正在持续",
                        value: hkCurrentSitValue,
                        valueUnit: ""
                    )
                    DashboardCard(
                        icon: "figure.seated.side",
                        iconColor: Theme.dashSedentary,
                        title: "久坐累计",
                        sub: "含打断后累计",
                        value: hkSedentaryValue,
                        valueUnit: ""
                    )
                }
            }
        }
    }
}

// MARK: - Dashboard

private struct DashboardSection: View {
    let hkSteps: String
    let hkEnergy: String
    let hkFlights: String
    let hkDistance: String
    let hkWalkingSpeed: String
    let hkDoubleSupport: String
    let hkSleepValue: String
    let hkSedentaryValue: String
    let hkCurrentSitValue: String
    let sleepSub: String
    let sleepValue: String
    let exerciseValue: String
    let dietEntries: [FoodEntry]
    let bpValue: String
    let sugarValue: String
    let bloodOxygenValue: String
    var mealLabel: (MealType) -> String

    var body: some View {
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
                        sub: sleepSub,
                        value: sleepValue,
                        valueUnit: "小时"
                    )
                    DashboardCard(
                        icon: "figure.walk",
                        iconColor: Theme.dashSteps,
                        title: "步数",
                        sub: "今日累计",
                        value: hkSteps,
                        valueUnit: "步"
                    )
                }

                // 第二行: 运动记录 + 饮食记录
                HStack(spacing: 10) {
                    DashboardCard(
                        icon: "figure.run",
                        iconColor: Theme.dashSteps,
                        title: "运动记录",
                        sub: "来自对话分析",
                        value: exerciseValue,
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
                            sub: "来自对话分析",
                            value: bloodOxygenValue,
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

            // MARK: - HealthKit Section

            HealthKitSectionView(
                hkSteps: hkSteps,
                hkEnergy: hkEnergy,
                hkFlights: hkFlights,
                hkDistance: hkDistance,
                hkWalkingSpeed: hkWalkingSpeed,
                hkDoubleSupport: hkDoubleSupport,
                hkSleepValue: hkSleepValue,
                hkCurrentSitValue: hkCurrentSitValue,
                hkSedentaryValue: hkSedentaryValue
            )
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
