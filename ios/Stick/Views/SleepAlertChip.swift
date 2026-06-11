import SwiftUI

/// 睡眠时浮现的异常提示小章：红色胶囊 + 三角警示 + "N 项异常"
///  - 持续轻微脉冲（scale + shadow）吸引注意
///  - 点击 → onTap 回调（外部 present 报告 sheet）
struct SleepAlertChip: View {
    let count: Int
    let onTap: () -> Void

    @State private var pulse: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .heavy))
                Text("\(count) 项异常")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .tracking(0.4)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(
                Capsule()
                    .fill(severityColor)
            )
            .overlay(
                Capsule()
                    .stroke(severityColor.opacity(0.35), lineWidth: 1.2)
            )
            .shadow(
                color: severityColor.opacity(pulse ? 0.55 : 0.18),
                radius: pulse ? 10 : 3,
                y: 1
            )
            .scaleEffect(pulse ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var severityColor: Color {
        Color(red: 0.95, green: 0.30, blue: 0.20)  // 警示红
    }
}

// MARK: - 睡眠异常报告 sheet (告警弹窗 — 由 SleepAlertChip 触发)

struct SleepAnomalyReportView: View {
    var onClose: () -> Void

    private let issues: [SleepIssue] = [
        SleepIssue(time: "02:34", title: "心率过缓", detail: "最低 47 bpm · 持续 8 秒 · 已自行恢复",
                  severity: .moderate, icon: "heart.fill"),
        SleepIssue(time: "04:05", title: "疑似呼吸暂停", detail: "本次 1 次 · 12 秒 · SpO₂ 一过性 92%；近 7 日累计 3 次类似事件，最低 SpO₂ 87% (8 天前)",
                  severity: .moderate, icon: "lungs.fill"),
    ]

    private let aiAnalysis = AIAnalysis(
        riskLevel: .moderate,
        title: "AI 综合分析",
        summary: "结合本次 + 近 7 日数据，AI 模型评估您存在中等程度的 OSA 倾向。",
        findings: [
            "本次记录 1 次疑似呼吸暂停 (12 秒, SpO₂ 92%)",
            "近 7 日累计 3 次类似事件，最低 SpO₂ 87% (8 天前凌晨 3:42)",
            "单次最长暂停 18 秒；AHI 估算约 5–15 次/小时 (轻度–中度区间)",
            "事件多发生在 REM 仰卧期，符合 OSA 典型特征",
        ],
        osaIndicator: "提示存在 OSA (阻塞性睡眠呼吸暂停) 倾向",
        recommendation: "建议尽快预约睡眠专科门诊，必要时安排 PSG 多导睡眠图监测以明确诊断。近期可尝试侧卧睡姿、避免酒精与安眠药、控制体重；若症状加重（白天嗜睡、夜间憋醒）请立即就诊。"
    )

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.bgTop.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                Rectangle()
                    .fill(Theme.borderSoft)
                    .frame(height: 0.5)
                    .padding(.horizontal, 20)

