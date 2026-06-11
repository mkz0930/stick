//
//  DataRecordView.swift
//  数据记录 — 展示今日健康快照 + 时间分析
//

import SwiftUI
import Combine

@MainActor
final class DataRecordViewModel: ObservableObject {
    @Published var today: [HealthSnapshot] = []
    @Published var insights: [HealthInsight] = []

    init() {
        refresh()
    }

    func refresh() {
        HealthStore.shared.refreshToday()
        today = HealthStore.shared.today
        insights = HealthAnalyzer.shared.analyze(snapshots: today)
    }

    // MARK: - 聚合

    /// 当日总步数
    var totalSteps: Int {
        today.compactMap { $0.stepCount }.reduce(0, +)
    }

    /// 当日平均心率 (排除 nil)
    var avgHeartRate: Double? {
        let hrs = today.compactMap { $0.heartRate }
        guard !hrs.isEmpty else { return nil }
        return hrs.reduce(0, +) / Double(hrs.count)
    }

    /// 当日最高心率
    var maxHeartRate: Double? {
        today.compactMap { $0.heartRate }.max()
    }

    /// 当日总活动能量 (千卡)
    var totalEnergy: Double {
        today.compactMap { $0.activeEnergy }.reduce(0, +)
    }

    /// 久坐累计分钟
    var sedentaryMinutes: Int {
        let sorted = today.sorted { $0.timestamp < $1.timestamp }
        var runMin = 0; var total = 0
        for s in sorted {
            let moving = (s.stepCount ?? 0) > 0
            let isSit = (s.bodyState == "sit") && !moving
            if isSit { runMin += 1; total = max(total, runMin) }
            else { runMin = 0 }
        }
        return total
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

    /// 24 小时的状态色块 (sit = 橙, walk = 绿, sleep = 蓝)
    var hourlyStates: [Int: String] {
        var map: [Int: String] = [:]
        for s in today {
            let h = Calendar.current.component(.hour, from: s.timestamp)
            // 取该小时最常见的状态
            if map[h] == nil { map[h] = s.bodyState }
        }
        return map
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
    @StateObject private var vm = DataRecordViewModel()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.bgTop.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

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

    // MARK: - 4 张汇总卡

    private var summaryCards: some View {
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: cols, spacing: 10) {
            SummaryCard(
                icon: "figure.walk", iconColor: Color(red: 0.30, green: 0.85, blue: 0.50),
                label: "今日步数", value: "\(vm.totalSteps)", unit: "步"
            )
            SummaryCard(
                icon: "heart.fill", iconColor: Color(red: 0.92, green: 0.34, blue: 0.34),
                label: "平均心率", value: vm.avgHeartRate.map { String(format: "%.0f", $0) } ?? "—",
                unit: vm.avgHeartRate != nil ? "bpm" : ""
            )
            SummaryCard(
                icon: "flame.fill", iconColor: Color(red: 0.96, green: 0.62, blue: 0.10),
                label: "活动能量", value: String(format: "%.0f", vm.totalEnergy), unit: "千卡"
            )
            SummaryCard(
                icon: "figure.seated.side", iconColor: Color(red: 0.55, green: 0.50, blue: 0.85),
                label: "久坐最长", value: "\(vm.sedentaryMinutes)", unit: "分钟"
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

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.15))
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(iconColor)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.slate)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.navy)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: 10))
                            .foregroundColor(Theme.slate)
                    }
                }
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1)))
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
