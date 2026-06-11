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

// MARK: - 睡眠异常报告 sheet

struct SleepReportView: View {
    var onClose: () -> Void

    private let issues: [SleepIssue] = [
        SleepIssue(time: "02:34", title: "心率过缓", detail: "最低 47 bpm · 持续 8 秒 · 已自行恢复",
                  severity: .moderate, icon: "heart.fill"),
        SleepIssue(time: "03:12", title: "翻身频繁", detail: "1 分钟内翻身 3 次 · 处于浅睡 N1 期",
                  severity: .mild, icon: "arrow.left.arrow.right"),
        SleepIssue(time: "04:05", title: "疑似呼吸暂停", detail: "检测到 1 次 · 时长 12 秒 · SpO₂ 一过性 92%",
                  severity: .moderate, icon: "lungs.fill"),
    ]

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
                            .padding(.bottom, 20)

                        Rectangle()
                            .fill(Theme.borderSoft)
                            .frame(height: 0.5)
                            .padding(.horizontal, 20)

                        VStack(spacing: 0) {
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
                        .padding(.top, 4)
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
            // 大数字
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
                stat("翻身频繁", "1")
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
            // 时间
            Text(issue.time)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(Theme.slate)
                .frame(width: 46, alignment: .leading)

            // 图标
            ZStack {
                Circle()
                    .fill(severityColor.opacity(0.14))
                Image(systemName: issue.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(severityColor)
            }
            .frame(width: 38, height: 38)

            // 文字
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
                    .lineLimit(2)
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
