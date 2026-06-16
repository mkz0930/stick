// ios/Stick/Views/TrendDataPage.swift
import SwiftUI

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

                    // 三大指标趋势
                    MetricTrendCard(
                        title: "睡眠时长",
                        icon: "moon.fill",
                        unit: "h",
                        values: trendReports.map { Double($0.sleepMinutes) / 60.0 },
                        qualityValues: trendReports.map { $0.sleepQuality },
                        baseColor: .purple
                    )

                    MetricTrendCard(
                        title: "步行时长",
                        icon: "figure.walk",
                        unit: "m",
                        values: trendReports.map { Double($0.walkMinutes) },
                        qualityValues: nil,
                        baseColor: .green
                    )

                    MetricTrendCard(
                        title: "久坐时长",
                        icon: "chair.fill",
                        unit: "h",
                        values: trendReports.map { Double($0.sedentaryMinutes) / 60.0 },
                        qualityValues: nil,
                        baseColor: .orange
                    )

                    MetricTrendCard(
                        title: "步行稳定度",
                        icon: "figure.walk.motion",
                        unit: "",
                        values: trendReports.map { walkingStabilityScore(report: $0) },
                        qualityValues: nil,
                        baseColor: .blue,
                        referenceValue: stabilityBaseline14d
                    )

                    // 身体状态得分折线图
                    BodyScoreTrendChart(scores: trendReports.map { $0.llmScore })

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
    let values: [Double]
    let qualityValues: [String]?
    let baseColor: Color
    /// 可选：参考基线（如 14 天均值），会在柱状图上画一条水平虚线
    var referenceValue: Double? = nil

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

    private var showLabels: Bool { values.count <= 7 }

    private var dayLabels: [String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return trendReports.map { r in
            if let date = Self.dateFormatter.date(from: r.date) {
                return formatter.string(from: date)
            }
            return ""
        }
    }

    private var trendReports: [MorningReport] { MorningReportStore.shared.reports }

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
    let scores: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("身体状态得分")
                .font(.caption)
                .foregroundColor(.secondary)

            if scores.isEmpty {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(scores.enumerated()), id: \.offset) { idx, score in
                        VStack {
                            Spacer()
                            RoundedRectangle(cornerRadius: 2)
                                .fill(scoreColor(score))
                                .frame(height: max(4, CGFloat(score) / 100 * 40))
                            Text("\(score)")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(height: 60)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return .red
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}