import SwiftUI

/// AI 风险分析报告 — 完整 sheet 视图
struct AIAnalysisView: View {
    let report: AIAnalysisReport
    var onClose: () -> Void

    private var timeText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE HH:mm"
        return f.string(from: report.timestamp)
    }

    private var timeShort: String {
        StickState.formatMinute(StickState.minutesOfDay(report.timestamp))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶栏
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headlineCard
                    vitalCard
                    reasonSection
                    recSection
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.bgTop.ignoresSafeArea())
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI 健康分析")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2.0)
                    .foregroundColor(Theme.slate)
                Text(timeText)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Theme.navy)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.navy)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.card))
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Theme.bgTop)
    }

    // MARK: - 结论卡

    private var headlineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(report.risk.color)
                Text("RISK ALERT · 风险预警")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundColor(report.risk.color)
                Spacer()
                riskBadge
            }
            Text(report.headline)
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundColor(Theme.navy)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(report.risk.color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(report.risk.color.opacity(0.35), lineWidth: 1)
        )
    }

    private var riskBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(report.risk.color)
                .frame(width: 7, height: 7)
            Text("\(report.risk.englishLabel) · \(report.risk.label)度风险")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(report.risk.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill(report.risk.color.opacity(0.12))
        )
    }

    // MARK: - 关键指标

    private var vitalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("关键指标 · KEY VITALS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.6)
                .foregroundColor(Theme.slate)

            HStack(alignment: .top, spacing: 10) {
                vitalItem(title: "心率", value: "\(report.heartRate)", unit: "bpm",
                          tone: report.risk.color)
                vitalItem(title: "基线", value: "\(report.restingHR)", unit: "bpm",
                          tone: Theme.slate)
                vitalItem(title: "HRV", value: "\(report.hrv)", unit: "ms",
                          tone: report.hrv < 30 ? report.risk.color : Theme.slate)
                vitalItem(title: "持续", value: "\(report.sustainedMinutes)", unit: "min",
                          tone: report.risk.color)
            }

            HStack {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                Text("较 7 日同时段均值 \(report.deviationPct >= 0 ? "+" : "")\(report.deviationPct)%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(report.risk.color)
                Spacer()
                Text(timeShort)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.slate)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func vitalItem(title: String, value: String, unit: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(Theme.slate)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(tone)
                Text(unit)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.slate)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    // MARK: - 分析

    private var reasonSection: some View {
        sectionCard(
            title: "AI 分析 · ANALYSIS",
            icon: "magnifyingglass",
            accent: Theme.navy
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(report.reasons.enumerated()), id: \.offset) { idx, txt in
                    HStack(alignment: .top, spacing: 10) {
                        Text(String(format: "%02d", idx + 1))
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(report.risk.color)
                            .frame(width: 18, alignment: .leading)
                        Text(txt)
                            .font(.system(size: 13, weight: .regular, design: .serif))
                            .foregroundColor(Theme.navy)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - 建议

    private var recSection: some View {
        sectionCard(
            title: "建议 · RECOMMENDATIONS",
            icon: "lightbulb",
            accent: report.risk.color
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(report.recommendations.enumerated()), id: \.offset) { idx, txt in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(report.risk.color)
                            .padding(.top, 1)
                        Text(txt)
                            .font(.system(size: 13, weight: .regular, design: .serif))
                            .foregroundColor(Theme.navy)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - 区块容器

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String, icon: String, accent: Color, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(accent)
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundColor(Theme.slate)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    // MARK: - 页脚

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .bold))
                Text("AI·v1.2 · 基于近 7 日 + 实时数据")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(0.5)
            }
            .foregroundColor(Theme.slate)
            Text("本报告仅供参考，不构成医疗建议。如有持续不适请咨询专业医师。")
                .font(.system(size: 9, weight: .regular, design: .serif))
                .foregroundColor(Theme.mist)
                .lineSpacing(2)
        }
        .padding(.top, 4)
    }
}
