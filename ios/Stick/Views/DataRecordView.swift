//
//  DataRecordView.swift
//  数据记录 — 消费 HealthStore.shared.today 真实数据
//

import SwiftUI
import Combine

@MainActor
final class DataRecordViewModel: ObservableObject {
    @Published var today: [HealthSnapshot] = []
    @Published var insights: [HealthInsight] = []

    private var cancellables: Set<AnyCancellable> = []

    init() {
        // 初次拉一次
        refresh()

        // 订阅 HealthStore.shared.$today, 一旦有变化自动重算
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
        HealthStore.shared.refreshToday()
        let snaps = HealthStore.shared.today
        today = snaps
        insights = HealthAnalyzer.shared.analyze(snapshots: snaps)
    }

    // MARK: - 聚合

    /// 当日总步数
    var totalSteps: Int {
        today.compactMap { $0.stepCount }.reduce(0, +)
    }

    /// 当日平均心率 (排除 nil, 取整)
    var avgHeartRate: Int? {
        let hrs = today.compactMap { $0.heartRate }
        guard !hrs.isEmpty else { return nil }
        return Int((hrs.reduce(0, +) / Double(hrs.count)).rounded())
    }

    /// 当日最高心率
    var maxHeartRate: Int? {
        guard let v = today.compactMap({ $0.heartRate }).max() else { return nil }
        return Int(v.rounded())
    }

    /// 当日总活动能量 (千卡, 取整)
    var totalEnergy: Int {
        Int(today.compactMap { $0.activeEnergy }.reduce(0, +).rounded())
    }

    /// 久坐累计分钟 (用 StateInference.inferSingle 对每条快照, 数 .sit 的数量, 粗估分钟数)
    var sedentaryMinutes: Int {
        var count = 0
        for s in today {
            if StateInference.inferSingle(s).state == .sit {
                count += 1
            }
        }
        return count
    }

    /// 活跃累计分钟 (walk 或有步数)
    var activeMinutes: Int {
        let sorted = today.sorted { $0.timestamp < $1.timestamp }
        var runMin = 0; var total = 0
        for s in sorted {
            let active = (s.bodyState == "walk") || ((s.stepCount ?? 0) > 0)
            if active { runMin += 1; total += 1 }
            else { runMin = 0 }
        }
        return total
    }

    /// 睡眠累计分钟
    var sleepMinutes: Int {
        let sleeps = today.filter { $0.bodyState == "sleep" }
        guard let first = sleeps.first?.timestamp, let last = sleeps.last?.timestamp else { return 0 }
        return Int(last.timeIntervalSince(first) / 60)
    }

    /// 24 个小时柱状条 (每条高度 = 该小时内步数 / 最大小时步数)
    var hourlyBars: [HourlyBar] {
        var buckets: [Int: Int] = [:]  // hour -> steps
        for s in today {
            let h = Calendar.current.component(.hour, from: s.timestamp)
            buckets[h, default: 0] += s.stepCount ?? 0
        }
        let maxV = max(buckets.values.max() ?? 0, 1)
        return (0..<24).map { h in
            HourlyBar(hour: h, value: buckets[h] ?? 0, normalized: Double(buckets[h] ?? 0) / Double(maxV))
        }
    }

    /// 24 小时的状态色块 (walk / sit / sleep)
    /// 简单规则: stepCount > 30 → walk, stepCount == 0 且时段在睡眠窗口 22-07 → sleep, 否则 sit
    var hourlyStates: [Int: String] {
        var buckets: [Int: [String]] = [:]   // hour -> [state]
        for s in today {
            let h = Calendar.current.component(.hour, from: s.timestamp)
            buckets[h, default: []].append(s.bodyState)
        }
        var out: [Int: String] = [:]
        for h in 0..<24 {
            let snaps = buckets[h] ?? []
            if snaps.isEmpty {
                // 没有任何快照, 按时段默认
                out[h] = (h >= 22 || h < 7) ? "sleep" : "sit"
                continue
            }
            // 取该小时最常见的状态
            let counts = snaps.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            out[h] = counts.max(by: { $0.value < $1.value })?.key ?? "sit"
        }
        return out
    }
}

