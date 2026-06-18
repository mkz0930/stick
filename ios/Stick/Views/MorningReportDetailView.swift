// ios/Stick/Views/MorningReportDetailView.swift
import SwiftUI

extension Notification.Name {
    static let openChatWithPhoto = Notification.Name("morningReport.openChatWithPhoto")
}

struct MorningReportDetailView: View {
    let report: MorningReport
    @Environment(\.dismiss) private var dismiss
    @State private var adviceTab: Int = 0
    @State private var detailExpanded: Bool = false
    /// 反馈时需要写回字段（let report 不可改），用 @State 镜像
    @State private var feedback: Int?
    @State private var feedbackDate: Date?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 通知横幅风格 Header
                NotificationBanner(report: report, formattedDate: formattedDate)

                // 主内容
                VStack(spacing: 16) {
                    // 日期 + 问候
                    HeaderSection()

                    // 三大指标卡片
                    MetricsCards(report: report)

                    // 24h 时间条
                    TimelineSection(colorForLabel: colorForLabel)

                    // 睡眠分析
                    analysisCard(title: "睡眠分析", icon: "moon.fill", color: .purple) {
                        VStack(alignment: .leading, spacing: 0) {
                            AnalysisItems(
                                report: report,
                                bedtimeDisplay: bedtimeDisplay,
                                wakeUpDisplay: wakeUpDisplay
                            )
                            SleepFeedbackSection(
                                feedback: feedback,
                                feedbackRecordText: feedbackRecordText,
                                feedbackButtons: {
                                    HStack(spacing: 8) {
                                        sleepFeedbackButton(title: "准确", isAccurate: true)
                                        sleepFeedbackButton(title: "不准确", isAccurate: false)
                                    }
                                }
                            )
                        }
                    }

                    // 久坐分析
                    analysisCard(title: "久坐分析", icon: "chair.fill", color: .orange) {
                        SedentaryItems(report: report)
                    }

                    // 运动分析
                    analysisCard(title: "运动分析", icon: "figure.walk", color: .green) {
                        WalkItems(report: report)
                    }

                    // 饮食分析
                    analysisCard(title: "饮食分析", icon: "fork.knife", color: .pink) {
                        DietItems(report: report, dietCaloriesText: dietCaloriesText)
                    }

                    // AI 总结
                    AISummaryCard(report: report)

                    // 建议 Tab
                    AdviceSection(
                        report: report,
                        adviceTab: $adviceTab,
                        adviceRow: adviceRow
                    )

                    // 详细报告折叠
                    DetailToggle(detailExpanded: $detailExpanded)
                    if detailExpanded {
                        DetailContent(report: report)
                    }

                    // 底部操作按钮
                    BottomActionButtons(
                        onCameraTap: { postNotification(seed: "拍照分析我的饮食状态") },
                        onReportTap: { postNotification(seed: "解读我的健康报告") }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 行为方法

    private func sleepFeedbackButton(title: String, isAccurate: Bool) -> some View {
        Button {
            submitFeedback(accurate: isAccurate)
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isAccurate ? .white : .primary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isAccurate ? Color.green : Color(uiColor: .tertiarySystemBackground))
                .cornerRadius(8)
        }
        .buttonStyle(FeedbackButtonStyle())
    }

    private func feedbackRecordText(accurate: Bool) -> String {
        let label = accurate ? "准确" : "不准确"
        let dateStr = feedbackDate.map { feedbackDateTimeFormatter.string(from: $0) } ?? ""
        return "已记录：\(label) · \(dateStr)"
    }

    private func submitFeedback(accurate: Bool) {
        let now = Date()
        feedback = accurate ? 1 : 0
        feedbackDate = now
        // 持久化：写回 report 的反馈字段并保存
        let updated = MorningReport(
            id: report.id,
            date: report.date,
            generatedAt: report.generatedAt,
            sleepMinutes: report.sleepMinutes,
            sleepQuality: report.sleepQuality,
            sleepMidnightWake: report.sleepMidnightWake,
            walkMinutes: report.walkMinutes,
            steps: report.steps,
            avgSpeed: report.avgSpeed,
            doubleSupport: report.doubleSupport,
            sedentaryMinutes: report.sedentaryMinutes,
            longestSedentaryMin: report.longestSedentaryMin,
            longestSedentaryRange: report.longestSedentaryRange,
            wakeUpMinute: report.wakeUpMinute,
            gaitScore: report.gaitScore,
            fatigueIndex: report.fatigueIndex,
            doubleSupportZScore: report.doubleSupportZScore,
            isDoubleSupportAnomaly: report.isDoubleSupportAnomaly,
            avgHeartRate: report.avgHeartRate,
            maxHeartRate: report.maxHeartRate,
            heartRateZoneAnalysis: report.heartRateZoneAnalysis,
            recoveryScore: report.recoveryScore,
            healthkitBedtime: report.healthkitBedtime,
            healthkitWakeUpMinute: report.healthkitWakeUpMinute,
            lastWalkBeforeBed: report.lastWalkBeforeBed,
            breakfastCalories: report.breakfastCalories,
            lunchCalories: report.lunchCalories,
            dinnerCalories: report.dinnerCalories,
            totalCalories: report.totalCalories,
            mealCount: report.mealCount,
            llmSummary: report.llmSummary,
            llmScore: report.llmScore,
            llmShortAdvice: report.llmShortAdvice,
            llmLongAdvice: report.llmLongAdvice,
            llmDetail: report.llmDetail,
            notified: report.notified,
            sleepAccuracyFeedback: feedback,
            sleepFeedbackDate: feedbackDate
        )
        MorningReportStore.shared.save(updated)
        UserProfileStore.shared.recordSleepAccuracy(accurate: accurate, date: now)
    }

    private var feedbackDateTimeFormatter: DateFormatter {
        FeedbackDateTimeFormatter.shared
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

    private func adviceRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("→").foregroundColor(.green)
            Text(text).font(.subheadline).foregroundColor(.secondary)
        }
    }