                ScrollView {
                    VStack(spacing: 0) {
                        summaryCard
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 16)

                        Rectangle()
                            .fill(Theme.borderSoft)
                            .frame(height: 0.5)
                            .padding(.horizontal, 20)

                        // 异常事件 — 顶部最显眼
                        VStack(spacing: 0) {
                            sectionHeader("异常事件")
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                .padding(.bottom, 8)

                            ForEach(Array(issues.enumerated()), id: \.offset) { idx, issue in
                                SleepIssueRow(issue: issue)
                                if idx < issues.count - 1 {
                                    Rectangle()
                                        .fill(Theme.borderSoft)
                                        .frame(height: 0.5)
                                        .padding(.leading, 90)
                                }
                            }
                        }
                        .padding(.bottom, 20)

                        Rectangle()
                            .fill(Theme.borderSoft)
                            .frame(height: 0.5)
                            .padding(.horizontal, 20)

                        // AI 综合分析 — 下方解读
                        aiCard
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 28)
                    }
                }
            }
        }
    }

    // MARK: 子视图

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(StickState.sleep.accent)
                    Text("睡眠异常报告")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Theme.navy)
                }
                Text("昨夜 22:30 – 今晨 07:00 · 检测到 \(issues.count) 项事件")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.slate)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.navy)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.card))
                    .overlay(Circle().stroke(Theme.borderSoft, lineWidth: 1))
            }
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(issues.count)")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundColor(.red.opacity(0.85))
                Text("异常事件")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.slate)
            }

            Rectangle()
                .fill(Theme.borderSoft)
                .frame(width: 0.5, height: 48)

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                stat("心率过缓", "1")
                stat("呼吸暂停", "1")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.red.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.red.opacity(0.12), lineWidth: 0.6)
        )
    }

    /// AI 综合分析卡片
    private var aiCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 头部：AI 标 + 风险 chip
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                    Text("AI")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(0.6)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(aiColor)
                )

                Text(aiAnalysis.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.navy)

                Spacer()

                riskChip
            }

            // 一句话总结
            Text(aiAnalysis.summary)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Theme.navy)
                .lineSpacing(3)

            // 关键发现
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(aiAnalysis.findings.enumerated()), id: \.offset) { idx, finding in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(idx + 1).")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(aiColor.opacity(0.7))
                            .frame(width: 14, alignment: .leading)
                        Text(finding)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Theme.slate)
                            .lineSpacing(2)
                    }
                }
            }
            .padding(.vertical, 4)

            // OSA 提示（高亮警告行）
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.red)
                Text(aiAnalysis.osaIndicator)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.red.opacity(0.08))
            )

            // 建议
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(StickState.walk.accent)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("建议")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.slate)
                        .tracking(0.4)
                    Text(aiAnalysis.recommendation)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Theme.navy)
                        .lineSpacing(3)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(aiColor.opacity(0.35), lineWidth: 0.8)
        )
        .shadow(color: aiColor.opacity(0.08), radius: 12, y: 2)
    }

    private var riskChip: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(riskColor)
                .frame(width: 6, height: 6)
            Text(riskLabel)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(riskColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(
            Capsule().fill(riskColor.opacity(0.12))
        )
    }

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(Theme.slate)
            Spacer()
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Theme.slate)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.navy)
        }
    }

    // AI 配色
    private var aiColor: Color {
        Color(red: 0.39, green: 0.40, blue: 0.95)  // 靛紫
    }

    private var riskColor: Color {
        switch aiAnalysis.riskLevel {
        case .low:     return Color(red: 0.20, green: 0.78, blue: 0.55)  // 绿
        case .moderate: return Color(red: 0.95, green: 0.65, blue: 0.10)  // 琥珀
        case .high:   return Color(red: 0.95, green: 0.30, blue: 0.20)  // 红
        }
    }

    private var riskLabel: String {
        switch aiAnalysis.riskLevel {
        case .low:     return "低度风险"
        case .moderate: return "中度风险"
        case .high:   return "高度风险"
        }
    }
}

// MARK: - 异常项

struct SleepIssue: Identifiable {
    let id = UUID()
    let time: String
    let title: String
    let detail: String
    let severity: Severity
    let icon: String

    enum Severity { case mild, moderate }
}

struct SleepIssueRow: View {
    let issue: SleepIssue

    var body: some View {
        HStack(spacing: 12) {
            Text(issue.time)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.slate)
                .frame(width: 46, alignment: .leading)

            ZStack {
                Circle()
                    .fill(severityColor.opacity(0.14))
                Image(systemName: issue.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(severityColor)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(issue.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.navy)
                    Text(severityLabel)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.4)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(severityColor)
                        )
                }
                Text(issue.detail)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.slate)
                    .lineLimit(3)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Theme.mist)
        }
        .frame(minHeight: 64)
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var severityColor: Color {
        switch issue.severity {
        case .mild:     return Color(red: 0.95, green: 0.65, blue: 0.10)  // 琥珀
        case .moderate: return Color(red: 0.95, green: 0.30, blue: 0.20)  // 警示红
        }
    }

    private var severityLabel: String {
        switch issue.severity {
        case .mild:     return "轻度"
        case .moderate: return "中度"
        }
    }
}

// MARK: - AI 分析

struct AIAnalysis {
    enum RiskLevel { case low, moderate, high }

    let riskLevel: RiskLevel
    let title: String
    let summary: String
    let findings: [String]
    let osaIndicator: String
    let recommendation: String
}