struct HourlyBar: Identifiable {
    let id = UUID()
    let hour: Int
    let value: Int
    let normalized: Double  // 0–1
}

// MARK: - 视图

struct DataRecordView: View {
    var onClose: () -> Void
    var deviceSet: Set<DeviceID> = []
    @StateObject private var vm = DataRecordViewModel()
    @StateObject private var healthAuth = HealthAuthService.shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.bgTop.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                if vm.today.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 18) {
                            summaryCards
                            hourlyChart
                            insightsSection
                            snapshotCount
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                    .refreshable { vm.refresh() }
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear { vm.refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("数据记录")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.navy)
                Text(todayString() + " · 共 \(vm.today.count) 条快照")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.slate)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.navy)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.card).overlay(Circle().stroke(Theme.border, lineWidth: 1)))
            }
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(Theme.mist)
            Text("今日暂无数据")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.navy)
            Text("等待 HealthKit 抓取…")
                .font(.system(size: 12))
                .foregroundColor(Theme.slate)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 4 张汇总卡 (按设备能力灰显)

    private var summaryCards: some View {
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: cols, spacing: 10) {
            SummaryCard(
                icon: "figure.walk", iconColor: Color(red: 0.30, green: 0.85, blue: 0.50),
                label: "今日步数", value: "\(vm.totalSteps)", unit: "步",
                metricID: .steps, deviceSet: deviceSet, healthStatuses: healthAuth.statuses
            )
            SummaryCard(
                icon: "heart.fill", iconColor: Color(red: 0.92, green: 0.34, blue: 0.34),
                label: "平均心率",
                value: vm.avgHeartRate.map { "\($0)" } ?? "—",
                unit: vm.avgHeartRate != nil ? "bpm" : "",
                metricID: .heartRate, deviceSet: deviceSet, healthStatuses: healthAuth.statuses
            )
            SummaryCard(
                icon: "flame.fill", iconColor: Color(red: 0.96, green: 0.62, blue: 0.10),
                label: "活动能量", value: "\(vm.totalEnergy)", unit: "千卡",
                metricID: .activeEnergy, deviceSet: deviceSet, healthStatuses: healthAuth.statuses
            )
            SummaryCard(
                icon: "figure.seated.side", iconColor: Color(red: 0.55, green: 0.50, blue: 0.85),
                label: "久坐累计", value: "\(vm.sedentaryMinutes)", unit: "分钟",
                metricID: .standHours, deviceSet: deviceSet, healthStatuses: healthAuth.statuses
            )
        }
    }

    // MARK: - 24h 柱状图

    private var hourlyChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("24 小时活跃度")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.navy)
                Spacer()
                Text("活跃 \(vm.activeMinutes)m · 久坐 \(vm.sedentaryMinutes)m · 睡眠 \(vm.sleepMinutes)m")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.slate)
            }

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(vm.hourlyBars) { bar in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor(for: bar.hour))
                            .frame(height: max(4, 80 * bar.normalized))
                        Text(String(format: "%02d", bar.hour))
                            .font(.system(size: 8))
                            .foregroundColor(Theme.mist)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 110)

            // 状态色块 (在柱图下方一行)
            HStack(spacing: 3) {
                ForEach(0..<24, id: \.self) { h in
                    Rectangle()
                        .fill(stateColor(vm.hourlyStates[h] ?? ""))
                        .frame(height: 4)
                        .frame(maxWidth: .infinity)
                }
            }

            // 图例
            HStack(spacing: 12) {
                LegendDot(color: Color(red: 0.30, green: 0.85, blue: 0.50), text: "活跃")
                LegendDot(color: Color(red: 0.96, green: 0.62, blue: 0.10), text: "久坐")
                LegendDot(color: Color(red: 0.39, green: 0.40, blue: 0.95), text: "睡眠")
                Spacer()
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1)))
    }

    private func barColor(for hour: Int) -> Color {
        let state = vm.hourlyStates[hour] ?? ""
        switch state {
        case "walk": return Color(red: 0.30, green: 0.85, blue: 0.50)
        case "sleep": return Color(red: 0.39, green: 0.40, blue: 0.95)
        default: return Color(red: 0.96, green: 0.62, blue: 0.10)
        }
    }

    private func stateColor(_ state: String) -> Color {
        switch state {
        case "walk":  return Color(red: 0.30, green: 0.85, blue: 0.50)
        case "sleep": return Color(red: 0.39, green: 0.40, blue: 0.95)
        default:      return Color(red: 0.96, green: 0.62, blue: 0.10)
        }
    }

    // MARK: - 时间洞察

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("时间洞察")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.navy)
                Spacer()
                Text("\(vm.insights.count) 条")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.slate)
            }

            if vm.insights.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 28))
                            .foregroundColor(Color(red: 0.30, green: 0.85, blue: 0.50))
                        Text("暂无异常, 一切正常")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.slate)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(vm.insights.enumerated()), id: \.offset) { idx, insight in
                        InsightRow(insight: insight)
                        if idx < vm.insights.count - 1 {
                            Rectangle()
                                .fill(Theme.borderSoft)
                                .frame(height: 0.5)
                                .padding(.leading, 14)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1)))
            }
        }
    }

    // MARK: - 底部计数

    private var snapshotCount: some View {
        HStack {
            Image(systemName: "tray.full")
                .font(.system(size: 12))
            Text("本地已存储 \(HealthStore.shared.all.count) 条快照 · 路径: Documents/health-snapshots.json")
                .font(.system(size: 10))
        }
        .foregroundColor(Theme.slate)
        .padding(.horizontal, 4)
    }

    // MARK: - 工具

    private func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