    private func actionButton(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.1))
            .cornerRadius(8)
        }
    }

    private func postNotification(seed: String) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationCenter.default.post(name: .openChatWithPhoto, object: seed)
        }
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

    private func dietCaloriesText(_ calories: Int?) -> String {
        guard let calories else { return "未记录" }
        return "\(calories) 大卡"
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

    // MARK: - 派生计算属性

    /// 入睡时间展示：有 HealthKit 数据优先用，否则用推测的 wakeUpMinute 反推
    private var bedtimeDisplay: String {
        if let bed = report.healthkitBedtime {
            return minuteToTimeString(bed)
        }
        return "未记录"
    }

    /// 起床时间展示：有 HealthKit 数据优先用，否则用推测值
    private var wakeUpDisplay: String {
        if let wake = report.healthkitWakeUpMinute {
            return minuteToTimeString(wake)
        }
        return minuteToTimeString(report.wakeUpMinute)
    }
}

// MARK: - 通知横幅

private struct NotificationBanner: View {
    let report: MorningReport
    let formattedDate: (String) -> String

    var body: some View {
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
}

// MARK: - 日期 + 问候

private struct HeaderSection: View {
    var body: some View {
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
}

// MARK: - 三大指标卡片

private struct MetricsCards: View {
    let report: MorningReport

    var body: some View {
        HStack(spacing: 12) {
            MetricCard(title: "睡眠", value: "\(report.sleepMinutes / 60)h\(report.sleepMinutes % 60)m", sub: report.sleepQuality, color: .purple, icon: "moon.fill")
            MetricCard(title: "步行", value: "\(report.walkMinutes)m", sub: "\(report.steps) 步", color: .green, icon: "figure.walk")
            MetricCard(title: "久坐", value: "\(report.sedentaryMinutes / 60)h\(report.sedentaryMinutes % 60)m", sub: "累计", color: .orange, icon: "chair.fill")
        }
    }
}

// MARK: - 24h 时间条

private struct TimelineSection: View {
    let colorForLabel: (String) -> Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("昨日 24h 状态分布")
                .font(.caption)
                .foregroundColor(.secondary)
            // 简化时间条
            SimpleTimelineBar()
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
}

// MARK: - 睡眠分析

private struct AnalysisItems: View {
    let report: MorningReport
    let bedtimeDisplay: String
    let wakeUpDisplay: String

    var body: some View {
        VStack(spacing: 0) {
            analysisRow("睡眠时长", "\(report.sleepMinutes / 60)h\(report.sleepMinutes % 60)m")
            analysisRow("睡眠质量", report.sleepQuality, color: .orange)
            analysisRow("入睡时间", bedtimeDisplay)
            analysisRow("起床时间", wakeUpDisplay)
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
}

private struct SleepFeedbackSection<FeedbackButtons: View>: View {
    let feedback: Int?
    let feedbackRecordText: (Bool) -> String
    let feedbackButtons: () -> FeedbackButtons

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("💡 睡眠时间根据活动推测，可能与 HealthKit 实际睡眠有差异")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .padding(.top, 4)

            if let fb = feedback {
                feedbackRecordedView(accurate: fb == 1)
            } else {
                feedbackButtons()
            }
        }
        .padding(.top, 4)
    }

    private func feedbackRecordedView(accurate: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.green)
            Text(feedbackRecordText(accurate))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 久坐 / 运动 / 饮食 / 恢复 items

private struct SedentaryItems: View {
    let report: MorningReport

