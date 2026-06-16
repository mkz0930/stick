// ios/Stick/Views/MorningReportDetailView.swift
import SwiftUI

struct MorningReportDetailView: View {
    let report: MorningReport
    @State private var adviceTab: Int = 0
    @State private var detailExpanded: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 通知横幅风格 Header
                notificationBanner

                // 主内容
                VStack(spacing: 16) {
                    // 日期 + 问候
                    headerSection

                    // 三大指标卡片
                    metricsCards

                    // 24h 时间条
                    timelineSection

                    // 睡眠分析
                    analysisCard(title: "睡眠分析", icon: "moon.fill", color: .purple) {
                        analysisItems
                    }

                    // 久坐分析
                    analysisCard(title: "久坐分析", icon: "chair.fill", color: .orange) {
                        sedentaryItems
                    }

                    // 运动分析
                    analysisCard(title: "运动分析", icon: "figure.walk", color: .green) {
                        walkItems
                    }

                    // AI 总结
                    aiSummaryCard

                    // 建议 Tab
                    adviceSection

                    // 详细报告折叠
                    detailToggle
                    if detailExpanded {
                        detailContent
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Subviews

    private var notificationBanner: some View {
        HStack {
            Image(systemName: "flame.fill")
                .foregroundColor(.orange)
            Text("Stick")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text("昨天 \(formattedDate(report.date))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text("晨间健康报告")
                .font(.title2)
                .fontWeight(.semibold)
            Text("解锁后的第一件事，了解昨天的自己")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.top, 16)
    }

    private var metricsCards: some View {
        HStack(spacing: 12) {
            MetricCard(title: "睡眠", value: "\(report.sleepMinutes / 60)h\(report.sleepMinutes % 60)m", sub: report.sleepQuality, color: .purple, icon: "moon.fill")
            MetricCard(title: "步行", value: "\(report.walkMinutes)m", sub: "\(report.steps) 步", color: .green, icon: "figure.walk")
            MetricCard(title: "久坐", value: "\(report.sedentaryMinutes / 60)h\(report.sedentaryMinutes % 60)m", sub: "累计", color: .orange, icon: "chair.fill")
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("昨日 24h 状态分布")
                .font(.caption)
                .foregroundColor(.secondary)
            // 简化时间条，用 StickState.daySchedule 渲染
            DayTimelineView(schedule: StickState.daySchedule, displayMinute: minutesOfDay)
                .frame(height: 12)
            HStack(spacing: 12) {
                ForEach(["睡眠", "步行", "久坐"], id: \.self) { label in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(colorForLabel(label))
                            .frame(width: 8, height: 8)
                        Text(label).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var analysisItems: some View {
        VStack(spacing: 0) {
            analysisRow("睡眠时长", "\(report.sleepMinutes / 60)h\(report.sleepMinutes % 60)m")
            analysisRow("睡眠质量", report.sleepQuality, color: .orange)
            analysisRow("入睡时间", "00:00")
            analysisRow("起床时间", minuteToTimeString(report.wakeUpMinute))
            analysisRow("步态评分", "\(report.gaitScore)/100")
        }
    }

    private var sedentaryItems: some View {
        VStack(spacing: 0) {
            analysisRow("累计久坐", "\(report.sedentaryMinutes / 60)h\(report.sedentaryMinutes % 60)m", color: .orange)
            analysisRow("最长连续", "\(report.longestSedentaryMin / 60)h\(report.longestSedentaryMin % 60)m")
        }
    }

    private var walkItems: some View {
        VStack(spacing: 0) {
            analysisRow("总步数", "\(report.steps) 步")
            analysisRow("步行时长", "\(report.walkMinutes) 分钟")
            if let speed = report.avgSpeed {
                analysisRow("平均步速", String(format: "%.2f m/s", speed))
            }
            if let ds = report.doubleSupport {
                analysisRow("双脚支撑", String(format: "%.1f%%", ds))
            }
            analysisRow("步态评分", "\(report.gaitScore)/100")
        }
    }

    private func analysisRow(_ key: String, _ val: String, color: Color = .primary) -> some View {
        HStack {
            Text(key).foregroundColor(.secondary)
            Spacer()
            Text(val).fontWeight(.semibold).foregroundColor(color)
        }
        .font(.subheadline)
        .padding(.vertical, 6)
    }

    private var aiSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI 综合评估").font(.caption).foregroundColor(.green)
            HStack(spacing: 12) {
                scoreCircle
                VStack(alignment: .leading) {
                    Text("昨日健康得分").font(.caption).foregroundColor(.secondary)
                    Text(report.llmSummary).font(.subheadline)
                }
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }

    private var scoreCircle: some View {
        ZStack {
            Circle()
                .stroke(Color.green.opacity(0.3), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(report.llmScore) / 100)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(report.llmScore)")
                .font(.headline)
                .foregroundColor(.green)
        }
        .frame(width: 50, height: 50)
    }

    private var adviceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("建议", selection: $adviceTab) {
                Text("短期建议").tag(0)
                Text("长期建议").tag(1)
            }
            .pickerStyle(.segmented)

            if adviceTab == 0 {
                ForEach(report.llmShortAdvice, id: \.self) { advice in
                    adviceRow(advice)
                }
            } else {
                ForEach(report.llmLongAdvice, id: \.self) { advice in
                    adviceRow(advice)
                }
            }
        }
    }

    private func adviceRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("→").foregroundColor(.green)
            Text(text).font(.subheadline).foregroundColor(.secondary)
        }
    }

    private var detailToggle: some View {
        Button {
            withAnimation { detailExpanded.toggle() }
        } label: {
            HStack {
                Text(detailExpanded ? "▲ 收起详细报告" : "▼ 展开详细报告")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }

    private var detailContent: some View {
        Text(report.llmDetail)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 8)
    }

    // MARK: - Helpers

    private var minutesOfDay: Int {
        let calendar = Calendar.current
        return calendar.component(.hour, from: Date()) * 60 + calendar.component(.minute, from: Date())
    }

    private var todayDateStr: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func minuteToTimeString(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    private func formattedDate(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }

    private func colorForLabel(_ label: String) -> Color {
        switch label {
        case "睡眠": return .purple
        case "步行": return .green
        case "久坐": return .orange
        default: return .gray
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let sub: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundColor(color)
            Text(value).font(.headline)
            Text(title).font(.caption2).foregroundColor(.secondary)
            Text(sub).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

private func analysisCard<Content: View>(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Label(title, systemImage: icon)
            .font(.caption)
            .foregroundColor(color)
        content()
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(uiColor: .secondarySystemBackground))
    .cornerRadius(12)
}