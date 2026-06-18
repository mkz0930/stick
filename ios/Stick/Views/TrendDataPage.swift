// ios/Stick/Views/TrendDataPage.swift
import SwiftUI

/// Rule 9 预聚合后的指标桶：UI 直接消费，不在 body 里再做 map
struct MetricBucket: Identifiable, Equatable {
    let id: String          // 日期 "yyyy-MM-dd"
    let value: Double
}

struct ScoreBucket: Identifiable, Equatable {
    let id: String          // 日期 "yyyy-MM-dd"
    let score: Int
}

struct TrendDataPage: View {
    @State private var selectedRange: TrendRange = .week

    enum TrendRange: String, CaseIterable {
        case today = "今日"
        case week = "本周"
        case month = "本月"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 时间维度切换
                    Picker("范围", selection: $selectedRange) {
                        ForEach(TrendRange.allCases, id: \.self) { r in Text(r.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // 三大指标趋势 —— 全部消费预聚合桶
                    MetricTrendCard(
                        title: "睡眠时长",
                        icon: "moon.fill",
                        unit: "h",
                        buckets: sleepBuckets,
                        qualityValues: sleepQualityValues,
                        baseColor: .purple
                    )

                    MetricTrendCard(
                        title: "步行时长",
                        icon: "figure.walk",
                        unit: "m",
                        buckets: walkBuckets,
                        qualityValues: nil,
                        baseColor: .green
                    )

                    MetricTrendCard(
                        title: "久坐时长",
                        icon: "chair.fill",
                        unit: "h",
                        buckets: sedentaryBuckets,
                        qualityValues: nil,
                        baseColor: .orange
                    )

                    MetricTrendCard(
                        title: "步行稳定度",
                        icon: "figure.walk.motion",
                        unit: "",
                        buckets: stabilityBuckets,
                        qualityValues: nil,
                        baseColor: .blue,
                        referenceValue: stabilityBaseline14d
                    )

                    // 身体状态得分折线图 —— 消费预聚合桶
                    BodyScoreTrendChart(buckets: scoreBuckets)

                    // 历史日报列表
                    if !trendReports.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("历史日报")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)

                            ForEach(trendReports) { report in
                                NavigationLink(destination: MorningReportDetailView(report: report)) {
                                    ReportRow(report: report)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("趋势数据")
        }
    }

    // MARK: - 数据源

    /// 选定范围内的 report 列表（已限定窗口）
    private var trendReports: [MorningReport] {
        let reports = MorningReportStore.shared.reports
        switch selectedRange {
        case .today:
            let today = Self.dateFormatter.string(from: Date())
            return reports.filter { $0.date == today }
        case .week:
            return Array(reports.prefix(7))
        case .month:
            return Array(reports.prefix(30))
        }
    }

    // MARK: - Rule 9 预聚合桶
    // 每个桶对应一天 (yyyy-MM-dd)，每个 metric 一次性物化成 [MetricBucket]
    // 视图层直接遍历 bucket，不在 body 里再算 map

    private var sleepBuckets: [MetricBucket] {
        trendReports.map {
            MetricBucket(id: $0.date, value: Double($0.sleepMinutes) / 60.0)
        }
    }

    private var sleepQualityValues: [String] {
        trendReports.map { $0.sleepQuality }
    }

    private var walkBuckets: [MetricBucket] {
        trendReports.map {
            MetricBucket(id: $0.date, value: Double($0.walkMinutes))
        }
    }

    private var sedentaryBuckets: [MetricBucket] {
        trendReports.map {
            MetricBucket(id: $0.date, value: Double($0.sedentaryMinutes) / 60.0)
        }
    }

    private var stabilityBuckets: [MetricBucket] {
        trendReports.map {
            MetricBucket(id: $0.date, value: walkingStabilityScore(report: $0))
        }
    }

    private var scoreBuckets: [ScoreBucket] {
        trendReports.map {
            ScoreBucket(id: $0.date, score: $0.llmScore)
        }
    }

    /// 步行稳定度 14 天滚动均值（用于参考基线）
    /// 排除当天未来得及生成报告的天；至少需要 3 个有效样本才有参考价值
    private var stabilityBaseline14d: Double? {
        let last14 = Array(MorningReportStore.shared.reports.prefix(14))
        let values = last14.map { walkingStabilityScore(report: $0) }.filter { $0 > 0 }
        guard values.count >= 3 else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}

// MARK: - 步行稳定度（速度归一化残差）

/// 步行稳定度 0-100：基于双脚支撑残差
/// expected_ds = 0.45 - 0.13 × speed
/// residual = actual_ds - expected_ds
/// stability = clamp(100 - residual × 500, 0, 100)
/// 残差 ≈ 0 → 100；残差 +0.1 → 50；残差 +0.2 → 0
private func walkingStabilityScore(report: MorningReport) -> Double {
    guard let ds = report.doubleSupport, let speed = report.avgSpeed else { return 0 }
    let expectedDS = 0.45 - 0.13 * speed
    let residual = ds - expectedDS
    return max(0, min(100, 100 - residual * 500))
}

struct MetricTrendCard: View {
    let title: String
    let icon: String
    let unit: String
    /// Rule 9: 消费预聚合桶；body 不再做 map
    let buckets: [MetricBucket]
    let qualityValues: [String]?
    let baseColor: Color
    /// 可选：参考基线（如 14 天均值），会在柱状图上画一条水平虚线
    var referenceValue: Double? = nil

    private var values: [Double] { buckets.map { $0.value } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.caption)
                    .foregroundColor(baseColor)
                Spacer()
                if let ref = referenceValue {
                    Text(String(format: "14天 %.0f", ref))
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                Text(averageText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let trend = trendArrow {
                    Text(trend)
                        .font(.caption)
                        .foregroundColor(trendColor)
                }
            }

            // 柱状图（含参考基线）
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(barData.enumerated()), id: \.offset) { idx, height in
                    VStack {
                        Rectangle()
                            .fill(barColor(idx: idx))
                            .frame(height: max(4, height))
                        if showLabels {
                            Text(dayLabels[safe: idx] ?? "")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(height: 40)
            .overlay(alignment: .topLeading) {
                if let refY = referenceLineY {
                    // 参考基线虚线
                    HStack(spacing: 2) {
                        Rectangle()
                            .fill(baseColor.opacity(0.5))
                            .frame(height: 1)
                            .frame(maxWidth: .infinity)
                        Text(String(format: "%.0f", referenceValue ?? 0))
                            .font(.system(size: 8))
                            .foregroundColor(baseColor.opacity(0.7))
                    }
                    .offset(y: refY)
                    .allowsHitTesting(false)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var barData: [CGFloat] {
        guard let maxVal = values.max(), maxVal > 0 else { return values.map { _ in 4 } }
        return values.map { CGFloat($0 / maxVal) * 36 }
    }

    /// 参考基线在柱状图区域内的 y 坐标
    private var referenceLineY: CGFloat? {
        guard let ref = referenceValue,
              let maxVal = values.max(),
              maxVal > 0 else { return nil }
        let ratio = CGFloat(ref / maxVal)
        return max(0, min(36, ratio * 36))
    }

    private var showLabels: Bool { buckets.count <= 7 }

    private var dayLabels: [String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return buckets.map { b in
            if let date = Self.dateFormatter.date(from: b.id) {
                return formatter.string(from: date)
            }
            return ""
        }
    }

    private var averageText: String {
        guard !values.isEmpty else { return "--" }
        let avg = values.reduce(0, +) / Double(values.count)
        return String(format: "均值 %.1f%@", avg, unit)
    }

    private var trendArrow: String? {
        guard values.count >= 2 else { return nil }
        let recent = values.prefix(values.count / 2 + 1).reduce(0, +) / Double(values.count / 2 + 1)
        let older = values.suffix(values.count / 2).reduce(0, +) / Double(values.count / 2)
        let diff = (recent - older) / older * 100
        if abs(diff) < 5 { return "→" }
        return diff > 0 ? "↑" : "↓"
    }

    private var trendColor: Color {
        guard let arrow = trendArrow else { return .secondary }
        return arrow == "↑" ? .green : (arrow == "↓" ? .red : .secondary)
    }

    private func barColor(idx: Int) -> Color {
        if let qualities = qualityValues {
            let q = qualities[safe: idx] ?? ""
            switch q {
            case "连续": return baseColor
            case "轻度中断": return baseColor.opacity(0.7)
            case "中断": return baseColor.opacity(0.5)
            case "碎片化": return baseColor.opacity(0.3)
            default: return baseColor.opacity(0.5)
            }
        }
        return baseColor
    }

    private static var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}

struct BodyScoreTrendChart: View {
    /// Rule 9: 消费预聚合桶；body 不再做 map
    let buckets: [ScoreBucket]

    private var scores: [Int] { buckets.map { $0.score } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: 标题 + 当前值
            HStack(alignment: .firstTextBaseline) {
                Label("身体状态得分", systemImage: "heart.text.square.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                if let current = currentScore {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(current)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(scoreColor(current))
                            .contentTransition(.numericText())
                        Text("/100")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if buckets.isEmpty {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                // 主图：彩色区域 + 折线 + 数据点
                TrendChartArea(buckets: buckets, average14d: average14d, scoreColor: scoreColor)

                // 底部：min / avg / max + 14天均值对照
                TrendStatsRow(
                    minScore: minScore,
                    avgScore: avgScore,
                    maxScore: maxScore,
                    trendVsAvg: trendVsAvg
                )
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - 计算属性

    private var currentScore: Int? { buckets.first?.score }

    private var minScore: Int? {
        guard !scores.isEmpty else { return nil }
        return scores.min()
    }

    private var maxScore: Int? {
        guard !scores.isEmpty else { return nil }
        return scores.max()
    }

    private var avgScore: Int? {
        guard !scores.isEmpty else { return nil }
        return Int(Double(scores.reduce(0, +)) / Double(scores.count))
    }

    private var average14d: Double? {
        let last14 = Array(scores.prefix(14))
        guard last14.count >= 3 else { return nil }
        return Double(last14.reduce(0, +)) / Double(last14.count)
    }

    /// 当前 vs 14天均值差（正数=优于均值，负数=低于均值）
    private var trendVsAvg: Int? {
        guard let current = currentScore, let avg = average14d else { return nil }
        return current - Int(avg.rounded())
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return .red
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - 子视图

private struct TrendChartArea: View {
    /// Rule 9: 消费预聚合桶
    let buckets: [ScoreBucket]
    let average14d: Double?
    var scoreColor: (Int) -> Color

    private var scores: [Int] { buckets.map { $0.score } }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height: CGFloat = 100
            ZStack(alignment: .bottom) {
                // 1. 背景区域色带：60 以下红 / 60-80 橙 / 80+ 绿
                HStack(spacing: 0) {
                    Rectangle().fill(Color.red.opacity(0.06))
                        .frame(width: width * 0.6)
                    Rectangle().fill(Color.orange.opacity(0.06))
                        .frame(width: width * 0.2)
                    Rectangle().fill(Color.green.opacity(0.06))
                        .frame(width: width * 0.2)
                }
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                // 2. 折线 + 数据点
                lineLayer(width: width, height: height)

                // 3. 14天均值参考线
                if let avg = average14d {
                    let y = height - CGFloat(avg) / 100 * height
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(height: 1)
                        Text(String(format: "14天均值 %.0f", avg))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .offset(y: -y)
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 100)
    }

    private func lineLayer(width: CGFloat, height: CGFloat) -> some View {
        let n = max(scores.count, 1)
        let stepX = scores.count > 1 ? width / CGFloat(n - 1) : 0
        let points: [CGPoint] = scores.enumerated().map { i, s in
            CGPoint(
                x: scores.count == 1 ? width / 2 : CGFloat(i) * stepX,
                y: height - CGFloat(s) / 100 * height
            )
        }
        return ZStack {
            // 折线
            Path { p in
                guard let first = points.first else { return }
                p.move(to: first)
                for pt in points.dropFirst() { p.addLine(to: pt) }
            }
            .stroke(scores.last.map { scoreColor($0) } ?? .secondary,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            // 数据点
            ForEach(Array(points.enumerated()), id: \.offset) { idx, pt in
                Circle()
                    .fill(scoreColor(scores[idx]))
                    .frame(width: scores.count <= 7 ? 8 : 5,
                           height: scores.count <= 7 ? 8 : 5)
                    .overlay(
                        Circle().stroke(Color(uiColor: .secondarySystemBackground), lineWidth: 1.5)
                    )
                    .position(pt)
            }

            // 最新点高亮 + 数值标签
            if let last = points.last, let lastScore = scores.last, scores.count <= 14 {
                Text("\(lastScore)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(scoreColor(lastScore))
                    )
                    .position(x: last.x, y: max(12, last.y - 12))
            }
        }
    }
}

private struct TrendStatsRow: View {
    let minScore: Int?
    let avgScore: Int?
    let maxScore: Int?
    let trendVsAvg: Int?

    var body: some View {
        HStack(spacing: 12) {
            statItem(label: "最低", value: minScore, color: .red)
            Divider().frame(height: 24)
            statItem(label: "平均", value: avgScore, color: .orange)
            Divider().frame(height: 24)
            statItem(label: "最高", value: maxScore, color: .green)
            if let trend = trendVsAvg {
                Divider().frame(height: 24)
                HStack(spacing: 2) {
                    Image(systemName: trend > 0 ? "arrow.up.right" : (trend < 0 ? "arrow.down.right" : "arrow.right"))
                        .font(.system(size: 10, weight: .bold))
                    Text(String(format: "%+.0f", trend))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(trend > 0 ? .green : (trend < 0 ? .red : .secondary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statItem(label: String, value: Int?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text(value.map { "\($0)" } ?? "--")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}