    var body: some View {
        VStack(spacing: 0) {
            analysisRow("累计久坐", "\(report.sedentaryMinutes / 60)h\(report.sedentaryMinutes % 60)m", color: .orange)
            analysisRow("最长连续", "\(report.longestSedentaryMin / 60)h\(report.longestSedentaryMin % 60)m")
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
}

private struct WalkItems: View {
    let report: MorningReport

    var body: some View {
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
}

private struct DietItems: View {
    let report: MorningReport
    let dietCaloriesText: (Int?) -> String

    var body: some View {
        VStack(spacing: 0) {
            if report.mealCount == 0 {
                Text("暂无饮食记录")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
            } else {
                analysisRow("总卡路里", dietCaloriesText(report.totalCalories), color: .pink)
                analysisRow("早餐", dietCaloriesText(report.breakfastCalories))
                analysisRow("午餐", dietCaloriesText(report.lunchCalories))
                analysisRow("晚餐", dietCaloriesText(report.dinnerCalories))
                analysisRow("餐次记录", "已记录 \(report.mealCount)/3 餐")
            }
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
}

private struct RecoveryItems: View {
    let report: MorningReport

    var body: some View {
        VStack(spacing: 0) {
            // 恢复指数
            let recoveryColor: Color = report.recoveryScore > 70 ? .green : (report.recoveryScore >= 40 ? .orange : .red)
            analysisRow("恢复指数", "\(report.recoveryScore)/100", color: recoveryColor)
            // 平均心率
            if let avgHR = report.avgHeartRate {
                analysisRow("平均心率", "\(avgHR) bpm")
            }
            // 最高心率
            if let maxHR = report.maxHeartRate {
                analysisRow("最高心率", "\(maxHR) bpm")
            }
            // 心率区间分布条
            if let zones = report.heartRateZoneAnalysis {
                HRZoneBar(zones: zones)
            }
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
}

// MARK: - 心率区间分布

private struct HRZoneBar: View {
    let zones: HeartRateZoneData

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("心率区间分布").font(.caption).foregroundColor(.secondary)
            GeometryReader { geo in
                HStack(spacing: 1) {
                    if zones.zone1Percent > 0 {
                        Rectangle().fill(Color.blue).frame(width: geo.size.width * CGFloat(zones.zone1Percent) / 100)
                    }
                    if zones.zone2Percent > 0 {
                        Rectangle().fill(Color.green).frame(width: geo.size.width * CGFloat(zones.zone2Percent) / 100)
                    }
                    if zones.zone3Percent > 0 {
                        Rectangle().fill(Color.yellow).frame(width: geo.size.width * CGFloat(zones.zone3Percent) / 100)
                    }
                    if zones.zone4Percent > 0 {
                        Rectangle().fill(Color.orange).frame(width: geo.size.width * CGFloat(zones.zone4Percent) / 100)
                    }
                    if zones.zone5Percent > 0 {
                        Rectangle().fill(Color.red).frame(width: geo.size.width * CGFloat(zones.zone5Percent) / 100)
                    }
                }
                .cornerRadius(4)
            }
            .frame(height: 8)
            HStack(spacing: 8) {
                zoneLegend("Z1", color: .blue)
                zoneLegend("Z2", color: .green)
                zoneLegend("Z3", color: .yellow)
                zoneLegend("Z4", color: .orange)
                zoneLegend("Z5", color: .red)
            }
            .font(.caption2)
        }
        .padding(.vertical, 6)
    }

    private func zoneLegend(_ label: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundColor(.secondary)
        }
    }
}

// MARK: - AI 综合评估

private struct AISummaryCard: View {
    let report: MorningReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI 综合评估").font(.caption).foregroundColor(.green)
            HStack(spacing: 12) {
                ScoreCircle(score: report.llmScore)
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
}

private struct ScoreCircle: View {
    let score: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.green.opacity(0.3), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(.headline)
                .foregroundColor(.green)
        }
        .frame(width: 50, height: 50)
    }
}

// MARK: - 建议 Tab

private struct AdviceSection<Row: View>: View {
    let report: MorningReport
    @Binding var adviceTab: Int
    let adviceRow: (String) -> Row

    var body: some View {
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
}

// MARK: - 详细报告折叠

private struct DetailToggle: View {
    @Binding var detailExpanded: Bool

    var body: some View {
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
}

private struct DetailContent: View {
    let report: MorningReport

    var body: some View {
        Text(report.llmDetail)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 8)
    }
}

// MARK: - 底部操作按钮

private struct BottomActionButtons: View {
    let onCameraTap: () -> Void
    let onReportTap: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Divider()
            HStack(spacing: 12) {
                actionButton(
                    icon: "camera.viewfinder",
                    title: "拍食物",
                    color: .pink,
                    action: onCameraTap
                )
                actionButton(
                    icon: "doc.text.fill",
                    title: "报告解读",
                    color: .blue,
                    action: onReportTap
                )
            }
        }
        .padding(.top, 8)
    }

    private func actionButton(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.1))
            .cornerRadius(8)
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

/// DateFormatter 单例：避免每帧重建
private enum FeedbackDateTimeFormatter {
    static let shared: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}

/// 反馈按钮按下时的 scaleEffect 反馈
private struct FeedbackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

/// 简化24h时间条（用于报告页展示）
struct SimpleTimelineBar: View {
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(StickState.daySchedule) { segment in
                    let width = geo.size.width * CGFloat(segment.endMinute - segment.startMinute) / 1440.0
                    Rectangle()
                        .fill(colorForState(segment.state))
                        .frame(width: max(1, width))
                }
            }
        }
        .background(Color(white: 0.15))
        .cornerRadius(6)
    }

    private func colorForState(_ state: StickState) -> Color {
        switch state {
        case .walk: return .green
        case .sit: return .orange
        case .stand: return .blue
        case .sleep: return .purple
        }
    }
}