// MARK: - 子组件

private struct SummaryCard: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    let unit: String
    let metricID: MetricID?
    let deviceSet: Set<DeviceID>
    let healthStatuses: [MetricID: MetricDataStatus]

    /// 该 metric 在当前 UI 下的呈现
    private var availability: MetricAvailability {
        guard let id = metricID else { return .available }
        let status = healthStatuses[id] ?? .unknown
        return DeviceCapabilities.effective(id, status: status, deviceSet: deviceSet)
    }

    private var isLocked: Bool { availability.kind == .locked }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // 图标 (灰显时变灰)
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isLocked ? Theme.mist.opacity(0.10) : iconColor.opacity(0.15))
                Image(systemName: isLocked ? "lock.fill" : icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isLocked ? Theme.mist : iconColor)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(isLocked ? Theme.mist : Theme.slate)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(isLocked ? "—" : value)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(isLocked ? Theme.mist : Theme.navy)
                    if !unit.isEmpty && !isLocked {
                        Text(unit)
                            .font(.system(size: 10))
                            .foregroundColor(Theme.slate)
                    }
                }
                // 灰显时的解锁提示
                if isLocked {
                    Text(availability.hint)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.mist)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isLocked ? Theme.mist.opacity(0.04) : Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isLocked ? Theme.mist.opacity(0.25) : Theme.border, lineWidth: 1)
        )
        .opacity(isLocked ? 0.65 : 1.0)
    }
}

private struct LegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 10)).foregroundColor(Theme.slate)
        }
    }
}

private struct InsightRow: View {
    let insight: HealthInsight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 严重度色条
            Rectangle()
                .fill(severityColor)
                .frame(width: 3)
                .cornerRadius(2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(insight.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.navy)
                    Spacer()
                    if let v = insight.numericValue {
                        Text(v)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(severityColor)
                    }
                }
                Text(insight.detail)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.slate)
                Text(insight.timestampRange)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.mist)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var severityColor: Color {
        switch insight.severity {
        case .info:  return Color(red: 0.30, green: 0.85, blue: 0.50)
        case .warn:  return Color(red: 0.96, green: 0.62, blue: 0.10)
        case .alert: return Color(red: 0.92, green: 0.34, blue: 0.34)
        }
    }
}

#Preview {
    DataRecordView(onClose: {})
}
